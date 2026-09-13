class_name SenseDeepWork
extends Sense

## HUMAN 4 -- Mountain. Screen off, face down, and left that way. The oracle's
## "phone turned face-down, digital distractions muted" with the minutes added:
## a phone put down for four seconds is not deep work, and the twenty-five
## minute window is what tells the difference.
##
## FACE DOWN IS gravity.z <= -FACE_DOWN, the same axis and sign
## sensor_oracle.gd used for its screen-down eclipse, so a device that read as
## deep work there reads as deep work here.

const WINDOW_MS: int = 1500000
const FACE_DOWN: float = 6.0

var _minutes: int = 0


func _init() -> void:
	super(Sense.HUMAN, 4, "deep work")


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "gravity") and t.has("screen_on")


func _read(now_ms: int, t: Dictionary) -> float:
	var g: Vector3 = Sense.vec(t, "gravity")
	var down: float = Sense.ramp(-g.z, FACE_DOWN, 9.4)
	var dark: float = 0.0 if Sense.flag(t, "screen_on", false) else 1.0
	if t.has("proximity_near") and Sense.flag(t, "proximity_near", false):
		down = maxf(down, 0.8)
	var base: float = down * dark
	var frac: float = _dwell(now_ms, base > 0.4, WINDOW_MS)
	_minutes = _dwell_minutes(now_ms)
	return Sense.windowed(base, frac)


func _say() -> String:
	if _minutes >= 1:
		return "face down, screen off, %d minutes" % _minutes
	return "face down, screen off"


func _forget() -> void:
	_minutes = 0
