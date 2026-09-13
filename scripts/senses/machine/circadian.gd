class_name SenseCircadian
extends Sense

## MACHINE 7 -- Heaven. How close the local clock is to the sun's high point.
## The oracle's "local solar hour between 11:00 and 14:30" as a slope rather
## than a window, so noon is a peak and not a plateau.
##
## `offset_ms` is a correction the host may hand down -- a zone the device did
## not know, a longitude nudge -- and is added to the local hour before the
## distance from noon is taken.

const NOON: float = 12.0
const HALF_DAY: float = 6.0

var _hour: float = 12.0


func _init() -> void:
	super(Sense.MACHINE, 7, "circadian")


func _has(t: Dictionary) -> bool:
	return t.has("local_hour")


func _read(_now_ms: int, t: Dictionary) -> float:
	var shift: float = Sense.num(t, "offset_ms", 0.0) / 3600000.0
	_hour = fposmod(Sense.num(t, "local_hour", 12.0) + shift, 24.0)
	var away: float = absf(fposmod(_hour - NOON + 12.0, 24.0) - 12.0)
	return clampf(1.0 - away / HALF_DAY, 0.0, 1.0)


func _high() -> String:
	return "local hour %s, near solar noon" % _clock()


func _low() -> String:
	return "local hour %s, far from noon" % _clock()


func _clock() -> String:
	var h: int = int(_hour)
	var m: int = int(floor((_hour - float(h)) * 60.0))
	return "%02d:%02d" % [h, m]


func _forget() -> void:
	_hour = 12.0
