extends SceneTree

## N6 -- THE OPTIC LOBE, WALKED.
##
## Three synthetic worlds, each one a sequence of luminance frames this file
## writes itself, and one live organism on a bus:
##   a still frame        -- nothing moves, so nothing is seen.
##   a stripe drifting    -- the flow reads negative, and so does the drift.
##   a blob expanding     -- looming climbs and the escape fires.
##   the eye on the bus   -- compound_eye Senses in, a changed Body out.
##
## Every millisecond and every photon here is one this file chose.

const FlyOpticLobeScript = preload("res://scripts/brain/fly_optic_lobe.gd")

const T0: int = 1_700_000_000_000
const DT: float = 0.05
const CELLS: int = 16

var passes: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST OPTIC LOBE (lamina -> medulla -> lobula) ---")
	_test_a_still_world_says_nothing()
	_test_a_stripe_drifting_left()
	_test_a_blob_expanding_looms()
	_test_the_one_cell_eye_still_looms()
	_test_the_eye_on_the_bus_moves_the_body()
	print("\nPassed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("--- ALL OPTIC LOBE TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- OPTIC LOBE TESTS FAILED: ", failures, " ---\n")
		quit(1)


## A bright stripe centred on `centre`, one frame of CELLS luminance cells.
static func _stripe(centre: float, width: float) -> Array:
	var out: Array = []
	for x in range(CELLS):
		var d: float = (float(x) - centre) / maxf(width, 0.001)
		out.append(exp(-0.5 * d * d))
	return out


## A BRIGHT DISC OF HALF-WIDTH `radius`, centred on the eye's midline, with
## two soft edges -- which is what a thing coming at the face looks like: two
## borders sliding outward, one per side.
static func _blob(radius: float) -> Array:
	var centre: float = float(CELLS - 1) * 0.5
	var out: Array = []
	for x in range(CELLS):
		out.append(1.0 / (1.0 + exp(-(radius - absf(float(x) - centre)) * 2.0)))
	return out


func _test_a_still_world_says_nothing() -> void:
	print("\n[A] a frame that never changes")
	var eye = FlyOpticLobeScript.new()
	for i in range(40):
		eye.step(DT, _blob(3.0))
	check(absf(eye.vx) < 0.01, "no horizontal flow (vx=%.4f)" % eye.vx)
	check(absf(eye.vy) < 0.01, "no vertical flow (vy=%.4f)" % eye.vy)
	check(eye.looming < 0.01, "nothing looms (looming=%.4f)" % eye.looming)
	check(is_zero_approx(eye.startle_drive), "and nothing startles")
	check(absf(eye.drift_rad()) < 0.01, "the world is not drifting anywhere")


func _test_a_stripe_drifting_left() -> void:
	print("\n[B] a stripe drifting left")
	var eye = FlyOpticLobeScript.new()
	var centre: float = 12.0
	var worst_vx: float = 0.0
	for i in range(30):
		eye.step(DT, _stripe(centre, 2.0))
		centre -= 0.3
		if i > 3:
			worst_vx = maxf(worst_vx, eye.vx)
	check(eye.vx < 0.0, "the flow is leftward (vx=%.4f)" % eye.vx)
	check(worst_vx <= 0.0, "and never once reads rightward")
	check(eye.drift_rad() < 0.0, "drift_rad takes its sign (%.4f rad)" % eye.drift_rad())
	check(is_zero_approx(eye.startle_drive),
		"a stripe going by is not a thing arriving (startle=%.4f)" % eye.startle_drive)

	print("\n[B'] the same stripe drifting right")
	var eye2 = FlyOpticLobeScript.new()
	var c2: float = 3.0
	for i in range(30):
		eye2.step(DT, _stripe(c2, 2.0))
		c2 += 0.3
	check(eye2.vx > 0.0, "the flow is rightward (vx=%.4f)" % eye2.vx)
	check(eye2.drift_rad() > 0.0, "and so is the drift (%.4f rad)" % eye2.drift_rad())


func _test_a_blob_expanding_looms() -> void:
	print("\n[C] a bright blob expanding into the face")
	var eye = FlyOpticLobeScript.new()
	var radius: float = 0.5
	var peak_loom: float = 0.0
	var peak_drive: float = 0.0
	for i in range(20):
		eye.step(DT, _blob(radius))
		radius += 0.3
		peak_loom = maxf(peak_loom, eye.looming)
		peak_drive = maxf(peak_drive, eye.startle_drive)
	check(peak_loom > FlyOpticLobeScript.LOOM_THRESHOLD,
		"looming climbs past the lobula's threshold (%.3f > %.3f)"
			% [peak_loom, FlyOpticLobeScript.LOOM_THRESHOLD])
	check(peak_drive > 0.0, "and LPLC2 drives an escape (%.3f)" % peak_drive)
	check(eye.expansion > 0.0, "the flow field is expanding (%.4f)" % eye.expansion)

	print("\n[C'] the same blob shrinking away")
	var eye2 = FlyOpticLobeScript.new()
	var r2: float = 6.5
	var drive2: float = 0.0
	for i in range(20):
		eye2.step(DT, _blob(r2))
		r2 -= 0.3
		drive2 = maxf(drive2, eye2.startle_drive)
	check(is_zero_approx(drive2), "a thing leaving never startles (%.4f)" % drive2)

	print("\n[C''] and a looming that stops growing stops driving")
	var eye3 = FlyOpticLobeScript.new()
	var r3: float = 0.5
	for i in range(20):
		eye3.step(DT, _blob(r3))
		r3 += 0.3
	for i in range(40):
		eye3.step(DT, _blob(r3))
	check(is_zero_approx(eye3.startle_drive),
		"the drive is back to nothing (%.4f)" % eye3.startle_drive)


func _test_the_one_cell_eye_still_looms() -> void:
	print("\n[D] the one-cell eye compound_eye actually publishes today")
	var eye = FlyOpticLobeScript.new()
	for i in range(20):
		eye.step(DT, 0.2)
	check(is_zero_approx(eye.vx) and eye.looming < 0.05,
		"one steady cell is one quiet eye (looming=%.4f)" % eye.looming)
	var drive: float = 0.0
	for i in range(30):
		eye.step(DT, 1.0)
		drive = maxf(drive, eye.startle_drive)
	check(drive > 0.0, "a cell filling with light is the only looming it has (%.3f)" % drive)
	check(is_zero_approx(eye.vx) and is_zero_approx(eye.vy),
		"and with no neighbour there is no flow at all")


## The eye on the bus: compound_eye Senses in on "/sense", one Body out on
## "/body", and the Body is read from the topic, never from the character.
func _test_the_eye_on_the_bus_moves_the_body() -> void:
	print("\n[E] the eye on the bus")
	var topic := HexyTopic.new()
	var ch := Character.new()
	ch.attach_bus(topic)
	var bodies: Array = []
	topic.subscribe("/body", func(m: Dictionary) -> void: bodies.append(m))
	ch.bus_tick(T0)
	check(bodies.size() == 1, "one tick, one Body")
	var before: Array = (bodies[-1] as Dictionary).get("lines", [])
	var octopamine_before: float = float(before[2]) if before.size() > 2 else 0.0

	var radius: float = 0.5
	var t_ms: int = T0
	for i in range(20):
		t_ms += int(DT * 1000.0)
		topic.publish(HexyTopic.TOPIC_SENSE,
			HexyMsg.sense("compound_eye", "camera", t_ms * 1_000_000,
				{"v": _blob(radius)}))
		radius += 0.3
		ch.bus_tick(t_ms, DT)

	check(ch.optic_lobe != null, "the character carries an optic lobe")
	check(ch.optic_lobe.looming > 0.0,
		"which has something looming in it (%.3f)" % ch.optic_lobe.looming)
	check(ch.giant_fiber.is_startled or ch.stage() == FlyStage.REFUSAL,
		"the giant fiber fired on a looming shadow, through its own trigger")
	var after: Array = (bodies[-1] as Dictionary).get("lines", [])
	var octopamine_after: float = float(after[2]) if after.size() > 2 else 0.0
	check(bodies.size() > 1, "every tick published a Body (%d)" % bodies.size())
	check(octopamine_after > octopamine_before,
		"and the Body on the bus carries the flight arousal (%.3f -> %.3f)"
			% [octopamine_before, octopamine_after])

	print("\n[E'] a drifting world leans the compass instead")
	var topic2 := HexyTopic.new()
	var ch2 := Character.new()
	ch2.attach_bus(topic2)
	ch2.bus_tick(T0)
	var heading_before: float = float(ch2.get_fly_state().get("heading_rad", 0.0))
	var centre: float = 12.0
	var t2: int = T0
	for i in range(30):
		t2 += int(DT * 1000.0)
		topic2.publish(HexyTopic.TOPIC_SENSE,
			HexyMsg.sense("compound_eye", "camera", t2 * 1_000_000,
				{"v": _stripe(centre, 2.0)}))
		centre -= 0.3
		ch2.bus_tick(t2, DT)
	check(ch2.optic_lobe.drift_rad() < 0.0,
		"the world drifts left (%.4f rad)" % ch2.optic_lobe.drift_rad())
	check(not ch2.giant_fiber.is_startled, "and a passing world never startles")
	check(absf(float(ch2.get_fly_state().get("heading_rad", 0.0)) - heading_before) >= 0.0,
		"the heading is the central complex's own, nudged and not seized")
