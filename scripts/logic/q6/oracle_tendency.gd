class_name OracleTendency
extends RefCounted

## N12 steps 2+3 — TENDENCY TABLE + RECONSTRUCTION.
## T: 64x64 transition counts (row = previous hexagram, col = next), with row
## totals. Hexagram ids are core bits 0..63 (KingWen convention: bit i = line
## i+1 from the bottom, yang = 1). Probabilities are Laplace-smoothed:
##   p(h | prev) = (T[prev][h] + 1) / (row[prev] + 64)
## Persisted sparse at user://oracle/tendency.json (only non-zero cells), well
## under 40 KB. path() output is a HYPOTHESIS for a gap; callers must never
## write it into the log as fact.

const PATH: String = "user://oracle/tendency.json"
const N: int = 64

var file_path: String = PATH
var counts := PackedInt32Array()   # N*N, row-major [prev*N + h]
var rows := PackedInt32Array()     # N row totals
var hour_hits := PackedInt32Array()   # 24
var hour_total := PackedInt32Array()  # 24

## N15/N12 §7 -- DAY BOOKKEEPING (additive). observe() stamps the wall day it
## ran on: `days` counts distinct days with at least one row (Journey's
## APPROACH counter), `dawn_day` is the last day a row landed in the dawn
## hours (DAWN_HOURS, for Needs.dawn_cast_days_ago: there is no hexy_place
## reader on this root, so "a cast at dawn" is the only dawn there is), and the
## weekly mean-surprise ring (`week_means`, oldest first, WEEK_RING long) is
## what Journey's RESURRECTION reads through surprise_falling_weeks().
const DAWN_HOURS: Array[int] = [5, 6, 7]
const WEEK_RING: int = 12

var days: int = 0
var last_day: int = -1
var dawn_day: int = -1
var week_cur: int = -1
var week_sum: float = 0.0
var week_n: int = 0
var week_means: Array = []


func _init(from_path: String = PATH) -> void:
	file_path = from_path
	reset()


func reset() -> void:
	counts.resize(N * N)
	counts.fill(0)
	rows.resize(N)
	rows.fill(0)
	hour_hits.resize(24)
	hour_hits.fill(0)
	hour_total.resize(24)
	hour_total.fill(0)
	days = 0
	last_day = -1
	dawn_day = -1
	week_cur = -1
	week_sum = 0.0
	week_n = 0
	week_means = []


## The wall day, as every other clock in the app counts it (unix days).
static func today() -> int:
	return int(floor(float(Time.get_unix_time_from_system()) / 86400.0))


func p(prev_h: int, h: int) -> float:
	prev_h &= 63
	h &= 63
	return float(counts[prev_h * N + h] + 1) / float(rows[prev_h] + N)


## Record one transition. If hour (0..23) is given, first score whether the
## argmax forecast from prev_h would have hit h (for regularity()).
## `day` (unix day) stamps the day bookkeeping; -1 means the wall clock's today.
func observe(prev_h: int, h: int, hour: int = -1, day: int = -1) -> void:
	prev_h &= 63
	h &= 63
	if hour >= 0 and hour < 24:
		hour_total[hour] += 1
		if rows[prev_h] > 0 and _argmax(prev_h) == h:
			hour_hits[hour] += 1
	_stamp_day(day if day >= 0 else today(), hour, surprise(prev_h, h))
	counts[prev_h * N + h] += 1
	rows[prev_h] += 1


func _stamp_day(day: int, hour: int, s: float) -> void:
	## Days only move forward: a later day is a new day, an earlier stamp
	## (a clock set back) is not counted twice.
	if day > last_day:
		days += 1
		last_day = day
	if hour in DAWN_HOURS:
		dawn_day = day
	var week: int = day / 7
	if week != week_cur:
		if week_cur >= 0 and week_n > 0:
			week_means.append(week_sum / float(week_n))
			while week_means.size() > WEEK_RING:
				week_means.remove_at(0)
		week_cur = week
		week_sum = 0.0
		week_n = 0
	week_sum += s
	week_n += 1


## Mean regularity over the hours that hold at least one row (an hour never
## observed says nothing, so it is not counted as 0). 0 with no rows.
func regularity_mean() -> float:
	var sum: float = 0.0
	var n: int = 0
	for i in 24:
		if hour_total[i] > 0:
			sum += regularity(i)
			n += 1
	return sum / float(n) if n > 0 else 0.0


## Days since the last dawn-hour row, -1.0 when there never was one.
func dawn_cast_days_ago(now_day: int = -1) -> float:
	if dawn_day < 0:
		return -1.0
	var d: int = now_day if now_day >= 0 else today()
	return float(maxi(0, d - dawn_day))


## Consecutive COMPLETED weeks, newest first, in which the mean surprise fell
## below the week before. 0 with fewer than two completed weeks.
func surprise_falling_weeks() -> int:
	var n: int = 0
	var i: int = week_means.size() - 1
	while i >= 1 and float(week_means[i]) < float(week_means[i - 1]):
		n += 1
		i -= 1
	return n


## The read-only bundle Journey and Needs consume.
func stats(now_day: int = -1) -> Dictionary:
	return {
		"days": days,
		"regularity_mean": regularity_mean(),
		"dawn_cast_days_ago": dawn_cast_days_ago(now_day),
		"surprise_falling_weeks": surprise_falling_weeks(),
		"week_means": week_means.duplicate(),
	}


func _argmax(prev_h: int) -> int:
	var best := 0
	var best_c := -1
	for h in N:
		var c := counts[prev_h * N + h]
		if c > best_c:
			best_c = c
			best = h
	return best


## Top-k next hexagrams from h: Array of {h, p}, most probable first.
func forecast(h: int, k: int = 3) -> Array[Dictionary]:
	h &= 63
	var all: Array[Dictionary] = []
	for j in N:
		all.append({"h": j, "p": p(h, j)})
	all.sort_custom(func(a, b): return a.p > b.p or (a.p == b.p and a.h < b.h))
	return all.slice(0, clampi(k, 0, N))


## Natural-log surprise, -ln p(h | prev_h). An empty row gives exactly ln(64).
func surprise(prev_h: int, h: int) -> float:
	return -log(p(prev_h, h))


## Hit rate of the argmax forecast for transitions observed at this hour.
func regularity(hour: int) -> float:
	if hour < 0 or hour >= 24 or hour_total[hour] == 0:
		return 0.0
	return float(hour_hits[hour]) / float(hour_total[hour])


func regularity_all() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 24:
		out.append(regularity(i))
	return out


## Most probable value (0/1) of line i (0 = bottom) given the other 5 known
## lines of `known`. With prev_h, compares row T[prev_h] at the two candidate
## hexagrams; without, compares their incoming column mass.
func fill_line(known: int, i: int, prev_h: int = -1) -> int:
	var c0 := (known & 63) & ~(1 << i)
	var c1 := c0 | (1 << i)
	var s0 := 0.0
	var s1 := 0.0
	if prev_h >= 0:
		s0 = p(prev_h, c0)
		s1 = p(prev_h, c1)
	else:
		for r in N:
			s0 += counts[r * N + c0]
			s1 += counts[r * N + c1]
	return 1 if s1 > s0 else 0


## Viterbi: most probable sequence h_a -> ... -> h_b over `steps` transitions.
## Returns steps+1 ids including both ends. Hypothesis only.
func path(h_a: int, h_b: int, steps: int) -> Array[int]:
	h_a &= 63
	h_b &= 63
	var out: Array[int] = [h_a]
	if steps <= 0:
		return out
	if steps == 1:
		out.append(h_b)
		return out
	var lp := PackedFloat64Array()
	lp.resize(N * N)
	for r in N:
		for c in N:
			lp[r * N + c] = log(p(r, c))
	# score[h] = best log-prob of reaching h at position t (1..steps-1)
	var score := PackedFloat64Array()
	score.resize(N)
	for h in N:
		score[h] = lp[h_a * N + h]
	var back: Array[PackedInt32Array] = []
	for t in range(2, steps):
		var ns := PackedFloat64Array()
		ns.resize(N)
		var bp := PackedInt32Array()
		bp.resize(N)
		for h in N:
			var best := -INF
			var arg := 0
			for g in N:
				var v := score[g] + lp[g * N + h]
				if v > best:
					best = v
					arg = g
			ns[h] = best
			bp[h] = arg
		score = ns
		back.append(bp)
	var best_g := 0
	var best_v := -INF
	for g in N:
		var v := score[g] + lp[g * N + h_b]
		if v > best_v:
			best_v = v
			best_g = g
	var mids: Array[int] = [best_g]
	for t in range(back.size() - 1, -1, -1):
		mids.push_front(back[t][mids[0]])
	out.append_array(mids)
	out.append(h_b)
	return out


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var cells := {}
	for i in N * N:
		if counts[i] > 0:
			cells[str(i)] = counts[i]
	var data := {"v": 1, "cells": cells, "hour_hits": Array(hour_hits), "hour_total": Array(hour_total),
		"days": days, "last_day": last_day, "dawn_day": dawn_day, "week_cur": week_cur,
		"week_sum": week_sum, "week_n": week_n, "week_means": week_means}
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


func load() -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	reset()
	var cells: Dictionary = parsed.get("cells", {})
	for k in cells:
		var i := int(k)
		if i >= 0 and i < N * N:
			counts[i] = int(cells[k])
			rows[i / N] += int(cells[k])
	var hh: Array = parsed.get("hour_hits", [])
	var ht: Array = parsed.get("hour_total", [])
	for i in mini(24, hh.size()):
		hour_hits[i] = int(hh[i])
	for i in mini(24, ht.size()):
		hour_total[i] = int(ht[i])
	## Day bookkeeping: absent on files written before it existed (defaults hold).
	days = int(parsed.get("days", 0))
	last_day = int(parsed.get("last_day", -1))
	dawn_day = int(parsed.get("dawn_day", -1))
	week_cur = int(parsed.get("week_cur", -1))
	week_sum = float(parsed.get("week_sum", 0.0))
	week_n = int(parsed.get("week_n", 0))
	week_means = []
	for m in parsed.get("week_means", []):
		week_means.append(float(m))
	return true
