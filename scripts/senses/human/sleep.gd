class_name SenseSleep
extends Sense

## HUMAN 0 -- Earth. Night, darkness and stillness together, held across the
## length of a night. The oracle's Earth habit ("body resting horizontally in
## quiet darkness") needed all three at once and so does this, but darkness and
## stillness are only counted when the host actually offers them: a phone with
## no light sensor should not be told it is awake.
##
## THREE GATES, NOT THREE HINTS. A screen that is ON is a person who is awake,
## and an hour outside the night is a day; either one alone makes this ZERO,
## not merely small. A Samsung A22 at 13:07 with the screen lit scored nothing
## and still said "night, dark and still", because a damped product and a
## refused reading looked the same from outside. They do not any more.

const WINDOW_MS: int = 28800000
const NIGHT_START: float = 22.0
const NIGHT_END: float = 6.0
const DARK_LUX: float = 40.0

var _hour: float = 0.0
var _hours: float = 0.0
var _night: bool = false
var _screen: bool = false


func _init() -> void:
	super(Sense.HUMAN, 0, "sleep")


func _has(t: Dictionary) -> bool:
	return t.has("local_hour")


func _read(now_ms: int, t: Dictionary) -> float:
	var shift: float = Sense.num(t, "offset_ms", 0.0) / 3600000.0
	_hour = fposmod(Sense.num(t, "local_hour", 12.0) + shift, 24.0)
	_night = _hour >= NIGHT_START or _hour < NIGHT_END
	# A missing screen key is not a lit screen: an absent sensor may not
	# convict. A present one that says ON ends the question.
	_screen = Sense.flag(t, "screen_on", false)
	var dark: float = 1.0
	if t.has("lux"):
		dark = clampf(1.0 - Sense.num(t, "lux", 0.0) / DARK_LUX, 0.0, 1.0)
	var still: float = 1.0
	if Sense.has_vec(t, "accel"):
		var dev: float = absf(Sense.vec(t, "accel").length() - 9.8)
		still = clampf(1.0 - dev / 1.0, 0.0, 1.0)
	if not _night or _screen:
		_dwell(now_ms, false, WINDOW_MS)
		_hours = 0.0
		return 0.0
	var base: float = dark * still
	var frac: float = _dwell(now_ms, base > 0.4, WINDOW_MS)
	_hours = float(_dwell_minutes(now_ms)) / 60.0
	return Sense.windowed(base, frac)


func _high() -> String:
	if _hours >= 1.0:
		return "asleep in the dark for %d hours" % int(_hours)
	return "night, dark and still"


func _low() -> String:
	var when: String = "night" if _night else "day"
	var glass: String = "screen on" if _screen else "screen off"
	return "%s, %s" % [when, glass]


func _forget() -> void:
	_hours = 0.0
	_night = false
	_screen = false
