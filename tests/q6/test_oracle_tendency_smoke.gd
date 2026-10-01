extends SceneTree

## ORACLE TENDENCY SMOKE — scripts/core/iching/oracle_tendency.gd (N12 steps 2+3).
## Prints === ALL PASS === or fails.

var _fails := 0
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		_fails += 1


func _initialize() -> void:
	var path := "user://oracle/tendency_smoke.json"
	var t := OracleTendency.new(path)
	_check(is_equal_approx(t.surprise(5, 9), log(64.0)), "empty row surprise == ln 64")

	var cyc := [3, 17, 42]
	var prev: int = cyc[0]
	for n in 6000:
		var h: int = cyc[(n + 1) % 3]
		t.observe(prev, h, n % 24)
		prev = h
	for i in 3:
		var a: int = cyc[i]
		var b: int = cyc[(i + 1) % 3]
		_check(t.p(a, b) > 0.95, "cycle edge %d->%d p=%.4f > 0.95" % [a, b, t.p(a, b)])
		_check(t.surprise(a, b) < 0.05, "cycle edge %d->%d surprise=%.4f ~0" % [a, b, t.surprise(a, b)])
		_check(int(t.forecast(a, 1)[0].h) == b, "forecast top-1 from %d is %d" % [a, b])
	var s_new := t.surprise(3, 60)
	_check(s_new >= log(64.0), "unseen edge 3->60 surprise=%.3f >= ln64=%.3f" % [s_new, log(64.0)])
	_check(t.regularity(5) > 0.95, "regularity(5)=%.3f" % t.regularity(5))
	_check(t.forecast(3, 5).size() == 5, "forecast k=5 returns 5")

	var pth := t.path(3, 42, 2)
	_check(pth == [3, 17, 42], "path(3,42,2) == [3,17,42] got %s" % str(pth))
	var pth3 := t.path(3, 3, 3)
	_check(pth3 == [3, 17, 42, 3], "path(3,3,3) == full cycle got %s" % str(pth3))
	# 17 = 0b010001: hide line bit 4, recover it from row of prev 3
	_check(t.fill_line(17 & ~(1 << 4), 4, 3) == 1, "fill_line recovers bit 4 of 17 given prev 3")
	_check(t.fill_line(17 | (1 << 1), 1) == 0, "fill_line recovers bit 1 of 17 by column mass")

	_check(t.save(), "save ok")
	var size := FileAccess.get_file_as_bytes(path).size()
	_check(size > 0 and size <= 40960, "file size %d <= 40 KB" % size)
	var u := OracleTendency.new(path)
	_check(u.load(), "load ok")
	_check(u.counts == t.counts and u.rows == t.rows, "counts + rows roundtrip")
	_check(u.hour_hits == t.hour_hits and u.hour_total == t.hour_total, "hour stats roundtrip")
	_check(is_equal_approx(u.surprise(42, 3), t.surprise(42, 3)), "surprise roundtrip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_day_bookkeeping(path)

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


## N15 §4 / N12 §7 -- days, dawn, regularity_mean, weekly surprise ring.
func _day_bookkeeping(path: String) -> void:
	var t := OracleTendency.new(path)
	_check(t.days == 0 and t.dawn_cast_days_ago(100) < 0.0 and t.surprise_falling_weeks() == 0, "fresh: 0 days, no dawn, 0 falling weeks")
	# day 700 (week 100): 3 rows at noon; day 701: 2 rows, one at 6h
	t.observe(1, 2, 12, 700)
	t.observe(2, 3, 12, 700)
	t.observe(3, 1, 12, 700)
	t.observe(1, 2, 6, 701)
	t.observe(2, 3, 12, 701)
	_check(t.days == 2, "two distinct days counted (%d)" % t.days)
	_check(is_equal_approx(t.dawn_cast_days_ago(704), 3.0), "dawn row at 6h on day 701 -> 3 days ago at 704 (%.1f)" % t.dawn_cast_days_ago(704))
	_check(t.regularity_mean() >= 0.0 and t.regularity_mean() <= 1.0, "regularity_mean in 0..1 (%.2f)" % t.regularity_mean())
	var st: Dictionary = t.stats(704)
	_check(int(st["days"]) == 2 and st.has("regularity_mean") and st.has("surprise_falling_weeks") and st.has("dawn_cast_days_ago"), "stats() carries the four keys")
	# a cycle repeated over weeks: surprise falls week after week as T learns
	var w := OracleTendency.new(path)
	var cyc := [3, 17, 42]
	var prev: int = cyc[0]
	var n := 0
	for week in range(6):
		for k in range(12):
			var h: int = cyc[(n + 1) % 3]
			w.observe(prev, h, 12, 7000 + week * 7 + (k % 7))
			prev = h
			n += 1
	_check(w.week_means.size() == 5, "five completed weeks in the ring (%d)" % w.week_means.size())
	_check(w.surprise_falling_weeks() >= 4, "surprise falls >= 4 weeks running (%d) means=%s" % [w.surprise_falling_weeks(), str(w.week_means)])
	_check(w.days == 6 * 7, "42 distinct days (%d)" % w.days)
	_check(w.save(), "save with day bookkeeping")
	var r := OracleTendency.new(path)
	_check(r.load(), "load")
	var ring_ok := r.week_means.size() == w.week_means.size()
	for i in r.week_means.size():
		ring_ok = ring_ok and absf(float(r.week_means[i]) - float(w.week_means[i])) < 1e-6
	_check(r.days == w.days and r.last_day == w.last_day and ring_ok and r.week_cur == w.week_cur, "days/last_day/ring/week_cur roundtrip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
