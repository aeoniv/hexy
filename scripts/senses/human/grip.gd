class_name SenseGrip
extends Sense

## HUMAN 3 -- Lake. Held in a hand. A hand is neither a table nor a pocket: it
## is small motion that never quite stops. So the reading is a BAND, not a
## threshold -- perfectly still is a desk, and large motion is a walk. The
## oracle read this as "gyro above a floor", which a phone sliding off a chair
## also passes.
##
## GRIP AND DESK REST ARE MUTUALLY EXCLUSIVE, AND THIS IS WHERE THAT IS
## ENFORCED. An A22 lying flat and untouched reported "flat on a surface,
## untouched" AND "held in a hand, steady" in the same breath, which is not two
## readings, it is a contradiction. A hand must therefore show itself twice
## over: the phone is NOT FLAT -- by SenseDeskRest.flatness, the same function
## the desk itself uses, so the two can never drift apart -- and there is
## either a finger on the glass or real jitter, the spread of recent motion
## above JITTER_FLOOR. Nothing lying on a table clears either bar.

const JITTER_PEAK: float = 0.35
const JITTER_WIDTH: float = 0.35
const TOUCH_FLOOR: float = 0.6

## The standard deviation of recent motion, in m/s^2, below which a thing is
## furniture and not a hand.
const JITTER_FLOOR: float = 0.05
const HISTORY: int = 6

## Above this flatness the phone is on a surface and no hand holds it.
const FLAT_MAX: float = 0.5

var _dev: float = 0.0
var _spread: float = 0.0
var _touching: bool = false
var _flat: bool = false
var _devs: Array[float] = ([] as Array[float])


func _init() -> void:
	super(Sense.HUMAN, 3, "grip")
	_needs = "accelerometer"


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "accel")


func _read(_now_ms: int, t: Dictionary) -> float:
	var a: Vector3 = Sense.vec(t, "accel")
	_dev = absf(a.length() - 9.8)
	_devs.append(_dev)
	while _devs.size() > HISTORY:
		_devs.remove_at(0)
	_spread = _spread_of()
	var touch: float = clampf(Sense.num(t, "touch_rate", 0.0), 0.0, 1.0)
	_touching = touch > 0.05
	# Gravity when the host offers it; otherwise a phone at rest IS its own
	# gravity vector, and a phone on a desk is at rest by definition.
	var g: Vector3 = Sense.vec(t, "gravity") if Sense.has_vec(t, "gravity") else a
	_flat = SenseDeskRest.flatness(g) > FLAT_MAX
	if _flat:
		return 0.0
	if not _touching and _spread <= JITTER_FLOOR:
		return 0.0
	var held: float = Sense.band(_dev, JITTER_PEAK, JITTER_WIDTH)
	return held * (TOUCH_FLOOR + (1.0 - TOUCH_FLOOR) * touch)


## How much recent motion sizes scatter. A single sample is not a spread, so
## the first reading is allowed to stand on its own deviation.
func _spread_of() -> float:
	if _devs.size() < 2:
		return _dev
	var mean: float = 0.0
	for d in _devs:
		mean += d
	mean /= float(_devs.size())
	var sum: float = 0.0
	for d in _devs:
		sum += (d - mean) * (d - mean)
	return sqrt(sum / float(_devs.size()))


func _high() -> String:
	if _touching:
		return "held in a hand, being touched"
	return "held in a hand, steady"


func _low() -> String:
	if _flat:
		return "not held, flat on a surface"
	return "not held"


func _forget() -> void:
	_dev = 0.0
	_spread = 0.0
	_touching = false
	_flat = false
	_devs.clear()
