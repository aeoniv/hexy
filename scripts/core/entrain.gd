class_name Entrain
extends RefCounted

## THE USER'S OWN CLOCK, GUESSED FROM ZEITGEBERS THE PHONE ALREADY HAS.
##
## [FlyCircadianClock] takes `update(hour)` on wall-clock solar hour, which
## entrains the creature to whoever built the phone's timezone table, not to
## the person holding it. A night owl's "morning" is not 07:00; this file
## estimates how far the user's rhythm sits from wall time -- a phase offset
## in hours -- from the two zeitgebers a phone can read without a wearable:
## light (lux) and motion, plus screen-on and whether the user spoke to the
## creature. [method internal_hour] then hands [FlyCircadianClock] the hour
## IT should believe, instead of the hour the sun believes.
##
## PURE AND DETERMINISTIC, LIKE [Geo] AND [Clock]. No Godot Input, no
## autoload, no wall-clock read of its own -- every sample is pushed in by a
## caller that already read the sensors, so a test drives a week of a night
## owl's days without a phone anywhere in sight.
##
## THE MODEL IS DELIBERATELY SMALL. This is a centre-of-mass estimate over a
## ring buffer, not a Kalman filter or a real phase-response-curve model: the
## fly's own bimodal shape already carries the nuance, and all this owes it is
## one number -- how many hours to slide the sun by -- and a light-only PRC
## advisory. Caffeine, meals, and any other zeitgeber are out of scope by the
## task that asked for this file, not by an oversight.

## Hours the user's morning peak (fly's own is 07:00) sits from wall clock's.
const FLY_MORNING_H := 7.0
## offset_h is clamped here both ways -- a bigger drift than half a day would
## mean the estimate is confused, not that the user lives on Mars.
const OFFSET_CLAMP_H := 6.0
## Below this many samples confidence cannot rise past a token floor: a
## handful of readings describe a minute, not a rhythm.
const CONFIDENCE_SAMPLE_FLOOR := 8
## Bright enough that a light sample counts as daylight/screen glare rather
## than ambient dark, for both the wake/sleep centroid and the PRC advisory.
const BRIGHT_LUX := 50.0
## A PRC shift capped at this many hours -- the fly's own peaks are ~1.8h
## wide, so a full-day shove from one bright sample would be a claim this
## model has no business making.
const MAX_SHIFT_H := 1.5


## ONE OBSERVED MINUTE. Kept as a plain Dictionary, not a class, so
## [method to_dict] round-trips it without a second (de)serialiser.
##
## `day` is a synthetic day index, entirely the caller's business: it exists
## only so the ring buffer can be trimmed to "the last N days" without this
## file ever reading a real calendar.
class Sample:
	var day: int
	var wall_hour: float
	var lux: float
	var motion: float
	var screen_on: bool
	var spoke: bool

	func to_dict() -> Dictionary:
		return {"day": day, "wall_hour": wall_hour, "lux": lux,
			"motion": motion, "screen_on": screen_on, "spoke": spoke}

	static func from_dict(d: Dictionary) -> Sample:
		var s := Sample.new()
		s.day = int(d.get("day", 0))
		s.wall_hour = float(d.get("wall_hour", 0.0))
		s.lux = float(d.get("lux", -1.0))
		s.motion = float(d.get("motion", 0.0))
		s.screen_on = bool(d.get("screen_on", false))
		s.spoke = bool(d.get("spoke", false))
		return s


## Hours the user's internal clock leads (+) or lags (-) wall time. Zero
## until enough samples say otherwise -- an unentrained creature runs on the
## sun, which is the least wrong default.
var phase_offset_h: float = 0.0
## 0..1. Rises with sample count and with how tightly the activity centroid
## holds together; decays a fixed amount whenever a caller notices no
## samples arrived (see [method decay]) rather than by this file watching a
## clock of its own.
var confidence: float = 0.0
## The ring buffer. A plain Array, trimmed by day index in [method sample] --
## no fixed capacity, because "the last N days" is a day count, not a row
## count, and a chatty day must not evict a whole quiet one.
var samples: Array[Sample] = []


## THE TWO KNOBS, HANDED OUT AS A DICTIONARY. HexyConfig's schema is owned
## elsewhere and this task does not touch the registry -- a caller that wants
## these live merges this dict into its own schema instead.
static func default_config() -> Dictionary:
	return {
		"entrain.days": 7,
		"entrain.min_samples": 48,
	}


## ONE OBSERVATION. `lux < 0` means "unknown" and is kept out of every light
## computation rather than coerced to zero, which would read as "pitch dark"
## and bias the centroid toward night. `day` lets [method estimate] window to
## the caller's own notion of "the last N days" without a wall-clock read
## here.
func sample(day: int, wall_hour: float, lux: float, motion: float,
		screen_on: bool, spoke: bool) -> void:
	var s := Sample.new()
	s.day = day
	s.wall_hour = fposmod(wall_hour, 24.0)
	s.lux = lux
	s.motion = clampf(motion, 0.0, 1.0)
	s.screen_on = screen_on
	s.spoke = spoke
	samples.append(s)


## Drops samples older than `days` relative to `latest_day`, so a long-running
## caller does not grow this ring forever. Not called from [method sample]
## itself -- a caller pushing samples one minute at a time decides when a
## trim is worth the O(n) pass, this file just does the arithmetic.
func trim(latest_day: int, days: int) -> void:
	var cutoff := latest_day - days + 1
	var kept: Array[Sample] = []
	for s in samples:
		if s.day >= cutoff:
			kept.append(s)
	samples = kept


## WHERE THE USER'S DAY LIVES, PULLED FROM WHAT THE PHONE SAW.
##
## Every "activity" sample -- bright light, real motion, the screen on, or a
## word spoken to the creature -- casts a vote for its wall_hour on a 24-hour
## circle. Wall-clock hours wrap at midnight, so a night owl's activity that
## spans 23:00-03:00 must not average to "11:00" the way a naive mean would:
## the vote is cast as a unit vector (cos/sin of the hour turned into an
## angle) and averaged as a vector, which is exactly how [Geo]-style bearing
## math handles wraparound -- the same reason bearings are never just
## subtracted.
##
## `wake_h` is that circular centroid's leading edge and `sleep_h` its
## trailing one, each estimated as the centroid +-  half the activity span's
## own angular half-width (a rough constant, not fit per user, matching this
## file's stated smallness). `offset_h` is wake_h shifted so the fly's own
## 07:00 dawn lines up with it.
func estimate() -> Dictionary:
	if samples.is_empty():
		return {"offset_h": 0.0, "confidence": 0.0, "wake_h": FLY_MORNING_H,
			"sleep_h": FLY_MORNING_H + 16.0}

	var sum_x := 0.0
	var sum_y := 0.0
	var weight_total := 0.0
	var active_count := 0
	# Per-day circular centroids, kept separately from the pooled sums above.
	# WHY TWO PASSES OF BOOKKEEPING: the pooled vector below answers "where in
	# the day does activity sit" and its own spread naturally reflects how
	# WIDE the user's active window is (a night owl's 16h span is never going
	# to look as tight as a nap). Day-to-day CONSISTENCY is a different
	# question -- does that window land in the same place night after night --
	# and conflating the two would punish a wide-but-steady rhythm with the
	# same low confidence as a rhythm that is genuinely erratic. So each day
	# gets its own centroid, and confidence below reads the agreement BETWEEN
	# those, not the width of any one of them.
	var day_sums: Dictionary = {}
	for s in samples:
		var activity := s.motion
		if s.lux >= 0.0 and s.lux >= BRIGHT_LUX:
			activity = maxf(activity, 0.6)
		if s.screen_on:
			activity = maxf(activity, 0.4)
		if s.spoke:
			activity = maxf(activity, 0.8)
		if activity <= 0.0:
			continue
		active_count += 1
		var angle := s.wall_hour / 24.0 * TAU
		sum_x += cos(angle) * activity
		sum_y += sin(angle) * activity
		weight_total += activity

		var acc: Dictionary = day_sums.get(s.day, {"x": 0.0, "y": 0.0, "w": 0.0})
		acc["x"] += cos(angle) * activity
		acc["y"] += sin(angle) * activity
		acc["w"] += activity
		day_sums[s.day] = acc

	if weight_total <= 0.0:
		return {"offset_h": 0.0, "confidence": 0.0, "wake_h": FLY_MORNING_H,
			"sleep_h": FLY_MORNING_H + 16.0}

	# Cross-day agreement: each day's own centroid cast as a unit vector, then
	# averaged. 1.0 means every day's activity centred on the same hour; it
	# falls toward 0.0 as the centre itself wanders from day to day.
	var cross_x := 0.0
	var cross_y := 0.0
	var day_count := 0
	for day in day_sums.keys():
		var acc: Dictionary = day_sums[day]
		if acc["w"] <= 0.0:
			continue
		var day_angle := atan2(acc["y"], acc["x"])
		cross_x += cos(day_angle)
		cross_y += sin(day_angle)
		day_count += 1
	var cross_day_consistency := 0.0
	if day_count > 0:
		cross_day_consistency = sqrt(cross_x * cross_x + cross_y * cross_y) / float(day_count)

	var mean_angle := atan2(sum_y / weight_total, sum_x / weight_total)
	var centroid_h := fposmod(mean_angle / TAU * 24.0, 24.0)
	# Mean resultant length: 1.0 when every vote lands on the same hour, and
	# falling toward 0 the more the activity is smeared across the day -- the
	# circular-statistics analogue of low variance, reused as this file's
	# consistency signal for confidence.
	var resultant := sqrt(sum_x * sum_x + sum_y * sum_y) / weight_total

	# Half the activity block, in hours: a tight resultant (near 1.0) means a
	# short, well-defined wake window; a loose one spreads it wider, up to
	# half a day.
	var half_span_h: float = lerpf(12.0, 2.0, clampf(resultant, 0.0, 1.0))
	var wake_h := fposmod(centroid_h - half_span_h, 24.0)
	var sleep_h := fposmod(centroid_h + half_span_h, 24.0)

	var offset_h := clampf(wake_h - FLY_MORNING_H, -OFFSET_CLAMP_H, OFFSET_CLAMP_H)
	# Wrap the raw difference into the shorter arc before clamping, so a
	# lark whose wake_h sits just past midnight (e.g. 23:00) reads as a small
	# negative offset, not a spurious +22h that the clamp would then mangle.
	var raw_diff := wake_h - FLY_MORNING_H
	if raw_diff > 12.0:
		raw_diff -= 24.0
	elif raw_diff < -12.0:
		raw_diff += 24.0
	offset_h = clampf(raw_diff, -OFFSET_CLAMP_H, OFFSET_CLAMP_H)

	var count_conf := clampf(float(active_count) / float(CONFIDENCE_SAMPLE_FLOOR * 6), 0.0, 1.0)
	var consistency_conf := clampf(cross_day_consistency, 0.0, 1.0)
	confidence = clampf(count_conf * consistency_conf, 0.0, 1.0)
	phase_offset_h = offset_h

	return {"offset_h": offset_h, "confidence": confidence, "wake_h": wake_h,
		"sleep_h": sleep_h}


## THE HOUR [FlyCircadianClock] SHOULD BELIEVE. A wall hour of 23:00 for a
## user whose offset is +4h (their morning starts four hours late) reads to
## the fly as 19:00 -- still their evening, not the fly's own midnight torpor.
func internal_hour(wall_hour: float) -> float:
	return fposmod(wall_hour - phase_offset_h, 24.0)


## A ONE-LIGHT-SAMPLE PHASE-RESPONSE ADVISORY.
##
## The textbook human PRC: bright light before the trough (here, the six
## hours BEFORE the estimated wake) advances the clock; bright light after
## the trough (the six hours AFTER estimated sleep) delays it. Everything
## else -- daytime light, or light too dim to matter -- is a no-op. Caffeine,
## meals, and darkness therapy are out of scope by the task, not missing by
## accident.
func advice(wall_hour: float, lux: float) -> Dictionary:
	if lux < BRIGHT_LUX:
		return {"key": "none", "shift_h": 0.0}

	var est := estimate()
	var wake_h: float = est["wake_h"]
	var sleep_h: float = est["sleep_h"]
	var h := fposmod(wall_hour, 24.0)

	var before_wake := fposmod(wake_h - h, 24.0)
	if before_wake > 0.0 and before_wake <= 6.0:
		var shift: float = lerpf(MAX_SHIFT_H, 0.0, before_wake / 6.0)
		return {"key": "light_advances", "shift_h": shift}

	var after_sleep := fposmod(h - sleep_h, 24.0)
	if after_sleep >= 0.0 and after_sleep <= 6.0:
		var shift: float = lerpf(MAX_SHIFT_H, 0.0, after_sleep / 6.0)
		return {"key": "light_delays", "shift_h": shift}

	return {"key": "none", "shift_h": 0.0}


## CALLED WHEN A CALLER NOTICES A STRETCH WITH NO SAMPLES -- this file reads
## no clock of its own, so it cannot decay itself on a timer. `ticks` is
## whatever unit the caller's own gap is measured in (minutes, checks,
## whatever); each tick knocks a fixed fraction off confidence, floored at
## zero rather than allowed to go negative.
func decay(ticks: int, rate: float = 0.02) -> void:
	confidence = clampf(confidence - rate * float(maxf(ticks, 0.0)), 0.0, 1.0)


## THE WHOLE STATE, FOR A CALLER THAT PERSISTS THIS BETWEEN RUNS.
func to_dict() -> Dictionary:
	var rows: Array = []
	for s in samples:
		rows.append(s.to_dict())
	return {
		"phase_offset_h": phase_offset_h,
		"confidence": confidence,
		"samples": rows,
	}


## THE INVERSE OF [method to_dict]. Builds a fresh instance rather than
## mutating an existing one, matching the load pattern the rest of this
## codebase's pure classes use.
static func from_dict(d: Dictionary) -> Entrain:
	var e := Entrain.new()
	e.phase_offset_h = float(d.get("phase_offset_h", 0.0))
	e.confidence = float(d.get("confidence", 0.0))
	var rows: Array = d.get("samples", [])
	var loaded: Array[Sample] = []
	for row in rows:
		loaded.append(Sample.from_dict(row))
	e.samples = loaded
	return e
