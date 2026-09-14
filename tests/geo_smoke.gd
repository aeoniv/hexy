extends MainLoop

## GEO IS PURE MATH, SO IT IS TESTED WITHOUT A PHONE.
##
## Bearings and distances against hand-computable pairs, the tilt-compensated
## heading against vectors whose answer is obvious by construction, and every
## refusal path -- because "we do not know" is a state this file is required to
## reach without crashing.

const GeoScript := preload("res://scripts/core/geo.gd")

var passes := 0
var failures := 0


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (got %.4f, want %.4f +-%.4f)" % [msg, a, b, eps])


func _process(_delta: float) -> bool:
	print("HEXY_TEST: Geo pure-math smoke...")
	_test_distance()
	_test_bearing()
	_test_heading_vectors()
	_test_pose()
	_test_accuracy()
	_test_circle()
	_test_spread()
	print("\n=== GEO RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Geo verified)")
	return true


func _test_distance() -> void:
	print("\n- haversine")
	var origin := {"lat": 0.0, "lon": 0.0}
	check(is_equal_approx(GeoScript.distance_m(origin, origin), 0.0), "a point is nowhere from itself")
	# One degree of latitude is one 360th of the meridian, everywhere.
	near(GeoScript.distance_m(origin, {"lat": 1.0, "lon": 0.0}),
		TAU * GeoScript.EARTH_RADIUS_M / 360.0, 1.0, "one degree of latitude")
	# One degree of longitude on the equator is the same, and at 60 deg north
	# it is half of it -- cos(60) = 0.5, which is the whole point of haversine.
	near(GeoScript.distance_m({"lat": 60.0, "lon": 0.0}, {"lat": 60.0, "lon": 1.0}),
		TAU * GeoScript.EARTH_RADIUS_M / 720.0, 200.0, "a degree of longitude halves at 60N")
	# A metre is a metre: 0.001 degrees of latitude is about 111 m.
	near(GeoScript.distance_m(origin, {"lat": 0.001, "lon": 0.0}), 111.2, 0.5, "a tenth of a millidegree")
	check(GeoScript.distance_m(origin, {}) < 0.0, "no fix, no distance -- and no crash")
	check(GeoScript.distance_m({"lat": 91.0, "lon": 0.0}, origin) < 0.0, "an impossible latitude is not a fix")


func _test_bearing() -> void:
	print("\n- initial great-circle bearing")
	var origin := {"lat": 0.0, "lon": 0.0}
	near(GeoScript.bearing_deg(origin, {"lat": 1.0, "lon": 0.0}), 0.0, 0.01, "due north is 0")
	near(GeoScript.bearing_deg(origin, {"lat": 0.0, "lon": 1.0}), 90.0, 0.01, "due east is 90")
	near(GeoScript.bearing_deg(origin, {"lat": -1.0, "lon": 0.0}), 180.0, 0.01, "due south is 180")
	near(GeoScript.bearing_deg(origin, {"lat": 0.0, "lon": -1.0}), 270.0, 0.01, "due west is 270")
	# On the equator a 45 deg diagonal really is 45 deg; away from it the
	# convergence of the meridians bends it, which is why this is the one place
	# the number is asserted exactly.
	near(GeoScript.bearing_deg(origin, {"lat": 1.0, "lon": 1.0}), 45.0, 0.02, "northeast on the equator")
	check(GeoScript.bearing_deg(origin, {}) < 0.0, "no fix, no bearing")
	check(GeoScript.is_placeable({"lat": 0.0, "lon": 0.0, "acc": 2000.0}) == false,
		"a 2 km cached fix is a real position that cannot place anyone")
	check(GeoScript.is_placeable({"lat": 0.0, "lon": 0.0}), "an unstated accuracy is taken at face value")


## THE TILT COMPENSATION, against vectors whose answer is obvious.
## Device axes: +X right, +Y toward the top of the screen, +Z out of the glass.
## `grav` points DOWN, toward the ground.
func _test_heading_vectors() -> void:
	print("\n- tilt-compensated heading")
	# Flat on a table, face up: gravity goes out through the back, -Z.
	var flat_grav := Vector3(0.0, 0.0, -9.8)
	# A field with no dip, pointing at the top of the phone: the phone's top is
	# north, so the heading is 0.
	near(GeoScript.heading_deg(Vector3(0.0, 30.0, 0.0), flat_grav, GeoScript.POSE_FLAT),
		0.0, 0.01, "flat, field out of the top: north")
	# Turn the phone 90 deg clockwise and the field now comes out of its right
	# edge... which means the phone is facing east.
	near(GeoScript.heading_deg(Vector3(-30.0, 0.0, 0.0), flat_grav, GeoScript.POSE_FLAT),
		90.0, 0.01, "flat, field out of the left edge: facing east")
	near(GeoScript.heading_deg(Vector3(0.0, -30.0, 0.0), flat_grav, GeoScript.POSE_FLAT),
		180.0, 0.01, "flat, field into the top: facing south")
	near(GeoScript.heading_deg(Vector3(30.0, 0.0, 0.0), flat_grav, GeoScript.POSE_FLAT),
		270.0, 0.01, "flat, field out of the right edge: facing west")
	# DIP IS WHAT TILT COMPENSATION IS FOR. The real field points into the
	# ground at 65 deg in northern Europe; the horizontal part still says north.
	near(GeoScript.heading_deg(Vector3(0.0, 20.0, -45.0), flat_grav, GeoScript.POSE_FLAT),
		0.0, 0.01, "a steeply dipping field still reads north when flat")
	# UPRIGHT reads a different axis. Held vertically, screen toward a face:
	# gravity runs down the screen, -Y. The way the phone FACES is -Z, out the
	# back. A field along -Z is therefore straight ahead: north.
	var up_grav := Vector3(0.0, -9.8, 0.0)
	near(GeoScript.heading_deg(Vector3(0.0, 0.0, -30.0), up_grav, GeoScript.POSE_UPRIGHT),
		0.0, 0.01, "upright, field out the back: facing north")
	near(GeoScript.heading_deg(Vector3(-30.0, 0.0, 0.0), up_grav, GeoScript.POSE_UPRIGHT),
		90.0, 0.01, "upright, field out the left edge: facing east")
	# And the same vectors read FLAT are degenerate, which is exactly why the
	# pose switch exists: +Y is straight up, so it has no horizontal part.
	near(GeoScript.heading_deg(Vector3(0.0, 0.0, -30.0), up_grav, GeoScript.POSE_FLAT),
		0.0, 90.01, "the flat convention degenerates upright -- hence two poses")
	# The refusals. Headless is the first of them and it is not an error.
	check(GeoScript.heading_deg(Vector3.ZERO, flat_grav) < 0.0, "no magnetometer, no heading")
	check(GeoScript.heading_deg(Vector3(0.0, 30.0, 0.0), Vector3.ZERO) < 0.0, "no gravity, no heading")
	check(GeoScript.heading_deg(Vector3(0.0, 0.0, -30.0), flat_grav) < 0.0,
		"a field straight down the gravity vector has no direction in it")
	check(GeoScript.heading_deg(Vector3(NAN, 0.0, 0.0), flat_grav) < 0.0, "NaN is not a field")


func _test_pose() -> void:
	print("\n- hold pose")
	check(GeoScript.pose_of(Vector3(0.0, 0.0, -9.8)) == GeoScript.POSE_FLAT, "face up is flat")
	check(GeoScript.pose_of(Vector3(0.0, 0.0, 9.8)) == GeoScript.POSE_FLAT, "face down is still flat")
	check(GeoScript.pose_of(Vector3(0.0, -9.8, 0.0)) == GeoScript.POSE_UPRIGHT, "on end is upright")
	near(GeoScript.screen_tilt_deg(1.0), 0.0, 0.01, "screen normal straight up is no tilt")
	near(GeoScript.screen_tilt_deg(0.0), 90.0, 0.01, "on edge is a right angle")
	near(GeoScript.screen_tilt_deg(-1.0), 0.0, 0.01, "face down is no tilt either")
	# THE DEAD BAND IS THE WHOLE POINT: a phone resting at the switch point must
	# not flip convention twice a second.
	check(GeoScript.classify_pose(25.0, GeoScript.POSE_FLAT) == GeoScript.POSE_FLAT,
		"inside the band, a flat phone stays flat")
	check(GeoScript.classify_pose(25.0, GeoScript.POSE_UPRIGHT) == GeoScript.POSE_UPRIGHT,
		"inside the band, an upright phone stays upright")
	check(GeoScript.classify_pose(31.0, GeoScript.POSE_FLAT) == GeoScript.POSE_UPRIGHT, "past the enter angle it flips")
	check(GeoScript.classify_pose(19.0, GeoScript.POSE_UPRIGHT) == GeoScript.POSE_FLAT, "under the exit angle it flips back")


func _test_accuracy() -> void:
	print("\n- derived compass trust")
	check(GeoScript.accuracy_from_field(0.0, -1.0) == GeoScript.ACC_UNKNOWN, "nothing measured is UNKNOWN")
	check(GeoScript.accuracy_from_field(48.0, 0.2) == GeoScript.ACC_HIGH, "a clean, quiet Earth field is HIGH")
	check(GeoScript.accuracy_from_field(48.0, -1.0) == GeoScript.ACC_MEDIUM,
		"one sample cannot claim steadiness, so MEDIUM")
	check(GeoScript.accuracy_from_field(48.0, 3.0) == GeoScript.ACC_LOW, "a jittering field is LOW")
	check(GeoScript.accuracy_from_field(48.0, 9.0) == GeoScript.ACC_UNRELIABLE, "a shaking field is UNRELIABLE")
	check(GeoScript.accuracy_from_field(22.0, 0.1) == GeoScript.ACC_LOW, "plausible but weak is LOW")
	check(GeoScript.accuracy_from_field(400.0, 0.1) == GeoScript.ACC_UNRELIABLE,
		"400 uT is a speaker magnet, not a planet")
	check(GeoScript.accuracy_trusted(GeoScript.ACC_UNKNOWN), "silence keeps the behaviour that predates the sensor")
	check(GeoScript.accuracy_trusted(GeoScript.ACC_MEDIUM), "MEDIUM is usable")
	check(not GeoScript.accuracy_trusted(GeoScript.ACC_LOW), "LOW is not")
	check(not GeoScript.accuracy_trusted(GeoScript.ACC_UNRELIABLE), "UNRELIABLE certainly is not")
	check(GeoScript.accuracy_name(GeoScript.ACC_HIGH) == "high", "the level says its own name")


func _test_circle() -> void:
	print("\n- the 0/360 seam")
	near(GeoScript.heading_delta(350.0, 10.0), 20.0, 0.001, "crossing north clockwise is +20, not -340")
	near(GeoScript.heading_delta(10.0, 350.0), -20.0, 0.001, "and back again is -20")
	near(GeoScript.heading_smooth(359.0, 1.0, 0.5), 0.0, 0.001, "smoothing across north does not swing through south")
	near(GeoScript.apply_declination(359.0, 4.0), 3.0, 0.001, "declination folds back onto the circle")
	near(GeoScript.apply_declination(10.0, -14.0), 356.0, 0.001, "and a western declination does too")
	near(GeoScript.heading_of({"deg": 400.0}), 40.0, 0.001, "a badly written bearing is still a bearing")
	check(GeoScript.heading_of({}) < 0.0, "no deg, no heading")
	check(not GeoScript.is_heading({"deg": NAN}), "NaN is not a heading")


func _test_spread() -> void:
	print("\n- honest uncertainty")
	var a := {"lat": 0.0, "lon": 0.0, "acc": 6.0}
	# 100 m apart with 6+6 m fixes: a narrow band.
	var far := {"lat": 0.0009, "lon": 0.0, "acc": 6.0}
	near(GeoScript.bearing_spread_deg(a, far), rad_to_deg(atan(12.0 / 100.0)), 1.0, "100 m apart is about 7 deg")
	check(not GeoScript.bearing_is_ring(a, far), "which is a band, not a ring")
	# The same pair on one desk: the discs overlap and there is no direction left.
	var here := {"lat": 0.0, "lon": 0.0, "acc": 6.0}
	check(GeoScript.bearing_is_ring(a, here), "two fixes on the same spot are a ring")
	check(GeoScript.close_range(a, here), "and are inside the confident-arrow floor")
	check(not GeoScript.bearing_trustworthy(a, here), "so no confident arrow is drawn")
	check(GeoScript.bearing_trustworthy(a, far), "at 100 m one is")
	near(GeoScript.bearing_floor_m(a, here), GeoScript.BEARING_ACC_K * 12.0, 0.001, "the floor is K times the summed radii")
	near(GeoScript.bearing_spread_deg({"lat": 0.0, "lon": 0.0}, {"lat": 1.0, "lon": 0.0}),
		GeoScript.SPREAD_MIN_DEG, 0.001, "an unstated accuracy gets the minimum ink, never a hairline claim")
	check(GeoScript.has_left(101.0) and not GeoScript.has_left(99.0), "past LEAVE_M they have left the room")
