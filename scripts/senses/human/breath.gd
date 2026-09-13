class_name SenseBreath
extends Sense

## HUMAN 6 -- Wind. Micro-motion that repeats. The oracle read equanimity as
## "low gyroscope jitter", but a phone on a shelf has no jitter at all and is
## not breathing. What breathing looks like to an accelerometer is a SMALL
## motion that keeps returning to the same size, so this reads two things: the
## size (a band, not a floor) and the sameness of that size across recent ticks.
##
## Speech spends breath. A voice in the telemetry damps the reading rather than
## cancelling it -- a person speaking slowly is still a person breathing.

const WINDOW_MS: int = 300000
const MICRO_PEAK: float = 0.12
const MICRO_WIDTH: float = 0.25
const SPREAD_FULL: float = 0.25
const HISTORY: int = 6
const SPEECH_DUCK: float = 0.85

var _devs: Array[float] = ([] as Array[float])
var _regular: float = 1.0
var _speaking: bool = false


func _init() -> void:
	super(Sense.HUMAN, 6, "breath")
	_needs = "accelerometer"


func _has(t: Dictionary) -> bool:
	return Sense.has_vec(t, "accel")


func _read(now_ms: int, t: Dictionary) -> float:
	var dev: float = absf(Sense.vec(t, "accel").length() - 9.8)
	_devs.append(dev)
	while _devs.size() > HISTORY:
		_devs.remove_at(0)
	_regular = _sameness()
	_speaking = Sense.flag(t, "speech", false)
	var micro: float = Sense.band(dev, MICRO_PEAK, MICRO_WIDTH)
	var base: float = micro * _regular * (SPEECH_DUCK if _speaking else 1.0)
	var frac: float = _dwell(now_ms, base > 0.4, WINDOW_MS)
	return Sense.windowed(base, frac)


## 1.0 when recent motion sizes agree, falling as they scatter. Fewer than two
## samples is not irregularity, it is silence -- and silence is not evidence.
func _sameness() -> float:
	if _devs.size() < 2:
		return 1.0
	var mean: float = 0.0
	for d in _devs:
		mean += d
	mean /= float(_devs.size())
	var var_sum: float = 0.0
	for d in _devs:
		var_sum += (d - mean) * (d - mean)
	var spread: float = sqrt(var_sum / float(_devs.size()))
	return clampf(1.0 - spread / SPREAD_FULL, 0.0, 1.0)


func _high() -> String:
	if _speaking:
		return "breathing slowly, speaking"
	if _regular > 0.7:
		return "breathing evenly, small steady motion"
	return "breathing, motion uneven"


func _low() -> String:
	return "no breath in this motion"


func _forget() -> void:
	_devs.clear()
	_regular = 1.0
	_speaking = false
