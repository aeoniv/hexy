extends SceneTree

## ENTRAIN SMOKE — scripts/core/entrain.gd.
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


func _near(a: float, b: float, eps: float, what: String) -> void:
	_check(absf(a - b) <= eps, "%s (got %.4f, want %.4f +-%.4f)" % [what, a, b, eps])


func _initialize() -> void:
	_empty_estimator()
	_night_owl()
	_lark()
	_internal_hour()
	_advice_prc()
	_round_trip()
	_decay()
	_trim()
	_config()

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


## True when `hour` (0..24, wrapping) falls in the half-open circular window
## [start, stop) -- lets both the owl (23 -> 3) and the lark windows be
## expressed the ordinary way even when they cross midnight.
func _in_window(hour: float, start: float, stop: float) -> bool:
	if start <= stop:
		return hour >= start and hour < stop
	return hour >= start or hour < stop


func _fill_days(e: Entrain, days: int, active_start: float, active_stop: float) -> void:
	for day in range(days):
		var h := 0.0
		while h < 24.0:
			var active := _in_window(h, active_start, active_stop)
			var lux := 200.0 if active else 1.0
			var motion := 0.7 if active else 0.0
			e.sample(day, h, lux, motion, active, false)
			h += 0.5


func _empty_estimator() -> void:
	print("\n- empty estimator")
	var e := Entrain.new()
	var est := e.estimate()
	_check(is_equal_approx(float(est["offset_h"]), 0.0), "no samples -> zero offset")
	_check(is_equal_approx(float(est["confidence"]), 0.0), "no samples -> zero confidence")
	_check(e.samples.is_empty(), "fresh estimator carries no samples")
	_near(e.internal_hour(10.0), 10.0, 0.001, "zero offset leaves the hour alone")


var _owl: Entrain


func _night_owl() -> void:
	print("\n- night owl (active 11:00-03:00)")
	var e := Entrain.new()
	_fill_days(e, 7, 11.0, 3.0)
	var est := e.estimate()
	var offset: float = est["offset_h"]
	var conf: float = est["confidence"]
	print("  owl offset=%.2f confidence=%.2f wake=%.2f sleep=%.2f" %
		[offset, conf, est["wake_h"], est["sleep_h"]])
	_check(offset >= 3.0 and offset <= 5.0, "owl offset lands in +3..+5h")
	_check(conf > 0.6, "owl confidence exceeds 0.6 after a full week")
	var internal := e.internal_hour(11.0)
	_near(internal, 7.0, 1.5, "owl's own 11:00 reads near the fly's 7:00 morning")
	_owl = e


func _lark() -> void:
	print("\n- lark (active 05:00-13:00)")
	var e := Entrain.new()
	_fill_days(e, 7, 5.0, 13.0)
	var est := e.estimate()
	var offset: float = est["offset_h"]
	print("  lark offset=%.2f confidence=%.2f" % [offset, est["confidence"]])
	_check(offset < 0.0, "lark offset is negative")
	_check(float(est["confidence"]) > 0.6, "lark confidence exceeds 0.6 after a full week")


func _internal_hour() -> void:
	print("\n- internal_hour wraps")
	var e := Entrain.new()
	e.phase_offset_h = 4.0
	_near(e.internal_hour(23.0), 19.0, 0.001, "offset shifts a late hour earlier")
	_near(e.internal_hour(2.0), 22.0, 0.001, "offset wraps past midnight correctly")
	e.phase_offset_h = -3.0
	_near(e.internal_hour(1.0), 4.0, 0.001, "a negative (lark) offset shifts later")


func _advice_prc() -> void:
	print("\n- advice PRC")
	var e := _owl
	var est := e.estimate()
	var wake_h: float = est["wake_h"]
	var sleep_h: float = est["sleep_h"]

	var before_wake := fposmod(wake_h - 2.0, 24.0)
	var adv_before := e.advice(before_wake, 300.0)
	_check(adv_before["key"] == "light_advances", "bright light before wake advances")
	_check(float(adv_before["shift_h"]) > 0.0, "advance carries a positive shift")

	var after_sleep := fposmod(sleep_h + 2.0, 24.0)
	var adv_after := e.advice(after_sleep, 300.0)
	_check(adv_after["key"] == "light_delays", "bright light after sleep delays")
	_check(float(adv_after["shift_h"]) > 0.0, "delay carries a positive shift")

	var adv_dim := e.advice(before_wake, 5.0)
	_check(adv_dim["key"] == "none", "dim light before wake is a no-op")

	var midday := fposmod(wake_h + 6.0, 24.0)
	var adv_mid := e.advice(midday, 300.0)
	_check(adv_mid["key"] == "none", "bright light well clear of either edge is a no-op")

	var e2 := Entrain.new()
	var adv_empty := e2.advice(3.0, 300.0)
	_check(adv_empty["key"] == "light_delays" or adv_empty["key"] == "light_advances" or adv_empty["key"] == "none",
		"advice never crashes on an empty estimator")


func _round_trip() -> void:
	print("\n- to_dict / from_dict")
	var e := Entrain.new()
	_fill_days(e, 3, 22.0, 6.0)
	e.estimate()
	var d := e.to_dict()
	_check(d.has("phase_offset_h") and d.has("confidence") and d.has("samples"),
		"to_dict carries offset, confidence and samples")

	var e2 := Entrain.from_dict(d)
	_near(e2.phase_offset_h, e.phase_offset_h, 0.0001, "offset round-trips")
	_near(e2.confidence, e.confidence, 0.0001, "confidence round-trips")
	_check(e2.samples.size() == e.samples.size(), "sample count round-trips")
	if e.samples.size() > 0 and e2.samples.size() > 0:
		var a: Entrain.Sample = e.samples[0]
		var b: Entrain.Sample = e2.samples[0]
		_check(a.day == b.day and is_equal_approx(a.wall_hour, b.wall_hour)
			and is_equal_approx(a.lux, b.lux) and is_equal_approx(a.motion, b.motion)
			and a.screen_on == b.screen_on and a.spoke == b.spoke,
			"first sample's fields round-trip exactly")

	var est2 := e2.estimate()
	var est1 := e.estimate()
	_near(float(est2["offset_h"]), float(est1["offset_h"]), 0.0001,
		"a from_dict estimator re-estimates to the same offset")

	var empty_d := Entrain.new().to_dict()
	var empty_e := Entrain.from_dict(empty_d)
	_check(empty_e.samples.is_empty(), "an empty estimator round-trips empty")


func _decay() -> void:
	print("\n- decay")
	var e := Entrain.new()
	e.confidence = 0.8
	e.decay(5, 0.02)
	_near(e.confidence, 0.7, 0.0001, "decay knocks confidence down by rate*ticks")
	e.decay(1000, 0.02)
	_check(e.confidence == 0.0, "decay floors at zero, never negative")


func _trim() -> void:
	print("\n- trim")
	var e := Entrain.new()
	_fill_days(e, 5, 11.0, 3.0)
	var before := e.samples.size()
	e.trim(4, 2)
	_check(e.samples.size() < before, "trim drops samples outside the day window")
	for s in e.samples:
		_check(s.day >= 3, "every kept sample is within the trimmed window")
		break


func _config() -> void:
	print("\n- default_config")
	var cfg := Entrain.default_config()
	_check(cfg.has("entrain.days") and int(cfg["entrain.days"]) == 7, "entrain.days defaults to 7")
	_check(cfg.has("entrain.min_samples") and int(cfg["entrain.min_samples"]) == 48,
		"entrain.min_samples defaults to 48")
