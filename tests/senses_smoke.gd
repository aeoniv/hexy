extends SceneTree

## W8d -- THE BASE ORGAN READERS, ON MOCKS.
##
## Each organ reader on HexySenses publishes a valid HexyMsg Sense, on the
## right organ, when consent is on -- and publishes nothing at all when it
## is off. No device, no plugin: every reader here is driven by hand.

const T0: int = 1_700_000_000_000_000_000

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST SENSES SMOKE (base organ readers) ---")
	_run()
	if failures == 0:
		print("--- ALL SENSES SMOKE TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- SENSES SMOKE TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	Consents.set_path("user://test_senses_consents.json")
	Consents.clear()

	var topic := HexyTopic.new()
	var senses := HexySenses.new()
	senses.bind(topic)

	# -- consent OFF: nothing published, for every gated organ -----------------
	print("\n[ no consent, no Sense ]")
	check(not senses.sample_lux(T0, 400.0), "lux refused with no body consent")
	check(not senses.sample_imu(T0, Vector3(1, 0, 0)), "imu refused with no body consent")
	check(not senses.sample_posture(T0, 0.8), "posture refused with no vision consent")
	check(not senses.sample_gaze(T0, 0.5), "gaze refused with no vision consent")
	check(not senses.sample_place(T0, 1.0, 2.0, 6.5), "place refused with no body consent")
	check(not senses.sample_voice(T0, "hello"), "voice refused with no voice consent")
	check(topic.topics().is_empty(), "and the topic bus stayed silent (%s)" % str(topic.topics()))

	# -- consent ON: each organ reader publishes a valid, correctly-organed Sense
	Consents.remember(Consents.BODY, true)
	Consents.remember(Consents.VISION, true)
	Consents.remember(Consents.VOICE, true)

	print("\n[ consented, every organ answers ]")
	check(senses.sample_lux(T0, 500.0), "lux publishes once consented")
	var lux_msg: Dictionary = topic.last("/sense/lux")
	check(HexyMsg.validate(lux_msg) and String(lux_msg.get("organ", "")) == "ocelli",
		"lux lands as an ocelli Sense (%s)" % str(lux_msg))

	check(senses.sample_imu(T0 + 1, Vector3(2, 0, 0), Vector3.ZERO), "imu publishes")
	var imu_msg: Dictionary = topic.last("/sense/imu")
	check(HexyMsg.validate(imu_msg) and String(imu_msg.get("organ", "")) == "halteres",
		"imu lands as a halteres Sense (%s)" % str(imu_msg))

	check(senses.sample_touch(T0 + 2, 1, 0.4), "touch publishes")
	var touch_msg: Dictionary = topic.last("/sense/touch")
	check(HexyMsg.validate(touch_msg) and String(touch_msg.get("organ", "")) == "tarsi",
		"touch lands as a tarsi Sense (%s)" % str(touch_msg))

	check(senses.sample_posture(T0 + 3, 0.9), "posture publishes")
	var posture_msg: Dictionary = topic.last("/sense/camera")
	check(HexyMsg.validate(posture_msg) and String(posture_msg.get("organ", "")) == "compound_eye",
		"posture lands as a compound_eye Sense (%s)" % str(posture_msg))

	check(senses.sample_gaze(T0 + 4, 0.6), "gaze publishes")
	var gaze_msg: Dictionary = topic.last("/sense/gaze")
	check(HexyMsg.validate(gaze_msg) and String(gaze_msg.get("organ", "")) == "antenna",
		"gaze lands as an antenna Sense (%s)" % str(gaze_msg))

	check(senses.sample_place(T0 + 5, 51.5, -0.1, 6.25), "place publishes")
	var place_msg: Dictionary = topic.last("/sense/place")
	check(HexyMsg.validate(place_msg) and String(place_msg.get("organ", "")) == "antenna"
			and is_equal_approx(float(place_msg.get("meta", {}).get("sunrise_h", -1.0)), 6.25),
		"place lands as an antenna Sense with sunrise in meta (%s)" % str(place_msg))

	check(senses.sample_voice(T0 + 6, "hello there"), "voice publishes")
	var voice_msg: Dictionary = topic.last("/sense/voice")
	check(HexyMsg.validate(voice_msg) and String(voice_msg.get("organ", "")) == "words"
			and String(voice_msg.get("value", "")) == "hello there",
		"voice lands as a words Sense carrying the text (%s)" % str(voice_msg))

	# -- one consent going off stops only what it gates -------------------------
	print("\n[ one consent, switched back off ]")
	Consents.remember(Consents.VISION, false)
	check(not senses.sample_posture(T0 + 7, 0.5), "posture stops once vision consent goes off")
	check(senses.sample_lux(T0 + 8, 600.0), "but lux (body consent) still answers")

	Consents.clear()

	_test_poll_rates()
	_test_broker_doors()

	Consents.clear()
	print("\nFailures: %d" % failures)


## W10a -- THE POLL, AND ITS RATES. `poll(t_ns)` is what the app calls on its
## own tick; each door decides for itself whether enough time has passed. The
## imu is every tick because it is the giant fiber's input; lux is once a
## second because ambient light does not move faster than that.
func _test_poll_rates() -> void:
	print("\n[ poll: each door at its own rate ]")
	Consents.remember(Consents.BODY, true)
	var topic := HexyTopic.new()
	var senses := HexySenses.new()
	senses.bind(topic)
	## MOCKED READERS, so no device and no aar is anywhere near this.
	senses.imu_mock = {"accel": Vector3(0.0, -9.8, 0.0), "gyro": Vector3(0.0, 0.3, 0.0)}
	senses.lux_mock = 410.0

	var imu_seen: Array = []
	var lux_seen: Array = []
	topic.subscribe("/sense/imu", func(m): imu_seen.append(m))
	topic.subscribe("/sense/lux", func(m): lux_seen.append(m))

	## Ten ticks, a sixtieth of a second apart: well under one second in all.
	var t: int = T0
	for i in 10:
		senses.poll(t)
		t += 16_666_666
	check(imu_seen.size() == 10, "imu published on every one of ten ticks (got %d)" % imu_seen.size())
	check(lux_seen.size() == 1, "lux published once in that sixth of a second (got %d)" % lux_seen.size())
	check(imu_seen.size() > 0 and String(imu_seen[0].get("organ", "")) == "halteres",
		"and the imu arrives as a halteres Sense")
	var yaw: float = -1.0
	if imu_seen.size() > 0:
		yaw = float((imu_seen[0].get("value") as Dictionary).get("gyro_yaw_rate", -1.0))
	check(is_equal_approx(yaw, 0.3),
		"carrying the mocked yaw rate the giant fiber reads (got %.3f)" % yaw)

	## Past the one-second mark, lux answers again -- and only once more.
	senses.poll(T0 + 1_100_000_000)
	senses.poll(T0 + 1_200_000_000)
	check(lux_seen.size() == 2, "lux answers again a second later, once (got %d)" % lux_seen.size())

	## CONSENT IS STILL THE GATE, on the poll as on every hand-driven sample.
	Consents.remember(Consents.BODY, false)
	var before: int = imu_seen.size()
	senses.poll(T0 + 2_000_000_000)
	check(imu_seen.size() == before, "poll publishes nothing once body consent goes off")
	Consents.remember(Consents.BODY, true)


## W10a -- THE CONTENDED DOORS. A camera is one device: the organ asks the
## broker first, and an add-on that already holds it wins.
func _test_broker_doors() -> void:
	print("\n[ the broker stands in front of the camera and the mic ]")
	Consents.remember(Consents.VISION, true)
	Consents.remember(Consents.VOICE, true)
	var broker := Broker.new()
	broker.autosave = false
	var topic := HexyTopic.new()
	var senses := HexySenses.new()
	senses.bind(topic, broker)

	check(senses.open_door("camera"), "the eye opens a free camera door")
	check(broker.holder("camera") == "compound_eye",
		"and the broker names compound_eye as its holder (got '%s')" % broker.holder("camera"))
	senses.close_door("camera")
	check(broker.holder("camera") == "", "closing it hands the door back")

	## SOMEBODY ELSE HAS IT. The organ is refused, and takes nothing.
	check(broker.acquire("camera", "some_addon"), "an add-on takes the camera first")
	check(not senses.open_door("camera"), "the eye is then refused the camera")
	check(broker.holder("camera") == "some_addon", "and the add-on still holds it")

	## The mic is a DIFFERENT door, and is not blocked by the camera.
	check(senses.open_door("voice"), "the antenna still opens the mic")
	check(broker.holder("mic") == "antenna",
		"held under the antenna's name (got '%s')" % broker.holder("mic"))
	senses.close_all_doors()
	check(broker.holder("mic") == "", "close_all_doors gives the mic back")
	check(broker.holder("camera") == "some_addon",
		"and takes nothing that was never this file's")

	## A POLL WITH NO CONSENT GIVES THE DOOR BACK, rather than merely going
	## quiet with the device still open.
	broker.release_door("camera", "some_addon")
	check(senses.open_door("camera"), "the eye takes the camera again")
	Consents.remember(Consents.VISION, false)
	senses.poll(T0 + 9_000_000_000)
	check(broker.holder("camera") == "",
		"a poll with vision consent off releases the camera (holder '%s')" % broker.holder("camera"))
