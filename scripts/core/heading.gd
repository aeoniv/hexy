class_name Heading
extends Node

## WHICH WAY THE PHONE IS FACING, FROM GODOT'S OWN SENSORS AND NOTHING ELSE.
##
## `Input.get_magnetometer()` and `Input.get_gravity()` are engine API: they are
## in base, they need no plugin, and they need no door. Every frame this node
## reads both, hands them to `Geo.heading_deg` for the tilt-compensated azimuth,
## and publishes four things the glass can read: the heading, how much to
## believe it, which pose the phone is in, and whether a sensor is speaking at
## all.
##
## HEADLESS IS A REAL STATE, NOT A BROKEN ONE. On a desktop, on CI, and on any
## phone with no magnetometer, `get_magnetometer()` returns the zero vector
## forever. Then `live()` is false, `heading_rad()` stays 0.0, `seen()` is false
## and NOTHING IS INVENTED. The radar reads `live()` and goes back to being the
## allocentric dial it was before this file existed.
##
## THE ACCURACY IS AN INFERENCE, AND THAT IS SAID OUT LOUD.
## Android's SensorManager reports a calibration state through
## onAccuracyChanged; Godot's Input does not expose it, and with no Android
## plugin there is no way to ask. So the level published here is DERIVED, by
## `Geo.accuracy_from_field`, from two things a raw vector can honestly show:
##   * the total field magnitude, against the 25-65 uT band Earth actually has;
##   * the sample-to-sample jitter of that magnitude.
## Both catch the case this exists for -- a phone next to a speaker, a laptop
## hinge or a car dashboard. NEITHER catches a steady hard-iron offset, which
## biases every heading by the same wrong amount while looking perfectly calm.
## That is why HIGH is only ever reached on a field that is both plausible and
## quiet, and why the radar's caption never claims more than this can back.
##
## TWO SEAMS FOR A FUTURE NAV ADD-ON, both write-only, both closed in base:
##   `set_declination(deg)` -- a position and a date give the World Magnetic
##       Model a declination, and `heading_rad()` folds it in so the number
##       becomes TRUE north. `true_north()` is the only honest way to tell the
##       two apart; the number alone never says.
##   `set_fix(lat, lon, acc_m)` -- where the body is. Base never fills it: GPS
##       is an add-on door and this node has no provider, no permission request
##       and no timer reading one. It is kept so the add-on has somewhere to put
##       the fix, and so `fix()` can hand it to whatever computes a declination.

signal heading_changed(deg: float)
signal accuracy_changed(level: int)
signal pose_changed(pose: String)

## One low-pass step per frame toward the raw reading, on the circle. Slow
## enough that a hand's tremor does not shiver the dial, fast enough that
## turning on the spot feels immediate.
const SMOOTH_ALPHA := 0.22

## How many magnitude samples the jitter is averaged over. About a fifth of a
## second at 60 Hz: long enough to average a tremor, short enough that walking
## away from a magnet clears the warning while you are still walking.
const JITTER_WINDOW := 12

## Frames of silence after which a heading that WAS arriving is called quiet.
## The picture keeps the last heading -- the peers do not snap back to north --
## but `live()` goes false and the radar stops claiming a live compass.
const QUIET_FRAMES := 240

var _deg := 0.0
var _raw_deg := -1.0
var _accuracy: int = Geo.ACC_UNKNOWN
var _pose: String = Geo.POSE_FLAT
var _seen := false
var _quiet_for := 0
var _declination := 0.0
var _has_declination := false
var _fix: Dictionary = {}
var _mags: PackedFloat32Array = PackedFloat32Array()
## Last vectors read, kept only so a test can see what the node saw.
var _mag := Vector3.ZERO
var _grav := Vector3.ZERO


func _process(_delta: float) -> void:
	step(Input.get_magnetometer(), Input.get_gravity())


## ONE FRAME OF SENSOR, HAND-FED. `_process` calls it with Godot's vectors; a
## test calls it with vectors of its own. Everything this node decides is
## decided here, so there is exactly one code path and it is testable.
func step(mag: Vector3, grav: Vector3) -> void:
	_mag = mag
	_grav = grav
	var raw := Geo.heading_deg(mag, grav, Geo.pose_of(grav, _pose))
	if raw < 0.0:
		# No field, or a field with no horizontal component. Not an error and
		# not a reason to move anything: the last heading stands, and after
		# QUIET_FRAMES the dial stops calling itself live.
		if _seen:
			_quiet_for += 1
		return
	_quiet_for = 0
	_set_pose(Geo.pose_of(grav, _pose))
	_set_accuracy(Geo.accuracy_from_field(mag.length(), _push_jitter(mag.length())))
	_raw_deg = raw
	var next := raw if not _seen else Geo.heading_smooth(_deg, raw, SMOOTH_ALPHA)
	_seen = true
	if not is_equal_approx(next, _deg):
		_deg = next
		heading_changed.emit(heading_deg())


## Mean absolute change of the total field over the recent window, in uT, or
## -1.0 while there is not yet a pair to compare. Pushing the new sample is part
## of asking, because the two always happen together.
func _push_jitter(magnitude: float) -> float:
	_mags.append(magnitude)
	while _mags.size() > JITTER_WINDOW:
		_mags.remove_at(0)
	if _mags.size() < 2:
		return -1.0
	var total := 0.0
	for i in range(1, _mags.size()):
		total += absf(_mags[i] - _mags[i - 1])
	return total / float(_mags.size() - 1)


# -- what the glass reads -----------------------------------------------------

## Where the phone is pointing, radians clockwise from north, [0, TAU).
## TRUE north once a declination has been handed in, MAGNETIC north until then,
## and `true_north()` is the only way to tell.
func heading_rad() -> float:
	return deg_to_rad(heading_deg())


## The same number in degrees, [0, 360).
func heading_deg() -> float:
	return Geo.apply_declination(_deg, _declination) if _has_declination else _deg


## Always the raw magnetic azimuth, exactly as the field reported it. The true
## heading is derived, never stored, so there is one place a declination can be
## folded in and one place it can be wrong.
func heading_magnetic() -> float:
	return _deg


## One of Geo.ACC_*. Derived, not reported -- see the header.
func accuracy() -> int:
	return _accuracy


## The level said out loud, for a log line.
func accuracy_name() -> String:
	return Geo.accuracy_name(_accuracy)


## True when the picture may be turned from this compass.
func trusted() -> bool:
	return Geo.accuracy_trusted(_accuracy)


## "flat" or "upright". The two poses read the heading off different device
## axes, so when the bearings look odd this is the first question worth asking.
func pose() -> String:
	return _pose


## True when samples are ACTUALLY ARRIVING right now. Not "does a source exist":
## a source that has gone silent still exists, and a dial that turned the world
## by a seventeen-second-old number looked entirely healthy doing it.
func live() -> bool:
	return _seen and _quiet_for < QUIET_FRAMES


## True when a heading has ever arrived. `seen() and not live()` is the "compass
## quiet -- the peers show the last heading" state the radar captions.
func seen() -> bool:
	return _seen


## True when the published heading is referenced to TRUE north, which is exactly
## when somebody has handed in a declination.
func true_north() -> bool:
	return _has_declination


func declination() -> float:
	return _declination


# -- the two seams ------------------------------------------------------------

## THE NAV DOOR'S FIRST GIFT. A future add-on that knows where the body is can
## evaluate the World Magnetic Model and hand the declination in; from that
## moment `heading_rad()` is true north and every caption says so. Passing NAN
## or a wild number is refused rather than believed: declination on Earth never
## exceeds 180 deg and, off the polar regions, never 30.
func set_declination(deg: float) -> void:
	if not is_finite(deg) or absf(deg) > 180.0:
		return
	if _has_declination and is_equal_approx(_declination, deg):
		return
	_declination = deg
	_has_declination = true
	heading_changed.emit(heading_deg())


## Forget the declination and fall back to magnetic north. What an add-on calls
## when it is detached, so the glass stops claiming a north nobody is computing.
func clear_declination() -> void:
	if not _has_declination:
		return
	_has_declination = false
	_declination = 0.0
	heading_changed.emit(heading_deg())


## THE NAV DOOR'S SECOND GIFT. Where the body is. BASE NEVER CALLS THIS: there
## is no GPS provider in this app, no permission request and no timer. It exists
## so an add-on has one place to put a fix, and so whatever computes a
## declination can read it back out of `fix()`.
##
## A malformed pair is ignored rather than stored -- `Geo.is_fix` is the gate
## everything that comes off a wire goes through.
func set_fix(lat: float, lon: float, acc_m: float = 0.0) -> void:
	var f := {"lat": lat, "lon": lon, "acc": maxf(0.0, acc_m)}
	if not Geo.is_fix(f):
		return
	_fix = f


## The fix, or an empty dictionary. Empty is the normal state in base.
func fix() -> Dictionary:
	return _fix.duplicate()


## True when somebody has handed in a position good enough to place by.
func has_fix() -> bool:
	return Geo.is_placeable(_fix)


# -- internals ----------------------------------------------------------------

func _set_accuracy(level: int) -> void:
	if level == _accuracy:
		return
	_accuracy = level
	accuracy_changed.emit(level)


func _set_pose(p: String) -> void:
	if p == _pose:
		return
	_pose = p
	pose_changed.emit(p)
