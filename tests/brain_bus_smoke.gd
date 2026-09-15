extends SceneTree

## W8c -- FFBRAIN ON THE BUS.
##
## One topic, one organism, and nothing else in the room. Senses go in as
## HexyMsg Sense messages; one Body and one Phase come out; the store's figure
## follows the Body because that is now the only way it moves.
##
## Time is driven from here -- every stamp is a millisecond this file chose --
## so nothing in this file waits for a clock.

const HexyStoreScript = preload("res://scripts/core/store.gd")

const T0: int = 1_700_000_000_000

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
	print("\n--- TEST BRAIN BUS (senses in, one body out) ---")
	_test_a_lux_sense_reaches_the_clock()
	_test_a_touch_moves_a_line()
	_test_the_body_and_the_phase_come_out()
	_test_a_bogus_organ_is_ignored()
	_test_the_store_follows_the_body()
	print("\nPassed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("--- ALL BRAIN BUS TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- BRAIN BUS TESTS FAILED: ", failures, " ---\n")
		quit(1)


## A bus with an organism on it, and nothing else.
func _rig() -> Array:
	var topic := HexyTopic.new()
	var ch := Character.new()
	ch.attach_bus(topic)
	return [topic, ch]


static func _lux(lux: float, t_ms: int) -> Dictionary:
	return HexyMsg.sense("ocelli", "lux", t_ms * 1_000_000, {"lux": lux})


static func _touch(line: int, amount: float, t_ms: int) -> Dictionary:
	return HexyMsg.sense("tarsi", "touch", t_ms * 1_000_000,
		{"line": line, "amount": amount})


func _test_a_lux_sense_reaches_the_clock() -> void:
	print("\n[ the ocelli measure light, and the clock stops guessing ]")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	var clock: RefCounted = ch.circadian_clock
	check(not clock.has_light(), "a clock nobody has told about the light says so")
	check(topic.publish("/sense", _lux(12000.0, T0)), "a lux Sense is a valid message")
	check(clock.has_light(), "and the ocelli have now reported")
	var bright: float = clock.light_drive
	check(bright > 0.5, "broad daylight reads high on the eye's own scale (%.3f)" % bright)
	var lit_pdf: float = clock.pdf_level
	topic.publish("/sense", _lux(0.05, T0 + 1000))
	check(clock.light_drive < 0.05, "and a dark room reads near zero (%.3f)" % clock.light_drive)
	check(clock.pdf_level < lit_pdf, "arousal falls with the light, on the same hour")
	check(absf(clock.solar_hour - 12.0) < 1e-6, "the hour itself was never touched")
	ch.detach_bus()


func _test_a_touch_moves_a_line() -> void:
	print("\n[ the tarsi are how a line fill is written, and the only how ]")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	ch.tick(T0)
	var before: float = ch.get_fullness(Character.LINE_FOOD)
	check(topic.publish("/sense", _touch(Character.LINE_FOOD, 0.3, T0 + 1000)),
		"a touch Sense is a valid message")
	var after: float = ch.get_fullness(Character.LINE_FOOD)
	check(after > before, "the food line filled (%.3f -> %.3f)" % [before, after])
	## Signed: a touch may drain a line as well as pour into one.
	topic.publish("/sense", _touch(Character.LINE_FOOD, -0.2, T0 + 2000))
	check(ch.get_fullness(Character.LINE_FOOD) < after, "and a negative touch drains it")
	## The connection line is not a line a hand may open.
	var conn: float = ch.get_fullness(Character.LINE_CONNECTION)
	topic.publish("/sense", _touch(Character.LINE_CONNECTION, 0.4, T0 + 3000))
	check(is_equal_approx(ch.get_fullness(Character.LINE_CONNECTION), conn)
		or ch.get_fullness(Character.LINE_CONNECTION) <= conn,
		"a bare touch cannot talk the connection line open")
	## A conspecific can, because a conspecific is the attested source.
	topic.publish("/sense", HexyMsg.sense("pheromone", "peer", (T0 + 4000) * 1_000_000,
		{"strength": 1.0, "solar_hour": 18.0}))
	check(ch.get_fullness(Character.LINE_CONNECTION) > conn,
		"but another body reaching for it does")
	ch.detach_bus()


func _test_the_body_and_the_phase_come_out() -> void:
	print("\n[ one Body and one Phase, every tick ]")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	ch.tick(T0)
	check(topic.last("/body").is_empty(), "nothing on /body before a tick")
	ch.bus_tick(T0 + 1000, 1.0)
	var b: Dictionary = topic.last("/body")
	check(not b.is_empty(), "a Body arrived on /body")
	check(HexyMsg.validate(b), "and it is a valid Body message")
	var lines0: Array = (b.get("lines", []) as Array).duplicate()
	check(lines0.size() == 6, "six line fills")
	check(int(b.get("bits", -1)) == ch.lines(),
		"and the bits are the threshold readout of those fills, nothing else")

	## A touch, then a tick: the lines the Body carries have moved.
	topic.publish("/sense", _touch(Character.LINE_BREATH, 0.4, T0 + 2000))
	ch.bus_tick(T0 + 3000, 1.0)
	var b2: Dictionary = topic.last("/body")
	check(float(b2["lines"][Character.LINE_BREATH]) > float(lines0[Character.LINE_BREATH]),
		"the second Body carries the line the touch moved (%.3f -> %.3f)" % [
			float(lines0[Character.LINE_BREATH]), float(b2["lines"][Character.LINE_BREATH])])
	check(b2.has("heading_rad") and b2.has("activity") and b2.has("glow"),
		"and the whole one body shape, not a slice of it")
	check((b2["activity"] as Array).size() == 8, "eight wedges of calcium")

	var p: Dictionary = topic.last("/phase")
	check(not p.is_empty(), "a Phase arrived on /phase")
	check(HexyMsg.validate(p), "and it is a valid Phase message")
	check(float(p["day"]) >= 0.0 and float(p["day"]) <= 1.0, "the day is a fraction of one")
	check(is_equal_approx(float(p["weeks"]), 0.0) and String(p["life"]) == "",
		"weeks and life are left for the gauge to fill, not invented here")
	ch.detach_bus()


func _test_a_bogus_organ_is_ignored() -> void:
	print("\n[ an organ this body does not have ]")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	ch.tick(T0)
	var before: float = ch.get_fullness(Character.LINE_BODY)
	var bogus: Dictionary = {
		"kind": "sense", "organ": "gizzard", "door": "nonsense",
		"t_ns": T0 * 1_000_000, "value": 1.0, "meta": {},
	}
	check(not topic.publish("/sense", bogus), "the bus refuses an unknown organ outright")
	check(ch.route_sense(bogus) == "", "and the brain takes nothing from one handed to it directly")
	check(ch.route_sense({"kind": "body", "bits": 63}) == "", "nor from a message of the wrong kind")
	check(is_equal_approx(ch.get_fullness(Character.LINE_BODY), before),
		"no line moved on either")
	check(ch.route_sense(_lux(300.0, T0)) == "ocelli", "a real organ still answers by name")
	ch.detach_bus()


func _test_the_store_follows_the_body() -> void:
	print("\n[ the store's figure is the Body it was handed ]")
	var topic := HexyTopic.new()
	var store: HexyStore = HexyStoreScript.new()
	var ch: RefCounted = store.get_character()
	ch.attach_bus(topic)
	store.attach_bus(topic)
	ch.tick(T0)
	## Five lines start full, the connection line empty: 0b011111.
	ch.bus_tick(T0 + 1000, 1.0)
	check(store.body_bits() == ch.lines(),
		"the store stands on the readout of the six fills (%d)" % store.body_bits())
	var was: int = store.body_bits()
	## Drain the food line under the threshold and the figure must follow.
	topic.publish("/sense", _touch(Character.LINE_FOOD, -0.5, T0 + 2000))
	topic.publish("/sense", _touch(Character.LINE_FOOD, -0.5, T0 + 2500))
	ch.bus_tick(T0 + 3000, 1.0)
	check(store.body_bits() != was, "a need that fell closed turned the line (%d -> %d)" % [
		was, store.body_bits()])
	check((store.body_bits() >> Character.LINE_FOOD) & 1 == 0, "and it is the food line that is yin")
	check(store.body_path().size() >= 2, "the walk remembers both figures")
	ch.detach_bus()
	store.detach_bus()
