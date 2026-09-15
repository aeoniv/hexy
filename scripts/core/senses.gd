class_name HexySenses
extends Node

## W8d -- THE BASE ORGANS, AS SENSE SOURCES ON THE BUS.
##
## One node that owns every door base itself may open: the engine's own
## sensors (light, IMU, touch/tap) and the aar doors where a singleton
## exists (IxBody, IxLens, IxLoc, IxVoice), reached the way `scripts/seam.gd`
## already reaches ixmnn -- `Engine.has_singleton`, never a bare cast. Every
## reader here is gated by `scripts/core/consents.gd`: a consent that is off
## opens nothing and publishes nothing, on this frame or any other.
##
## EACH READER PUBLISHES A HexyMsg Sense ON THE ONE TOPIC, organ by organ:
## lux -> ocelli, imu -> halteres, touch -> tarsi, camera/ARCore ->
## compound_eye, mic/GPS/baro -> antenna. Nothing here decides what the brain
## does with a Sense; this file only reads a door and writes a message.
##
## NO TIMER HEURISTICS BEYOND SAMPLE RATE. A reader either has a fresh sample
## (a signal fired, or Input answered a non-zero vector) or it has nothing to
## say this tick; there is no debounce, no smoothing and no invented value
## living in this file.

const REQUIRES_IXBODY := "ixbody/2"
const REQUIRES_IXLENS := "ixlens/2"
const REQUIRES_IXLOC := "ixloc/1"
const REQUIRES_IXVOICE := "ixvoice/2"

## organ -> the consent key that must be on before that organ may publish.
## Base engine readers (lux, imu, touch) are gated under BODY -- the same
## switch the eye/nav/voice add-ons gated their own ambient reads under --
## so one person's "no" covers every ambient sensor base itself can open, not
## only the camera. compound_eye (posture/AR) and antenna/words (mic) use the
## sharper VISION and VOICE consents because a lens or a microphone is a
## different promise than an accelerometer.
const CONSENT_OF := {
	"lux": Consents.BODY,
	"imu": Consents.BODY,
	"touch": Consents.BODY,
	"camera": Consents.VISION,
	"gaze": Consents.VISION,
	"place": Consents.BODY,
	"voice": Consents.VOICE,
}

var topic: HexyTopic = null

## W10a -- THE BROKER, WHEN ONE IS WIRED. A camera or a microphone is a
## CONTENDED door: an add-on may want the same lens this organ is reading, and
## only one of the two may have it. Every read of IxBody/IxLens (the camera)
## and IxVoice (the mic) goes through `broker.acquire(door, who)` FIRST and is
## abandoned, silently and completely, when the door is already held. With no
## broker bound (every unit test that does not care) the doors are open.
var broker: Node = null

## WHO THIS FILE ASKS AS. Two names, one per physical door: the eye holds the
## camera, the antenna holds the mic. They are organ names rather than the
## four-law table's `look`/`ear` because this is the W8d flat door table --
## an add-on's `"wifi"` and an organ's `"camera"` live in the same namespace
## and the holder is whoever asked first.
const HOLDER_EYE := "compound_eye"
const HOLDER_ANTENNA := "antenna"

## door -> the holder name that door is acquired under. Doors absent from this
## table (lux, imu, touch, place) are base's own sensors: nothing else on the
## phone can be reading them instead, so nothing is acquired for them.
const BROKER_DOOR_OF := {
	"camera": HOLDER_EYE,
	"gaze": HOLDER_EYE,
	"voice": HOLDER_ANTENNA,
}
## The broker's own name for each of those doors. Two organ doors ("camera"
## and "gaze") are the SAME lens, so both map onto the one broker door.
const BROKER_NAME_OF := {
	"camera": "camera",
	"gaze": "camera",
	"voice": "mic",
}

## -- poll rates, in nanoseconds ---------------------------------------------
## The imu rides the app's tick (whatever that is); everything else has its
## own floor. A reader whose interval has not elapsed is not called at all --
## there is no smoothing and no catch-up, only "not yet".
const LUX_EVERY_NS: int = 1_000_000_000      # ocelli: once a second
const AAR_EVERY_NS: int = 500_000_000        # the aar doors: twice a second

var _last_lux_ns: int = 0
var _last_aar_ns: int = 0
## Every broker door this file currently holds, so consent going off or the
## node leaving the tree gives back exactly what it took.
var _open_doors: Dictionary = {}  # broker door name -> holder name

## Mocks, so a headless test can drive every reader with no device and no
## plugin anywhere near it. A mock is only ever consulted when the matching
## `Engine.has_singleton` says there is no real one to ask instead.
var lux_mock: Variant = null
var imu_mock: Variant = null
var touch_mock: Variant = null
var ixbody_mock: Variant = null
var ixlens_mock: Variant = null
var ixloc_mock: Variant = null
var ixvoice_mock: Variant = null

var _ixbody: Object = null
var _ixlens: Object = null
var _ixloc: Object = null
var _ixvoice: Object = null
var _seam: Script = null


func _init() -> void:
	_seam = load("res://scripts/seam.gd") as Script


func bind(p_topic: HexyTopic, p_broker: Node = null) -> void:
	topic = p_topic
	broker = p_broker


## -- the broker's doors ------------------------------------------------------

## OPEN A CONTENDED DOOR, or find out somebody else has it. True when this
## organ may read `door` right now: either the door is uncontended (not in
## BROKER_DOOR_OF), or no broker is wired, or the broker says it is ours.
func open_door(door: String) -> bool:
	var who: String = String(BROKER_DOOR_OF.get(door, ""))
	if who == "":
		return true
	if broker == null:
		return true
	var name: String = String(BROKER_NAME_OF.get(door, door))
	if not bool(broker.call("acquire", name, who)):
		return false
	_open_doors[name] = who
	return true


## GIVE ONE DOOR BACK. Silently nothing for a door this file never took.
func close_door(door: String) -> void:
	var name: String = String(BROKER_NAME_OF.get(door, door))
	var who: String = String(_open_doors.get(name, ""))
	if who == "" or broker == null:
		_open_doors.erase(name)
		return
	broker.call("release_door", name, who)
	_open_doors.erase(name)


## EVERYTHING THIS FILE HAS. Called when consent is withdrawn wholesale and on
## the way out of the tree.
func close_all_doors() -> void:
	for name in _open_doors.keys().duplicate():
		if broker != null:
			broker.call("release_door", name, String(_open_doors[name]))
		_open_doors.erase(name)


func _exit_tree() -> void:
	close_all_doors()


## -- the poll ----------------------------------------------------------------

## ONE POLL, ON THE HOST'S TICK. Each door answers at its OWN rate: the imu
## every tick (it is the giant fiber's input and the cheapest read there is),
## lux once a second, the aar doors twice a second. Touch is not here -- a tap
## is an event, and `sample_touch` is called from the host's input path when
## one happens, never guessed at on a clock.
##
## A door whose consent is off is not read AND its broker hold is given back,
## so a person switching a consent off frees the device rather than merely
## silencing the messages about it.
##
## Returns how many Senses were published this poll, so a caller (or a test)
## can see the organ answered without subscribing to anything.
func poll(t_ns: int) -> int:
	var published: int = 0

	## -- halteres: every tick. Base's own accelerometer; no door to take.
	if consented("imu"):
		if sample_imu(t_ns):
			published += 1

	## -- ocelli: once a second, and only when something really answers.
	if t_ns - _last_lux_ns >= LUX_EVERY_NS:
		_last_lux_ns = t_ns
		if consented("lux"):
			var lux: float = _read_lux()
			if lux >= 0.0 and sample_lux(t_ns, lux):
				published += 1

	## -- the aar doors: twice a second, each behind its own consent and,
	## where the device is contended, behind the broker.
	if t_ns - _last_aar_ns >= AAR_EVERY_NS:
		_last_aar_ns = t_ns
		if consented("camera") and open_door("camera"):
			if poll_ixbody(t_ns):
				published += 1
		else:
			close_door("camera")
		if consented("place"):
			if poll_ixloc(t_ns):
				published += 1
		if consented("voice") and open_door("voice"):
			if poll_ixvoice(t_ns):
				published += 1
		else:
			close_door("voice")
	return published


## THE ONE AMBIENT LIGHT READER BASE HAS. `lux_mock` first (a headless test
## hands one in), then ixmnn's own sensor where the aar is on the device.
## A negative answer means "nothing said anything", and nothing is published.
func _read_lux() -> float:
	if lux_mock != null and typeof(lux_mock) in [TYPE_INT, TYPE_FLOAT]:
		return float(lux_mock)
	if _seam == null:
		return -1.0
	var mnn: Object = _seam.call("ixmnn")
	## NO has_method GATE. `Seam.ixmnn()` has already version-checked the aar,
	## and a JNISingleton answers `has_method` false for every method it owns
	## -- the same trap sensor_oracle._sample_hardware_extensions documents.
	if mnn == null:
		return -1.0
	return float(mnn.call("get_ambient_lux"))


## -- consent -----------------------------------------------------------------

## `door` is the CONSENT_OF key ("lux", "imu", "touch", "camera", "gaze",
## "place", "voice") -- NOT the organ name. Several doors share one organ
## (gaze and place both land on "antenna"), and each has its own promise.
func consented(door: String) -> bool:
	var key: String = String(CONSENT_OF.get(door, ""))
	if key == "":
		return true
	return Consents.resolve(key, false)


## -- the handshake, one per aar, reused from scripts/seam.gd's own pattern --

func _singleton(name: String, needs: String, tag: String, mock: Variant) -> Object:
	if mock != null:
		return mock
	if not Engine.has_singleton(name):
		return null
	var node: Object = Engine.get_singleton(name)
	if _seam != null and not bool(_seam.call("check", node, needs, tag)):
		return null
	return node


func _ixbody_node() -> Object:
	return _singleton("IxBody", REQUIRES_IXBODY, "hexy_senses.body", ixbody_mock)


func _ixlens_node() -> Object:
	return _singleton("IxLens", REQUIRES_IXLENS, "hexy_senses.lens", ixlens_mock)


func _ixloc_node() -> Object:
	return _singleton("IxLoc", REQUIRES_IXLOC, "hexy_senses.loc", ixloc_mock)


func _ixvoice_node() -> Object:
	return _singleton("IxVoice", REQUIRES_IXVOICE, "hexy_senses.voice", ixvoice_mock)


## -- publishing ---------------------------------------------------------------

func _publish(organ: String, door: String, t_ns: int, value, meta: Dictionary = {}) -> bool:
	if topic == null:
		return false
	if not consented(door):
		return false
	return topic.publish(HexyTopic.TOPIC_SENSE, HexyMsg.sense(organ, door, t_ns, value, meta))


## -- ocelli: lux --------------------------------------------------------------

## `lux_mock`, if set, is a float the test hands in directly; otherwise this
## reads whatever `scripts/senses/machine/light.gd`-style telemetry the host
## already gathers. Base carries no ambient light sensor of its own on
## desktop, so a caller wanting a real reading hands one in via `sample_lux`.
func sample_lux(t_ns: int, lux: float) -> bool:
	return _publish("ocelli", "lux", t_ns, lux, {})


## -- halteres: IMU accel/gyro --------------------------------------------------

func sample_imu(t_ns: int, accel: Vector3 = Vector3.ZERO, gyro: Vector3 = Vector3.ZERO) -> bool:
	if imu_mock is Dictionary:
		accel = (imu_mock as Dictionary).get("accel", accel)
		gyro = (imu_mock as Dictionary).get("gyro", gyro)
	elif accel == Vector3.ZERO and gyro == Vector3.ZERO:
		accel = Input.get_accelerometer()
		gyro = Input.get_gyroscope()
	## `value` matches what FlyBrain.route_sense reads for "halteres": accel
	## (the giant fiber's raw acceleration) and gyro_yaw_rate (the central
	## complex's turn rate) live on the value itself, not buried in meta.
	return _publish("halteres", "imu", t_ns,
		{"accel": accel, "gyro_yaw_rate": gyro.y}, {"gyro": gyro})


## -- tarsi: touch/tap ----------------------------------------------------------

func sample_touch(t_ns: int, line: int, amount: float) -> bool:
	return _publish("tarsi", "touch", t_ns, {"line": line, "amount": amount}, {})


## -- compound_eye: camera / posture (ixbody) or ARCore -------------------------

## PORTED FROM addons/hexy_eye's own measurement: a 0..1 upright/slumped
## reading, published as a compound_eye Sense rather than nudged straight
## into Alchemy -- the brain, not this file, decides what a posture means.
func sample_posture(t_ns: int, upright: float) -> bool:
	return _publish("compound_eye", "camera", t_ns, clampf(upright, 0.0, 1.0), {})


func poll_ixbody(t_ns: int) -> bool:
	var node: Object = _ixbody_node()
	if node == null or not node.has_method("last_posture"):
		return false
	var v: Variant = node.call("last_posture")
	if v == null:
		return false
	return sample_posture(t_ns, float(v))


## -- antenna: gaze (ixlens), place/solar (ixloc), voice (ixvoice), mic/GPS/baro --

## PORTED FROM addons/hexy_lens: a gaze direction/dwell reading.
func sample_gaze(t_ns: int, dwell: float) -> bool:
	return _publish("antenna", "gaze", t_ns, clampf(dwell, 0.0, 1.0), {})


## PORTED FROM addons/hexy_nav: the solar/place reading, with sunrise carried
## in `meta` for the gauge to fit its clock against (see HexyGauge.fit).
func sample_place(t_ns: int, lat: float, lon: float, sunrise_h: float) -> bool:
	return _publish("antenna", "place", t_ns, {"lat": lat, "lon": lon},
		{"sunrise_h": sunrise_h})


## PORTED FROM addons/hexy_voice: a spoken utterance reaches the mushroom
## body as an antenna/words Sense, matching HexyMsg.SENSE_ORGANS' "words".
func sample_voice(t_ns: int, text: String) -> bool:
	if not consented("voice"):
		return false
	if topic == null:
		return false
	return topic.publish(HexyTopic.TOPIC_SENSE,
		HexyMsg.sense("words", "voice", t_ns, text, {}))


func poll_ixloc(t_ns: int) -> bool:
	var node: Object = _ixloc_node()
	if node == null or not node.has_method("last_fix"):
		return false
	var fix: Variant = node.call("last_fix")
	if not (fix is Dictionary):
		return false
	var d: Dictionary = fix
	return sample_place(t_ns, float(d.get("lat", 0.0)), float(d.get("lon", 0.0)),
		float(d.get("sunrise_h", 6.0)))


func poll_ixvoice(t_ns: int) -> bool:
	var node: Object = _ixvoice_node()
	if node == null or not node.has_method("last_utterance"):
		return false
	var text: Variant = node.call("last_utterance")
	if text == null or String(text) == "":
		return false
	return sample_voice(t_ns, String(text))
