class_name SenseGaze
extends Sense

## HUMAN 5 -- Fire. A face in front of the glass, and hands on it. The oracle
## inferred gaze from proximity and tilt, which a phone on a passenger seat
## also satisfies; a face is the thing that was always meant, so the face is
## what this asks for. Touch only sharpens it -- someone reading is looking
## without tapping, and that is still gaze.

const FACE_WEIGHT: float = 0.7
const TOUCH_WEIGHT: float = 0.3
const TOUCH_FULL: float = 2.0

var _face: bool = false
var _rate: float = 0.0


func _init() -> void:
	super(Sense.HUMAN, 5, "gaze")
	_needs_consent = true


func _has(t: Dictionary) -> bool:
	return t.has("face_on")


func _read(_now_ms: int, t: Dictionary) -> float:
	_face = Sense.flag(t, "face_on", false)
	_rate = maxf(0.0, Sense.num(t, "touch_rate", 0.0))
	var looking: float = FACE_WEIGHT if _face else 0.0
	var tapping: float = TOUCH_WEIGHT * clampf(_rate / TOUCH_FULL, 0.0, 1.0)
	if not _face:
		tapping *= 0.5
	return clampf(looking + tapping, 0.0, 1.0)


func _say() -> String:
	if not _face:
		return "no face on the glass"
	if _rate > 0.05:
		return "looking at the glass, hands on it"
	return "looking at the glass"


func _forget() -> void:
	_face = false
	_rate = 0.0
