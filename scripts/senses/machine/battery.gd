class_name SenseBattery
extends Sense

## MACHINE 2 -- Water. What is left in the well, read so that empty scores
## high. The oracle read depletion as a cliff at 25 per cent; here it is a
## slope, because a phone at 30 per cent and a phone at 90 per cent are not the
## same phone and a threshold says they are.

var _pct: float = 100.0


func _init() -> void:
	super(Sense.MACHINE, 2, "battery")


func _has(t: Dictionary) -> bool:
	return t.has("battery_pct")


func _read(_now_ms: int, t: Dictionary) -> float:
	_pct = clampf(Sense.num(t, "battery_pct", 100.0), 0.0, 100.0)
	return clampf(1.0 - _pct / 100.0, 0.0, 1.0)


func _say() -> String:
	if _pct < 25.0:
		return "battery %d percent, deep reserve" % int(round(_pct))
	return "battery %d percent" % int(round(_pct))


func _forget() -> void:
	_pct = 100.0
