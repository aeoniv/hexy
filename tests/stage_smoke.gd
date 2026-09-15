extends SceneTree

## N3 -- THE FIRST-PERSON STAGE, WALKED.
##
## The stage is the ORGANISM'S. It is not the journey: the journey reads the
## walk of figures through the gauge and hands a reading layer a chapter, and
## it needs the store's path, which the brain never sees. This machine is
## driven by what the brain already has -- an attested pheromone contact, the
## giant fiber's startle, a dopaminergic event, the connection line's fill --
## and it rides out on every Body as `stage`.
##
## Senses in on "/sense", one Body out on "/body", and every millisecond in
## this file is one this file chose.

const FlyStageScript = preload("res://scripts/brain/fly_stage.gd")

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
	print("\n--- TEST STAGE (the organism says where it stands) ---")
	_test_a_fresh_organism_stands_nowhere()
	_test_contact_opens_the_approach()
	_test_a_startle_refuses()
	_test_a_landed_reach_rewards()
	_test_every_stage_comes_home()
	_test_the_stage_rides_the_body()
	print("\nPassed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("--- ALL STAGE TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- STAGE TESTS FAILED: ", failures, " ---\n")
		quit(1)


## A bus with one organism on it, and nothing else in the room.
func _rig() -> Array:
	var topic := HexyTopic.new()
	var ch := Character.new()
	ch.attach_bus(topic)
	ch.bus_tick(T0)
	return [topic, ch]


static func _pheromone(strength: float, t_ms: int) -> Dictionary:
	return HexyMsg.sense("pheromone", "peer", t_ms * 1_000_000, {"strength": strength})


func _test_a_fresh_organism_stands_nowhere() -> void:
	print("\n- a fresh organism stands in no stage at all")
	var rig: Array = _rig()
	var ch: Character = rig[1]
	check(ch.stage() == "", "a brand new organism's stage is \"\"")
	ch.bus_tick(T0 + 1000)
	check(ch.stage() == "", "and beating alone never invents one")
	check(String(ch.body_msg(T0 + 1000).get("stage", "x")) == "",
		"the Body it publishes carries the same empty stage")


func _test_contact_opens_the_approach() -> void:
	print("\n- an attested contact opens the approach")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	topic.publish(HexyTopic.TOPIC_SENSE, _pheromone(0.2, T0 + 500))
	ch.bus_tick(T0 + 1000)
	check(ch.stage() == "approach", "one conspecific contact and the stage is approach")
	## And ONLY an attested one: a touch on a line is not another body.
	var rig2: Array = _rig()
	var t2: HexyTopic = rig2[0]
	var c2: Character = rig2[1]
	t2.publish(HexyTopic.TOPIC_SENSE,
		HexyMsg.sense("tarsi", "touch", (T0 + 500) * 1_000_000, {"line": 1, "amount": 0.4}))
	c2.bus_tick(T0 + 1000)
	check(c2.stage() == "", "a tarsal touch is not a conspecific and opens nothing")


func _test_a_startle_refuses() -> void:
	print("\n- a startle in the middle of an approach is a refusal")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	topic.publish(HexyTopic.TOPIC_SENSE, _pheromone(0.2, T0 + 500))
	ch.bus_tick(T0 + 1000)
	check(ch.stage() == "approach", "the approach is open")
	ch.fly_stage.note_startle()
	ch.bus_tick(T0 + 2000)
	check(ch.stage() == "refusal", "the giant fiber fires and the reach pulls back")


func _test_a_landed_reach_rewards() -> void:
	print("\n- a reach that lands is a reward")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	## Enough attested contact to carry the connection line over open.
	var t: int = T0
	for i in 12:
		t += 250
		topic.publish(HexyTopic.TOPIC_SENSE, _pheromone(1.0, t))
		ch.bus_tick(t)
		if ch.stage() == "reward":
			break
	check(ch.stage() == "reward",
		"the connection line crosses open and the stage is reward (got '%s')" % ch.stage())


func _test_every_stage_comes_home() -> void:
	print("\n- and every stage comes home to \"\"")
	var rig: Array = _rig()
	var topic: HexyTopic = rig[0]
	var ch: Character = rig[1]
	topic.publish(HexyTopic.TOPIC_SENSE, _pheromone(0.2, T0 + 500))
	ch.bus_tick(T0 + 1000)
	ch.fly_stage.note_startle()
	ch.bus_tick(T0 + 2000)
	check(ch.stage() == "refusal", "standing in refusal")
	## Long enough after the last contact, and the organism is ordinary again.
	var late: int = T0 + 2000 + FlyStageScript.HOLD_MS + 1000
	ch.bus_tick(late)
	check(ch.stage() == "", "the hold runs out and the stage is \"\" again")
	## An approach nobody ever answers gives up too.
	var rig2: Array = _rig()
	var t2: HexyTopic = rig2[0]
	var c2: Character = rig2[1]
	t2.publish(HexyTopic.TOPIC_SENSE, _pheromone(0.2, T0 + 500))
	c2.bus_tick(T0 + 1000)
	check(c2.stage() == "approach", "standing in approach")
	c2.bus_tick(T0 + 1000 + FlyStageScript.APPROACH_MS + 1000)
	check(c2.stage() == "" or c2.stage() == "reward",
		"an unanswered approach does not stand forever (got '%s')" % c2.stage())


func _test_the_stage_rides_the_body() -> void:
	print("\n- the stage rides out on the Body and nowhere else")
	var topic := HexyTopic.new()
	var ch := Character.new()
	ch.attach_bus(topic)
	ch.bus_tick(T0)
	var seen: Array[String] = []
	topic.subscribe(HexyTopic.TOPIC_BODY, func(msg: Dictionary) -> void:
		seen.append(String(msg.get("stage", "?"))))
	topic.publish(HexyTopic.TOPIC_SENSE, _pheromone(0.2, T0 + 500))
	ch.bus_tick(T0 + 1000)
	check(seen.size() >= 1, "a Body came out")
	check(seen[seen.size() - 1] == "approach",
		"and it carried the stage the organism is standing in (got '%s')"
			% seen[seen.size() - 1])
	check(HexyMsg.body(0, 0, [], 0.0, [], 0.0, "Day").get("stage", "x") == "",
		"a Body built with no stage still defaults to \"\"")
