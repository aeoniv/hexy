class_name SenseDeepWork
extends Sense

## HUMAN 4 -- Mountain. Screen off, face down, and left that way. The oracle's
## "phone turned face-down, digital distractions muted" with the minutes added:
## a phone put down for four seconds is not deep work, and the twenty-five
## minute window is what tells the difference.
##
## FACE DOWN IS gravity.z >= FACE_DOWN -- POSITIVE. The convention is written
## out in full in machine/desk_rest.gd: Godot's gravity points the way the
## earth pulls, in a device frame whose +z leaves the screen, so FACE UP reads
## z near -9.8 and FACE DOWN reads z near +9.8. sensor_oracle.gd's screen-down
## test had this sign inverted, which is exactly why an A22 lying face up on a
## desk was told it was in deep work. Desk rest asks |z| and is right either
## way; only this sense cares which face is down.
##
## BOTH CONDITIONS ARE GATES. A lit screen is not deep work at any tilt.

const WINDOW_MS: int = 1500000
const FACE_DOWN: float = 6.0

var _minutes: int = 0
var _down: bool = false
var _screen: bool = false


func _init() -> void:
	super(Sense.HUMAN, 4, "deep work")
	_needs = "gravity sensor"


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "gravity") and t.has("screen_on")


func _read(now_ms: int, t: Dictionary) -> float:
	var g: Vector3 = Sense.vec(t, "gravity")
	var down: float = Sense.ramp(g.z, FACE_DOWN, 9.4)
	if t.has("proximity_near") and Sense.flag(t, "proximity_near", false):
		down = maxf(down, 0.8)
	_down = down > 0.0
	_screen = Sense.flag(t, "screen_on", false)
	if _screen or not _down:
		_dwell(now_ms, false, WINDOW_MS)
		_minutes = 0
		return 0.0
	var frac: float = _dwell(now_ms, down > 0.4, WINDOW_MS)
	_minutes = _dwell_minutes(now_ms)
	return Sense.windowed(down, frac)


func _high() -> String:
	if _minutes >= 1:
		return "face down, screen off, %d minutes" % _minutes
	return "face down, screen off"


func _low() -> String:
	var face: String = "face down" if _down else "face up"
	var glass: String = "screen on" if _screen else "screen off"
	return "%s, %s" % [face, glass]


func _forget() -> void:
	_minutes = 0
	_down = false
	_screen = false
