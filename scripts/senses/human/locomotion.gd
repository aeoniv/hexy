class_name SenseLocomotion
extends Sense

## HUMAN 1 -- Thunder. Steps, and how long they have been going. The oracle
## guessed walking from jerk, which a phone in a pocket on a bus also produces;
## here the cadence itself is the reading, confirmed by a ten minute window so
## that crossing a room and going for a walk are told apart.

const WINDOW_MS: int = 600000
const CADENCE_LO: float = 20.0
const CADENCE_FULL: float = 110.0
const WALKING: float = 25.0

var _spm: float = 0.0
var _minutes: int = 0


func _init() -> void:
	super(Sense.HUMAN, 1, "locomotion")
	_needs = "ixbody"


func _has(t: Dictionary) -> bool:
	return t.has("steps_per_min")


func _read(now_ms: int, t: Dictionary) -> float:
	_spm = maxf(0.0, Sense.num(t, "steps_per_min", 0.0))
	var base: float = Sense.ramp(_spm, CADENCE_LO, CADENCE_FULL)
	var frac: float = _dwell(now_ms, _spm >= WALKING, WINDOW_MS)
	_minutes = _dwell_minutes(now_ms)
	return Sense.windowed(base, frac)


func _high() -> String:
	if _minutes >= 1:
		return "walking %d a minute for %d minutes" % [int(round(_spm)), _minutes]
	return "walking, %d steps a minute" % int(round(_spm))


func _low() -> String:
	return "not walking, %d steps a minute" % int(round(_spm))


func _forget() -> void:
	_spm = 0.0
	_minutes = 0
