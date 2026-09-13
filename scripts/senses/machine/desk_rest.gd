class_name SenseDeskRest
extends Sense

## MACHINE 4 -- Mountain. Lying flat on something, untouched. The oracle's
## "phone resting flat on table, substrate completely immobilized", read from
## gravity alone so it holds whichever face is down; WHICH face is down belongs
## to the human family's deep work, not to the surface underneath.

const FLAT_LO: float = 6.0
const FLAT_HI: float = 9.4
const TILT_M: float = 4.0

var _touched: bool = false


func _init() -> void:
	super(Sense.MACHINE, 4, "desk rest")


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "gravity")


func _read(_now_ms: int, t: Dictionary) -> float:
	var g: Vector3 = Sense.vec(t, "gravity")
	var flat: float = Sense.ramp(absf(g.z), FLAT_LO, FLAT_HI)
	var tilt: float = clampf(1.0 - Vector2(g.x, g.y).length() / TILT_M, 0.0, 1.0)
	var touch: float = clampf(Sense.num(t, "touch_rate", 0.0), 0.0, 1.0)
	_touched = touch > 0.05
	return flat * tilt * (1.0 - touch)


func _say() -> String:
	if _touched:
		return "flat on a surface, still being touched"
	return "flat on a surface, untouched"


func _forget() -> void:
	_touched = false
