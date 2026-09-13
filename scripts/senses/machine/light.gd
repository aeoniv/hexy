class_name SenseLight
extends Sense

## MACHINE 5 -- Fire. How much light is falling on the glass. Lux is a
## logarithmic world -- a room at 300 and a room at 600 look nearly alike,
## 300 and 30000 do not -- so the ramp is taken in decades, not in lux. The
## oracle's single 3500 lux cliff is kept only as a word in the sentence.

const DARK_LUX: float = 10.0
const SUN_LUX: float = 10000.0

var _lux: float = 0.0


func _init() -> void:
	super(Sense.MACHINE, 5, "light")


func _has(t: Dictionary) -> bool:
	return t.has("lux")


func _read(_now_ms: int, t: Dictionary) -> float:
	_lux = maxf(0.0, Sense.num(t, "lux", 0.0))
	var decades: float = log(maxf(_lux, 1.0)) / log(10.0)
	var lo: float = log(DARK_LUX) / log(10.0)
	var hi: float = log(SUN_LUX) / log(10.0)
	return Sense.ramp(decades, lo, hi)


func _say() -> String:
	if _lux < 20.0:
		return "almost no light, %d lux" % int(round(_lux))
	if _lux > 3500.0:
		return "full daylight, %d lux" % int(round(_lux))
	return "light at %d lux" % int(round(_lux))


func _forget() -> void:
	_lux = 0.0
