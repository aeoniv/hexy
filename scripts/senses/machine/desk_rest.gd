class_name SenseDeskRest
extends Sense

## MACHINE 4 -- Mountain. Lying flat on something, untouched. The oracle's
## "phone resting flat on table, substrate completely immobilized", read from
## gravity alone so it holds whichever face is down; WHICH face is down belongs
## to the human family's deep work, not to the surface underneath.
##
## THE GRAVITY CONVENTION, WRITTEN DOWN ONCE AND READ BY BOTH SENSES.
## Godot's Input.get_gravity() on Android reports, in m/s^2, the direction the
## earth pulls, in the DEVICE frame whose +z comes OUT OF THE SCREEN. So a
## phone lying FACE UP on a desk reads gravity.z near -9.8, and FACE DOWN reads
## near +9.8. Confirmed on a Samsung A22 lying face up: |z| ~ 9.8 with a
## negative sign. sensor_oracle.gd's `filtered_grav.z < -7.0` screen-down test
## therefore had the sign INVERTED and called a face-up phone face down; that
## file is left alone here, and deep_work.gd carries the corrected sign.
## This sense only ever asks |z|, because a table is a table either way.

const FLAT_LO: float = 6.0
const FLAT_HI: float = 9.4
const TILT_M: float = 4.0

var _touched: bool = false


func _init() -> void:
	super(Sense.MACHINE, 4, "desk rest")
	_needs = "gravity sensor"


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "gravity")


## How flat on a surface a gravity vector reads, 0..1. Grip asks this too --
## a phone flat on a desk is NOT in a hand, and the two senses must agree on
## what flat means or they will both claim the same phone.
static func flatness(g: Vector3) -> float:
	var flat: float = Sense.ramp(absf(g.z), FLAT_LO, FLAT_HI)
	var tilt: float = clampf(1.0 - Vector2(g.x, g.y).length() / TILT_M, 0.0, 1.0)
	return flat * tilt


func _read(_now_ms: int, t: Dictionary) -> float:
	var touch: float = clampf(Sense.num(t, "touch_rate", 0.0), 0.0, 1.0)
	_touched = touch > 0.05
	return flatness(Sense.vec(t, "gravity")) * (1.0 - touch)


func _high() -> String:
	if _touched:
		return "flat on a surface, still being touched"
	return "flat on a surface, untouched"


func _low() -> String:
	return "not flat on a surface"


func _forget() -> void:
	_touched = false
