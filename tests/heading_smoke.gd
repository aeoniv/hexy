extends MainLoop

## HEADLESS IS A REAL STATE, AND THIS IS THE TEST THAT SAYS SO.
##
## On this runner `Input.get_magnetometer()` returns the zero vector forever.
## The node must come up NOT LIVE, publish nothing, invent nothing, and still
## answer every question a caller asks. Then the seams: a declination turns the
## published heading into true north, and a fix has a place to land even though
## nothing in base will ever put one there.

const HeadingScript := preload("res://scripts/core/heading.gd")
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


func _process(_delta: float) -> bool:
	print("HEXY_TEST: Heading headless smoke...")
	_test_cold()
	_test_fed()
	_test_declination()
	_test_fix_seam()
	_test_quiet()
	print("\n=== HEADING RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Heading verified)")
	return true


## NOTHING IN, NOTHING OUT.
func _test_cold() -> void:
	print("\n- a phone with no magnetometer, which is this runner")
	var h: Node = HeadingScript.new()
	check(not h.live(), "cold, it is not live")
	check(not h.seen(), "and nothing has ever been seen")
	check(is_equal_approx(h.heading_rad(), 0.0), "the heading is 0.0 and it is not a claim")
	check(h.accuracy() == GeoScript.ACC_UNKNOWN, "the accuracy is UNKNOWN, not a guess")
	check(h.pose() == GeoScript.POSE_FLAT, "the pose defaults to flat")
	check(not h.true_north(), "and it is certainly not true north")
	check(h.fix().is_empty(), "no fix -- base never asks the platform for one")
	check(not h.has_fix(), "and says so")
	# The real headless path: Godot's own zero vectors, fed the way _process does.
	for i in range(8):
		h.step(Input.get_magnetometer(), Input.get_gravity())
	check(not h.live(), "eight frames of Godot's own sensors and it is STILL not live")
	check(is_equal_approx(h.heading_rad(), 0.0), "and still has not invented a direction")
	h.free()


func _test_fed() -> void:
	print("\n- hand-fed vectors, which is what a phone would do")
	var h: Node = HeadingScript.new()
	var flat_grav := Vector3(0.0, 0.0, -9.8)
	# A clean 48 uT field out of the top of the phone: north.
	h.step(Vector3(0.0, 48.0, 0.0), flat_grav)
	check(h.live(), "one good sample and it is live")
	check(h.seen(), "and has been seen")
	check(is_equal_approx(h.heading_deg(), 0.0), "the first sample is taken whole, not smoothed toward from 0")
	check(h.accuracy() == GeoScript.ACC_MEDIUM, "one sample cannot claim steadiness: MEDIUM")
	check(h.trusted(), "which is enough to turn the picture by")
	check(h.pose() == GeoScript.POSE_FLAT, "lying flat")
	for i in range(20):
		h.step(Vector3(0.0, 48.0, 0.0), flat_grav)
	check(h.accuracy() == GeoScript.ACC_HIGH, "a quiet clean field settles to HIGH")
	# Turn the phone to face east and the heading walks there rather than jumping.
	h.step(Vector3(-48.0, 0.0, 0.0), flat_grav)
	check(h.heading_deg() > 0.0 and h.heading_deg() < 90.0, "a turn is smoothed, not snapped")
	for i in range(60):
		h.step(Vector3(-48.0, 0.0, 0.0), flat_grav)
	check(absf(GeoScript.heading_delta(h.heading_deg(), 90.0)) < 1.0, "and arrives at east")
	# A speaker magnet. Not broken -- uncalibrated, and the caller must be told.
	for i in range(20):
		h.step(Vector3(-400.0, 0.0, 0.0), flat_grav)
	check(h.accuracy() == GeoScript.ACC_UNRELIABLE, "400 uT is UNRELIABLE")
	check(not h.trusted(), "so the picture may not be turned by it")
	check(h.live(), "but it is still live -- a bad field is a state, not a silence")
	# Stand the phone up and the pose follows.
	h.step(Vector3(0.0, 0.0, -48.0), Vector3(0.0, -9.8, 0.0))
	check(h.pose() == GeoScript.POSE_UPRIGHT, "on end, the upright convention takes over")
	h.free()


func _test_declination() -> void:
	print("\n- the declination seam, which a nav add-on will use")
	var h: Node = HeadingScript.new()
	h.step(Vector3(0.0, 48.0, 0.0), Vector3(0.0, 0.0, -9.8))
	check(not h.true_north(), "magnetic north until somebody computes a declination")
	h.set_declination(4.0)
	check(h.true_north(), "a declination makes it true north")
	check(is_equal_approx(h.heading_deg(), 4.0), "and the number moves by exactly that much")
	check(is_equal_approx(h.heading_magnetic(), 0.0), "the raw magnetic azimuth is kept untouched")
	check(is_equal_approx(h.declination(), 4.0), "and the declination is readable")
	h.set_declination(NAN)
	check(is_equal_approx(h.declination(), 4.0), "NaN is refused, not believed")
	h.set_declination(400.0)
	check(is_equal_approx(h.declination(), 4.0), "and so is a declination no planet has")
	h.clear_declination()
	check(not h.true_north(), "detaching the add-on hands north back to the magnet")
	check(is_equal_approx(h.heading_deg(), 0.0), "and the number with it")
	h.free()


func _test_fix_seam() -> void:
	print("\n- the fix seam, which base never uses")
	var h: Node = HeadingScript.new()
	h.set_fix(52.52, 13.405, 8.0)
	var f: Dictionary = h.fix()
	check(GeoScript.is_fix(f), "a handed-in fix is a fix")
	check(h.has_fix(), "and an 8 m one can place somebody")
	check(is_equal_approx(float(f["lat"]), 52.52), "latitude survives the round trip")
	h.set_fix(999.0, 0.0, 5.0)
	check(is_equal_approx(float(h.fix()["lat"]), 52.52), "an impossible latitude is ignored, not stored")
	h.set_fix(0.0, 0.0, 3000.0)
	check(not h.has_fix(), "a 3 km fix is a real position that cannot place anyone")
	h.free()


func _test_quiet() -> void:
	print("\n- a compass that goes silent")
	var h: Node = HeadingScript.new()
	h.step(Vector3(0.0, 48.0, 0.0), Vector3(0.0, 0.0, -9.8))
	check(h.live(), "live while samples arrive")
	for i in range(HeadingScript.QUIET_FRAMES + 2):
		h.step(Vector3.ZERO, Vector3.ZERO)
	check(not h.live(), "and quiet after long enough silence")
	check(h.seen(), "but it HAS been seen -- that is the caption the radar draws")
	check(is_equal_approx(h.heading_deg(), 0.0), "the last heading stands; nothing snaps back")
	h.free()
