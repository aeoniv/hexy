class_name SenseSleep
extends Sense

## HUMAN 0 -- Earth. Night, darkness and stillness together, held across the
## length of a night. The oracle's Earth habit ("body resting horizontally in
## quiet darkness") needed all three at once and so does this, but darkness and
## stillness are only counted when the host actually offers them: a phone with
## no light sensor should not be told it is awake.

const WINDOW_MS: int = 28800000
const NIGHT_START: float = 22.0
const NIGHT_END: float = 6.0
const DARK_LUX: float = 40.0

var _hour: float = 0.0
var _hours: float = 0.0


func _init() -> void:
	super(Sense.HUMAN, 0, "sleep")


func _has(t: Dictionary) -> bool:
	return t.has("local_hour")


func _read(now_ms: int, t: Dictionary) -> float:
	var shift: float = Sense.num(t, "offset_ms", 0.0) / 3600000.0
	_hour = fposmod(Sense.num(t, "local_hour", 12.0) + shift, 24.0)
	var night: float = 1.0 if (_hour >= NIGHT_START or _hour < NIGHT_END) else 0.0
	var dark: float = 1.0
	if t.has("lux"):
		dark = clampf(1.0 - Sense.num(t, "lux", 0.0) / DARK_LUX, 0.0, 1.0)
	var still: float = 1.0
	if Sense.has_vec(t, "accel"):
		var dev: float = absf(Sense.vec(t, "accel").length() - 9.8)
		still = clampf(1.0 - dev / 1.0, 0.0, 1.0)
	if Sense.flag(t, "screen_on", false):
		still *= 0.4
	var base: float = night * dark * still
	var frac: float = _dwell(now_ms, base > 0.4, WINDOW_MS)
	_hours = float(_dwell_minutes(now_ms)) / 60.0
	return Sense.windowed(base, frac)


func _say() -> String:
	if _hours >= 1.0:
		return "asleep in the dark for %d hours" % int(_hours)
	return "night, dark and still"


func _forget() -> void:
	_hours = 0.0
