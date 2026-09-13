class_name SenseThermal
extends Sense

## MACHINE 1 -- Thunder. Current running in, or heat coming off. The oracle's
## "charging current flowing into lithium cell or thermal excitation elevated",
## with the two halves separated so either one alone can still be sensed.

const WARM_C: float = 28.0
const HOT_C: float = 40.0
const CHARGE_FLOOR: float = 0.7

var _charging: bool = false
var _temp_c: float = 0.0
var _has_temp: bool = false


func _init() -> void:
	super(Sense.MACHINE, 1, "thermal")
	_needs = "android battery"


func _has(t: Dictionary) -> bool:
	return t.has("battery_temp_c") or t.has("charging")


func _read(_now_ms: int, t: Dictionary) -> float:
	_has_temp = t.has("battery_temp_c")
	_temp_c = Sense.num(t, "battery_temp_c", 0.0)
	_charging = Sense.flag(t, "charging", false)
	var heat: float = 0.0
	if _has_temp:
		heat = Sense.ramp(_temp_c, WARM_C, HOT_C)
	var wire: float = CHARGE_FLOOR if _charging else 0.0
	return maxf(heat, wire)


func _high() -> String:
	if _charging and _has_temp:
		return "charging, cell at %d c" % int(round(_temp_c))
	if _charging:
		return "charging, current running in"
	return "cell at %d c" % int(round(_temp_c))


func _low() -> String:
	if _has_temp:
		return "not charging, cell at %d c" % int(round(_temp_c))
	return "not charging, no heat"


func _forget() -> void:
	_charging = false
	_has_temp = false
	_temp_c = 0.0
