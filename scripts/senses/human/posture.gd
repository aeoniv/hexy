class_name SensePosture
extends Sense

## HUMAN 7 -- Heaven. A spine held against gravity. The host may have a real
## answer (a pose estimate, 0..1) and the phone always has gravity; the pose is
## the reading and the tilt is the witness. Where the oracle had only tilt --
## and so called a phone standing on a shelf "upright spine" -- here tilt can
## only confirm a posture, never claim one.

const TILT_LO: float = 5.0
const TILT_HI: float = 9.0

var _upright: float = 0.0
var _tilt: float = 1.0


func _init() -> void:
	super(Sense.HUMAN, 7, "posture")


func _has(t: Dictionary) -> bool:
	return t.has("pose_upright")


func _read(_now_ms: int, t: Dictionary) -> float:
	_upright = clampf(Sense.num(t, "pose_upright", 0.0), 0.0, 1.0)
	_tilt = 1.0
	if Sense.has_vec(t, "gravity"):
		var g: Vector3 = Sense.vec(t, "gravity")
		_tilt = Sense.ramp(-g.y, TILT_LO, TILT_HI)
	return _upright * (0.7 + 0.3 * _tilt)


func _say() -> String:
	if _upright > 0.66:
		return "sitting up, spine against gravity"
	if _upright > 0.33:
		return "half upright, leaning"
	return "slumped, spine given up"


func _forget() -> void:
	_upright = 0.0
	_tilt = 1.0
