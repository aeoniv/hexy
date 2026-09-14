class_name Geo
extends RefCounted

## PURE EARTH MATH. No node, no timer, no radio, no permission dialog.
##
## Ported from the origin app's `scripts/social/geo.gd`, which was a Node that
## owned an Android location plugin as well as the arithmetic. Everything that
## needed the plugin stayed behind; everything that is only numbers came here,
## as statics, so a headless test can check the 0/360 seam and the haversine
## without a phone anywhere in sight.
##
## WHAT IS DELIBERATELY NOT HERE. There is no provider, no `current()`, no
## `changed` signal and no GPS. A position is a future add-on's gift: it comes
## in through `Heading.set_fix()` and `FlyCalciumRadar2D.set_peer_distances_m()`
## and nothing in base ever asks the platform for one. The seam is these
## statics: an add-on that learns two lat/lon pairs calls `bearing_deg` and
## `distance_m` here and hands the answers in. Base never opens the door.
##
## STATES, NOT CRASHES. Every predicate answers "we do not know" with a value a
## caller can carry on with: -1.0 for a bearing or a distance that cannot be
## computed, `false` for a fix that is not a fix. Nothing throws.


# -- hold pose ----------------------------------------------------------------
# The compass azimuth is a rotation about an axis that only points at the sky
# while the phone is lying flat. Held upright to be looked at -- the pose this
# radar is actually used in -- that axis is horizontal and the azimuth
# degenerates, so the heading has to be read off a different device axis.
# `heading_deg` below switches on the pose for exactly that reason.

## Lying down, either face. The classic compass pose.
const POSE_FLAT := "flat"
## Standing up, screen toward a face. The phone faces the way you are looking.
const POSE_UPRIGHT := "upright"
## Screen tilt off horizontal at which the upright convention takes over...
const POSE_UPRIGHT_ENTER_DEG := 30.0
## ...and the tilt it must fall back under to hand it back. The gap between the
## two is not slack, it is the whole point: a phone resting at the switch point
## must not flip convention twice a second and shiver the dial.
const POSE_UPRIGHT_EXIT_DEG := 20.0


## Which pose a tilt means, given the pose we were already in. A tilt inside the
## dead band is not an answer, so it keeps `previous` -- which is why this takes
## one and why a phone held at 25 deg is stable rather than undecided.
static func classify_pose(tilt_deg: float, previous: String) -> String:
	if tilt_deg >= POSE_UPRIGHT_ENTER_DEG:
		return POSE_UPRIGHT
	if tilt_deg <= POSE_UPRIGHT_EXIT_DEG:
		return POSE_FLAT
	return previous


## Screen tilt off horizontal, from the world-up component of the screen
## normal. +-1 is flat, 0 is on edge. The abs() is deliberate: face-down is
## still flat.
static func screen_tilt_deg(up_component: float) -> float:
	return rad_to_deg(acos(clampf(absf(up_component), 0.0, 1.0)))


# -- compass reliability ------------------------------------------------------
# The numbers are Android's SENSOR_STATUS_ACCURACY_*, kept because they are the
# vocabulary the whole origin codebase (and this radar's captions) speak.
#
# GODOT EXPOSES NO CALIBRATION STATE. `Input.get_magnetometer()` hands back a
# vector and nothing else -- there is no onAccuracyChanged, and without an
# Android plugin there never will be. So `Heading` DERIVES a level instead of
# being told one, and the derivation is deliberately conservative: see
# `accuracy_from_field` below. It is an inference, not a platform verdict, and
# the doc comment on Heading.accuracy() says so out loud.
const ACC_UNRELIABLE := 0
const ACC_LOW := 1
const ACC_MEDIUM := 2
const ACC_HIGH := 3
## Before anything has been measured at all. Treated as TRUSTED, deliberately:
## a dial that refused to work until a verdict that may never arrive would be a
## dial that never works. Only an explicit LOW or UNRELIABLE takes the picture's
## permission to turn away.
const ACC_UNKNOWN := -1


## True when the compass is worth drawing a direction from.
static func accuracy_trusted(level: int) -> bool:
	return level == ACC_UNKNOWN or level >= ACC_MEDIUM


## The level, said out loud, for a log and for the hint on screen.
static func accuracy_name(level: int) -> String:
	match level:
		ACC_HIGH: return "high"
		ACC_MEDIUM: return "medium"
		ACC_LOW: return "low"
		ACC_UNRELIABLE: return "unreliable"
		_: return "unknown"


# -- the field itself ---------------------------------------------------------
# Earth's surface field runs about 25 uT at the magnetic equator to about 65 uT
# near the poles. A reading well outside that band is not a heading, it is a
# speaker magnet, a laptop hinge, a car dashboard or a fridge door -- and the
# only honest response is to stop turning the picture from it.

## Weakest total field anywhere on Earth's surface, minus a margin.
const FIELD_MIN_UT := 20.0
## Strongest, plus a margin.
const FIELD_MAX_UT := 70.0
## Inside this much of the band's middle the field is textbook clean.
const FIELD_GOOD_MIN_UT := 25.0
const FIELD_GOOD_MAX_UT := 65.0
## Sample-to-sample wobble of the total field, in uT, above which the heading is
## being shaken by something local rather than by Earth. A hand-held phone in a
## clean field wobbles well under a microtesla between frames.
const JITTER_LOW_UT := 1.5
## ...and past this the reading is not a field measurement at all.
const JITTER_BAD_UT := 6.0


## HOW MUCH TO BELIEVE A MAGNETOMETER NOBODY WILL VOUCH FOR.
##
## Two signals, both purely local, both honest about what they can and cannot
## see:
##
##   MAGNITUDE. The total field must plausibly be Earth's. Outside
##   [FIELD_MIN_UT, FIELD_MAX_UT] something ferrous is closer than the planet,
##   and that is UNRELIABLE. Inside the wider band but outside the clean one is
##   LOW -- readable, not trustworthy.
##
##   JITTER. The mean absolute change in total field between recent samples. A
##   still phone in a clean field is quiet; one near a motor, a magnet or a
##   moving laptop lid is not. Past JITTER_BAD_UT it is UNRELIABLE; past
##   JITTER_LOW_UT it is LOW.
##
## WHAT THIS CANNOT SEE, and the reason it is capped at MEDIUM unless both
## signals are clean: a *constant* hard-iron offset. A steady bias from the
## phone's own speaker shifts every heading by the same wrong amount and is
## perfectly quiet and perfectly plausible in magnitude. Only a real calibration
## routine catches that, and Godot gives us none -- so this never claims HIGH
## on a shaky field and the caption never claims more than the sensor can back.
##
## `jitter` below zero means "not measured yet", which is the first frame.
static func accuracy_from_field(magnitude_ut: float, jitter_ut: float) -> int:
	if magnitude_ut <= 0.0:
		return ACC_UNKNOWN
	if magnitude_ut < FIELD_MIN_UT or magnitude_ut > FIELD_MAX_UT:
		return ACC_UNRELIABLE
	if jitter_ut >= JITTER_BAD_UT:
		return ACC_UNRELIABLE
	if magnitude_ut < FIELD_GOOD_MIN_UT or magnitude_ut > FIELD_GOOD_MAX_UT:
		return ACC_LOW
	if jitter_ut >= JITTER_LOW_UT:
		return ACC_LOW
	if jitter_ut < 0.0:
		# One sample, nothing to compare it with. The magnitude is clean, so the
		# reading is usable; HIGH would be a claim about steadiness we have not
		# watched for long enough to make.
		return ACC_MEDIUM
	return ACC_HIGH


# -- tilt-compensated heading -------------------------------------------------
# THE ONE PIECE OF MATH THAT DID NOT EXIST IN THE ORIGIN GDSCRIPT. There it was
# Kotlin: SensorManager.getRotationMatrix + remapCoordinateSystem + getOrientation
# inside the IxLoc plugin, and GDScript only ever saw a finished azimuth. With
# no plugin, Godot hands us the two raw vectors instead and the remap has to
# happen here -- which is better, because here a test can check it.
#
# THE CONVENTION, WRITTEN DOWN ONCE.
#   `grav` points DOWN, toward the ground, in DEVICE axes. That is what
#   `Input.get_gravity()` reports: a phone lying flat face-up is being pulled
#   through its own back, so gravity is roughly (0, 0, -9.8) with +Z out of the
#   screen.
#   Device axes, screen upright in the hand: +X right, +Y toward the top of the
#   screen, +Z out of the glass toward the face.
#   `mag` is the magnetic field in the same device axes, microtesla.
#
# The arithmetic is the textbook one and has no trigonometric special cases:
#   down = normalize(grav)
#   east = normalize(down x mag)        -- perpendicular to both, horizontal
#   north = east x down                 -- completes the frame: n x e = d, the
#                                          right-handed NED convention
# The ORDER of those two cross products is the whole of the handedness, and
# getting it backwards mirrors the dial east-for-west without changing north or
# south -- which is why the test asserts all four cardinals and not just one.
#   heading = atan2(forward . east, forward . north)
# which is degrees CLOCKWISE FROM MAGNETIC NORTH, because east is 90 deg.


## The device axis that counts as "the way it is pointing", for a pose.
##
## FLAT: the top of the phone, +Y. Lay it on a table and it is a map on a table.
##
## UPRIGHT: -Z, out through the BACK of the screen. Held up to a face, +Y is
## vertical -- projected onto the horizontal plane it collapses to nothing and
## the azimuth degenerates -- while -Z is the direction the glass is aimed at,
## which is the direction the person holding it is looking. That is the number
## the radar's north-up mode wants: screen-up is the way the phone faces.
static func pose_forward(pose: String) -> Vector3:
	return Vector3(0.0, 0.0, -1.0) if pose == POSE_UPRIGHT else Vector3(0.0, 1.0, 0.0)


## Magnetic heading in degrees clockwise from north, [0, 360), from the two raw
## device vectors. -1.0 when the pair carries no heading at all: a zero or
## non-finite vector (every desktop, headless included), or a field exactly
## parallel to gravity, where there is no horizontal component to point with.
##
## -1.0 is the same "we do not know" every other refusal in this file uses, and
## it is a value no real bearing can take.
static func heading_deg(mag: Vector3, grav: Vector3, pose: String = POSE_FLAT) -> float:
	if not (_finite3(mag) and _finite3(grav)):
		return -1.0
	if mag.length() < 0.0001 or grav.length() < 0.0001:
		return -1.0
	var down := grav.normalized()
	var east := down.cross(mag)
	if east.length() < 0.0001:
		# The field points straight down the gravity vector. Directly over a
		# magnetic pole this is real; everywhere else it is a magnet. Either way
		# there is no horizontal direction left to name.
		return -1.0
	east = east.normalized()
	var north := east.cross(down)
	var fwd := pose_forward(pose)
	return fposmod(rad_to_deg(atan2(fwd.dot(east), fwd.dot(north))), 360.0)


## The pose those two vectors are being held in, given the pose we were in.
## Reads the screen normal (+Z) against world up (-down).
static func pose_of(grav: Vector3, previous: String = POSE_FLAT) -> String:
	if not _finite3(grav) or grav.length() < 0.0001:
		return previous
	var up := -grav.normalized()
	return classify_pose(screen_tilt_deg(up.z), previous)


static func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


# -- circle arithmetic --------------------------------------------------------

## Signed shortest turn from `a` to `b`, in (-180, 180]. Positive is clockwise.
## Every heading comparison goes through it, because subtracting two compass
## bearings directly is wrong exactly once per revolution.
static func heading_delta(a: float, b: float) -> float:
	return fposmod(b - a + 180.0, 360.0) - 180.0


## One low-pass step toward `raw`, taken on the circle rather than on the
## number. Averaging 359 and 1 arithmetically gives 180 -- a needle crossing
## north would swing all the way through south. Interpolating the TURN has no
## seam, so the same alpha behaves identically at every bearing.
static func heading_smooth(prev: float, raw: float, alpha: float) -> float:
	return fposmod(prev + heading_delta(prev, raw) * clampf(alpha, 0.0, 1.0), 360.0)


# -- true north ---------------------------------------------------------------
# A magnetometer measures the field, and the field does not point at the pole.
# The difference is the magnetic declination: about +4 deg in Berlin, -14 in
# Seattle, past 20 in plenty of inhabited places -- bigger than the
# ON_TARGET_DEG window the radar calls "straight ahead", so it is not noise.
#
# The number itself comes from the World Magnetic Model, which needs a position
# and a date, so it exists only once a fix has landed -- and a fix is an add-on's
# gift, not base's. The arithmetic lives here, where it can be checked at the
# 0/360 seam without a magnetometer or a satellite.

## Magnetic azimuth plus declination, folded back onto the circle. Declination
## is east-positive: true = magnetic + declination.
static func apply_declination(magnetic: float, declination: float) -> float:
	return fposmod(magnetic + declination, 360.0)


## How far the body must move before the declination is worth recomputing. The
## WMM varies by well under a tenth of a degree per kilometre anywhere on Earth.
const DECLINATION_REFRESH_M := 1000.0
## ...and how long before it is recomputed anyway. Declination drifts by a
## fraction of a degree per YEAR; five minutes is not about the field moving, it
## is about a phone carried a long way by a source too coarse to notice.
const DECLINATION_REFRESH_MS := 300000


## True when the declination cached for `last` no longer describes `now_fix`.
## An empty `last` means nothing has ever been computed, which is always due.
static func declination_needs_refresh(last: Dictionary, now_fix: Dictionary,
		last_ms: int, now_ms: int) -> bool:
	if not is_fix(now_fix):
		return false
	if not is_fix(last):
		return true
	if now_ms - last_ms >= DECLINATION_REFRESH_MS:
		return true
	return distance_m(last, now_fix) >= DECLINATION_REFRESH_M


# -- positions ----------------------------------------------------------------

## Mean Earth radius (IUGG). Haversine on a sphere is good to ~0.5% -- three
## orders of magnitude finer than a coarse fix, so the ellipsoid can wait.
const EARTH_RADIUS_M := 6371008.8


## True when a dictionary carries a usable position. Everything that reads a
## position off a wire goes through this: an older peer sends no geo at all, a
## newer one might send a shape we do not expect.
static func is_fix(d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	var dd: Dictionary = d
	if not (dd.has("lat") and dd.has("lon")):
		return false
	var lat: Variant = dd["lat"]
	var lon: Variant = dd["lon"]
	if not ((lat is float or lat is int) and (lon is float or lon is int)):
		return false
	return absf(float(lat)) <= 90.0 and absf(float(lon)) <= 180.0


## True when a dictionary carries a usable HEADING -- the `deg` half of a
## presence heartbeat. Degrees are NOT range-checked before folding: 400 is a
## well-formed bearing written badly, and fposmod says what it means.
## Non-finite is not.
static func is_heading(d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	var dd: Dictionary = d
	if not dd.has("deg"):
		return false
	var deg: Variant = dd["deg"]
	if not (deg is float or deg is int):
		return false
	return is_finite(float(deg))


## The bearing inside a heading dict, folded onto the circle. -1.0 when there
## is none.
static func heading_of(d: Variant) -> float:
	return fposmod(float((d as Dictionary)["deg"]), 360.0) if is_heading(d) else -1.0


## Coarsest fix that can still say WHERE IN THE ROOM somebody is. A fused
## provider indoors hands back a cached network fix with `acc` around 2000 m --
## a real position, honestly labelled, and useless here: two phones side by side
## on one table get centroids kilometres apart. A radius wider than half a room
## cannot place anyone inside it, so the threshold is LEAVE_M / 2.
const PLACEABLE_ACC_M := 50.0


## True when a fix is good enough to PLACE someone by, not merely well-formed.
## `acc` absent or <= 0 means the source did not say, and an unstated accuracy
## is taken at face value.
static func is_placeable(d: Variant) -> bool:
	if not is_fix(d):
		return false
	var acc := float((d as Dictionary).get("acc", 0.0))
	return acc <= 0.0 or acc <= PLACEABLE_ACC_M


## Great-circle metres between two fixes. Haversine: stable at the short
## distances this game cares about, where the spherical law of cosines loses
## precision. -1.0 when either side is not a fix.
static func distance_m(a: Dictionary, b: Dictionary) -> float:
	if not (is_fix(a) and is_fix(b)):
		return -1.0
	var lat1 := deg_to_rad(float(a["lat"]))
	var lat2 := deg_to_rad(float(b["lat"]))
	var dlat := lat2 - lat1
	var dlon := deg_to_rad(float(b["lon"]) - float(a["lon"]))
	var h := sin(dlat / 2.0) * sin(dlat / 2.0) \
		+ cos(lat1) * cos(lat2) * sin(dlon / 2.0) * sin(dlon / 2.0)
	return 2.0 * EARTH_RADIUS_M * asin(sqrt(clampf(h, 0.0, 1.0)))


## Initial great-circle bearing from a to b, degrees clockwise from true north
## in [0, 360). "Which way do I turn to walk to you." -1.0 when either side is
## not a fix.
static func bearing_deg(a: Dictionary, b: Dictionary) -> float:
	if not (is_fix(a) and is_fix(b)):
		return -1.0
	var lat1 := deg_to_rad(float(a["lat"]))
	var lat2 := deg_to_rad(float(b["lat"]))
	var dlon := deg_to_rad(float(b["lon"]) - float(a["lon"]))
	var y := sin(dlon) * cos(lat2)
	var x := cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)


# -- honest uncertainty -------------------------------------------------------
# TWO 6 m FIXES CANNOT RESOLVE A 6 m SEPARATION. Each position is a disc, and
# when the discs overlap the vector between their centres is dominated by their
# own error rather than by where the two bodies are.
#
# The origin app first REFUSED the bearing in that case and pinned the peer to a
# ring. That was arithmetically right and a product mistake: the whole point of
# the screen is FINDING somebody, and a marker that cannot move is a marker you
# cannot walk toward. So the direction is always shown and the WIDTH of what is
# drawn carries how much it can be believed:
#
#     half-angle = atan((acc_a + acc_b) / distance)
#
# the angle subtended at one body by the other's combined error circle:
#
#     100 m apart, 6+6 m fixes ->  atan(12/100) =  7 deg   a narrow band
#      20 m apart, 6+6 m fixes ->  atan(12/20)  = 31 deg   "roughly that way"
#       6 m apart, 3+7 m fixes ->  atan(10/6)   = 59 deg   most of a quadrant
#       1 m apart, 3+7 m fixes ->  atan(10/1)   = 84 deg   nearly all of it
#
# Clamped at both ends: a zero-width band is invisible ink, and past the ceiling
# the band has eaten so much of the circle that pointing at all is a lie.

## Adding the radii, not the root-sum-square: the pessimistic geometric reading,
## where both errors lie along the line joining the two people. K = 1.0 is the
## bare "the discs touch" case; 1.5 refuses bearings across a whole room. 1.25
## puts the floor at 15 m for a pair of 6 m fixes.
const BEARING_ACC_K := 1.25

## Narrowest band ever drawn. Not a claim about precision -- a minimum ink.
const SPREAD_MIN_DEG := 3.0
## Widest band that is still a band. Past this the caller draws a full ring.
const SPREAD_MAX_DEG := 88.0
## At or past this there is no direction left: every bearing is about as likely
## as any other.
const SPREAD_RING_DEG := 85.0


## The separation, in metres, below which a bearing between these two fixes is
## not worth claiming confidently. 0.0 when neither side stated an accuracy.
static func bearing_floor_m(a: Dictionary, b: Dictionary) -> float:
	var acc_a := maxf(0.0, float(a.get("acc", 0.0)))
	var acc_b := maxf(0.0, float(b.get("acc", 0.0)))
	return BEARING_ACC_K * (acc_a + acc_b)


## True when two people are so close, relative to how well either is located,
## that the direction from one to the other is noise. Distance survives -- it is
## a scalar and degrades gracefully -- but a CONFIDENT bearing does not.
static func close_range(a: Dictionary, b: Dictionary) -> bool:
	var d := distance_m(a, b)
	if d < 0.0:
		return false
	return d < bearing_floor_m(a, b)


## Half-angle of the uncertainty band between two fixes, in degrees. A
## non-positive distance is the fully degenerate case -- the same point, or two
## fixes that round to it -- and gets the maximum rather than a division.
static func bearing_spread_deg(a: Dictionary, b: Dictionary) -> float:
	var d := distance_m(a, b)
	if d <= 0.0:
		return SPREAD_MAX_DEG
	var acc := maxf(0.0, float(a.get("acc", 0.0))) + maxf(0.0, float(b.get("acc", 0.0)))
	return clampf(rad_to_deg(atan(acc / d)), SPREAD_MIN_DEG, SPREAD_MAX_DEG)


## True when the band has grown so wide that a direction is no longer worth
## drawing as a direction. The caller draws a full ring instead: the peer is
## somewhere around you, at a distance that is still perfectly real.
static func bearing_is_ring(a: Dictionary, b: Dictionary) -> bool:
	return bearing_spread_deg(a, b) >= SPREAD_RING_DEG


## May I draw a CONFIDENT arrow between these two -- the "walk exactly this way"
## arrow? Placement never asks this; a wide band is a better answer than none.
static func bearing_trustworthy(a: Dictionary, b: Dictionary) -> bool:
	if not (is_placeable(a) and is_placeable(b)):
		return false
	return not close_range(a, b)


# -- metres to pixels ---------------------------------------------------------

## Arm's length. Inside this a peer is as big as they ever get.
const NEAR_M := 10.0
## Past this they have left the room.
const LEAVE_M := 100.0


## True when a peer is far enough away to count as gone.
static func has_left(distance: float) -> bool:
	return distance > LEAVE_M
