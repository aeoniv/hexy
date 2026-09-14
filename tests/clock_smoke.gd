extends SceneTree

## CLOCK SMOKE — scripts/core/clock.gd, ported/authored for base's M1b.
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
	_unwired_readings()
	_wired_source()
	_fallbacks()
	_seconds_and_day()

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


func _unwired_readings() -> void:
	var a := Clock.now_ms()
	var b := Clock.now_ns()
	_check(a >= 0, "now_ms is non-negative")
	_check(b >= 0, "now_ns is non-negative")
	_check(b >= a * 1000000, "now_ns is at least now_ms scaled to ns")
	var a2 := Clock.now_ms()
	_check(a2 >= a, "now_ms never goes backwards across two calls")


func _wired_source() -> void:
	var src := func() -> int: return 424242
	_check(Clock.ns(src) == 424242, "ns() reads a wired source")
	_check(Clock.ns(Callable()) == 0, "ns() with no source is zero")
	_check(Clock.ms(src) == 424242, "ms() reads a wired source")
	_check(Clock.ms(Callable()) == 0, "ms() with no source is zero")


func _fallbacks() -> void:
	_check(Clock.ns_or_ticks(Callable()) >= 0,
		"ns_or_ticks falls back to the local monotonic clock")
	var src := func() -> int: return 7
	_check(Clock.ns_or_ticks(src) == 7, "ns_or_ticks reads a wired source")
	_check(Clock.ms_or_ticks(123) == 123,
		"ms_or_ticks honours a non-negative caller stamp")
	_check(Clock.ms_or_ticks(-1) >= 0,
		"ms_or_ticks falls back to the local clock on -1")


func _seconds_and_day() -> void:
	_check(Clock.seconds() >= 0.0, "seconds() is non-negative")
	_check(Clock.day_seconds(Callable()) >= 0
		and Clock.day_seconds(Callable()) < 86400,
		"day_seconds() is within one day")
	_check(Clock.day_index(Callable()) > 0,
		"day_index() is a plausible days-since-epoch")
	var src := func() -> int: return 55
	_check(Clock.day_seconds(src) == 55, "day_seconds() reads a wired source")
	_check(Clock.day_index(src) == 55, "day_index() reads a wired source")
