class_name SenseHydration
extends Sense

## HUMAN 2 -- Water. The only sense with no sensor: it reads a clock started by
## a person's own tap. Thirst is the decay since the last glass, so the reading
## rises the longer the water tool goes unused, and the tool that answers it is
## offered on the same sheet.
##
## The oracle had "metabolic pacing" as the state it fell through to when
## nothing else matched -- a default dressed as a reading. This is the reading
## it should have been.

const DRY_MS: float = 10800000.0

var _hours: float = 0.0
var _has_drink: bool = false


func _init() -> void:
	super(Sense.HUMAN, 2, "hydration")


func _has(t: Dictionary) -> bool:
	return t.has("last_drink_ms")


func _read(now_ms: int, t: Dictionary) -> float:
	var last: float = Sense.num(t, "last_drink_ms", 0.0)
	_has_drink = last > 0.0
	var since: float = maxf(0.0, float(now_ms) - last)
	_hours = since / 3600000.0
	return clampf(since / DRY_MS, 0.0, 1.0)


func _say() -> String:
	if not _has_drink:
		return "no water logged yet"
	if _hours < 1.0:
		return "water %d minutes ago" % int(round(_hours * 60.0))
	return "water %d hours ago" % int(_hours)


func tools() -> Array:
	return [{"id": "water", "label": "water"}]


func _forget() -> void:
	_hours = 0.0
	_has_drink = false
