class_name SenseGrip
extends Sense

## HUMAN 3 -- Lake. Held in a hand. A hand is neither a table nor a pocket: it
## is small motion that never quite stops. So the reading is a BAND, not a
## threshold -- perfectly still is a desk, and large motion is a walk. The
## oracle read this as "gyro above a floor", which a phone sliding off a chair
## also passes.

const JITTER_PEAK: float = 0.35
const JITTER_WIDTH: float = 0.35
const TOUCH_FLOOR: float = 0.6

var _dev: float = 0.0
var _touching: bool = false


func _init() -> void:
	super(Sense.HUMAN, 3, "grip")


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "accel")


func _read(_now_ms: int, t: Dictionary) -> float:
	_dev = absf(Sense.vec(t, "accel").length() - 9.8)
	var held: float = Sense.band(_dev, JITTER_PEAK, JITTER_WIDTH)
	var touch: float = clampf(Sense.num(t, "touch_rate", 0.0), 0.0, 1.0)
	_touching = touch > 0.05
	return held * (TOUCH_FLOOR + (1.0 - TOUCH_FLOOR) * touch)


func _say() -> String:
	if _touching:
		return "held in a hand, being touched"
	return "held in a hand, steady"


func _forget() -> void:
	_dev = 0.0
	_touching = false
