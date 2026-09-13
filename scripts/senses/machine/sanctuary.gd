class_name SenseSanctuary
extends Sense

## MACHINE 0 -- Earth. The same place, held still, for long enough that it
## stops being a coordinate and starts being a room.
##
## Ported from sensor_oracle.gd's Earth substrate ("physical location
## stationary and sheltered") with the part it could not actually measure made
## measurable: the oracle inferred sanctuary from darkness, this sense asks the
## place itself. A fix that wanders more than ROOM_M metres is a different room
## and the clock starts again.

const WINDOW_MS: int = 600000
const ROOM_M: float = 60.0
const DEG_M: float = 111000.0

var _lat: float = 0.0
var _lon: float = 0.0
var _anchored: bool = false
var _minutes: int = 0


func _init() -> void:
	super(Sense.MACHINE, 0, "sanctuary")
	_needs_consent = true


func _has(t: Dictionary) -> bool:
	return t.has("location") and (t["location"] is Dictionary)


func _read(now_ms: int, t: Dictionary) -> float:
	var fix: Dictionary = t["location"] as Dictionary
	var lat: float = float(fix.get("lat", 0.0))
	var lon: float = float(fix.get("lon", 0.0))
	var moved: bool = false
	if _anchored:
		var dy: float = (lat - _lat) * DEG_M
		var dx: float = (lon - _lon) * DEG_M * cos(deg_to_rad(lat))
		moved = sqrt(dx * dx + dy * dy) > ROOM_M
	if moved or not _anchored:
		_lat = lat
		_lon = lon
		_anchored = true
	var still: float = _stillness(t)
	var frac: float = _dwell(now_ms, not moved, WINDOW_MS)
	_minutes = _dwell_minutes(now_ms)
	return Sense.windowed(still, frac)


func _stillness(t: Dictionary) -> float:
	if not Sense.has_vec(t, "accel"):
		return 1.0
	var dev: float = absf(Sense.vec(t, "accel").length() - 9.8)
	return clampf(1.0 - dev / 1.5, 0.0, 1.0)


func _say() -> String:
	if _minutes < 1:
		return "settled in one place"
	return "same place for %d minutes" % _minutes


func _forget() -> void:
	_anchored = false
	_minutes = 0
