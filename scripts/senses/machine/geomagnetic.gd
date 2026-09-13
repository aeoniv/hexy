class_name SenseGeomagnetic
extends Sense

## MACHINE 6 -- Wind. The planet's field, and whether the phone is holding one
## bearing inside it. The oracle read only the north-south corridor; a corridor
## is a place, but Wind is a steadiness, so this reads both: field strength
## saying the magnetometer is really seeing the earth, and a heading that has
## stopped wandering.

const FIELD_FLOOR: float = 20.0
const FIELD_FULL: float = 55.0
const SWING_DEG: float = 25.0

var _field: float = 0.0
var _heading: float = 0.0
var _has_heading: bool = false
var _last_heading: float = 0.0
var _first: bool = true


func _init() -> void:
	super(Sense.MACHINE, 6, "geomagnetic")


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "magnet") or t.has("heading_deg")


func _read(_now_ms: int, t: Dictionary) -> float:
	var m: Vector3 = Sense.vec(t, "magnet")
	_field = m.length()
	var strength: float = 1.0
	if Sense.has_vec(t, "magnet"):
		strength = Sense.ramp(_field, FIELD_FLOOR, FIELD_FULL)
	_has_heading = t.has("heading_deg")
	if _has_heading:
		_heading = fposmod(Sense.num(t, "heading_deg", 0.0), 360.0)
	elif Sense.has_vec(t, "magnet"):
		_heading = fposmod(rad_to_deg(atan2(-m.x, -m.y)), 360.0)
		_has_heading = true
	var steady: float = 1.0
	if _has_heading and not _first:
		var d: float = absf(fposmod(_heading - _last_heading + 180.0, 360.0) - 180.0)
		steady = clampf(1.0 - d / SWING_DEG, 0.0, 1.0)
	_last_heading = _heading
	_first = false
	return 0.5 * strength + 0.5 * steady


func _say() -> String:
	if not _has_heading:
		return "field at %d microtesla" % int(round(_field))
	return "holding %d degrees, field %d ut" % [int(round(_heading)), int(round(_field))]


func _forget() -> void:
	_first = true
	_field = 0.0
	_has_heading = false
