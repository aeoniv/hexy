extends SceneTree

## W10a -- THE OUT DOORS.
##
## An Act published on "/act" reaches HexyActs and one door does one thing.
## Three rules, and they are the whole contract:
##   1. THE SPEAKER IS BORROWED, NOT KEPT. A wing song acquires the broker's
##      speaker door and gives it back in the same call.
##   2. A DOOR SOMEBODY ELSE HAS IS A REFUSAL, not a queue and not a steal.
##   3. A DOOR THAT DOES NOT EXIST IS A REFUSAL. HexyMsg.ACT_DOORS is closed.
##
## Then the app-level producer: a pheromone Sense that arrives IN PHASE is
## answered with a speaker Act, and one that is merely near is not.

const T0: int = 1_700_000_000_000_000_000

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	print("\n--- TEST ACTS SMOKE (the out doors) ---")
	_test_an_act_reaches_a_door()
	_test_the_speaker_is_borrowed()
	_test_a_bad_door_is_refused()
	await _test_the_app_producer()
	print("\nFailures: %d" % failures)
	if failures == 0:
		print("--- ALL ACTS SMOKE TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- ACTS SMOKE TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _acts(broker: Node = null) -> Array:
	var topic := HexyTopic.new()
	var acts := HexyActs.new()
	root.add_child(acts)
	acts.bind(topic, broker)
	return [topic, acts]


func _test_an_act_reaches_a_door() -> void:
	print("\n[ an Act on /act reaches HexyActs ]")
	var pair: Array = _acts()
	var topic: HexyTopic = pair[0]
	var acts: HexyActs = pair[1]

	check(topic.publish("/act", HexyMsg.act("haptic", T0, 20, {})),
		"a haptic Act is a valid message and publishes")
	check(acts.buzzes == 1, "and the haptic door buzzed once (got %d)" % acts.buzzes)
	check(acts.last_door == "haptic", "the door it took is the one it says (%s)" % acts.last_door)

	## A haptic with no duration is nothing to do, and says so.
	var before: int = acts.refused
	topic.publish("/act", HexyMsg.act("haptic", T0 + 1, 0, {}))
	check(acts.refused == before + 1, "a haptic with no duration is refused")

	## The two doors that are no-ops BY DESIGN still count as arrived.
	topic.publish("/act", HexyMsg.act("screen", T0 + 2, "anything", {}))
	topic.publish("/act", HexyMsg.act("radio", T0 + 3, "anything", {}))
	check(acts.performed >= 3, "screen and radio arrive and deliberately do nothing")
	acts.queue_free()


func _test_the_speaker_is_borrowed() -> void:
	print("\n[ the speaker is acquired, then released ]")
	var broker := Broker.new()
	broker.autosave = false
	var pair: Array = _acts(broker)
	var topic: HexyTopic = pair[0]
	var acts: HexyActs = pair[1]

	check(broker.holder("speaker") == "", "the speaker starts free")
	topic.publish("/act", HexyMsg.act("speaker", T0, 620.0, {}))
	check(acts.songs == 1, "a speaker Act sang once (got %d)" % acts.songs)
	check(broker.holder("speaker") == "",
		"and gave the door straight back (holder '%s')" % broker.holder("speaker"))

	## SOMEBODY ELSE HAS IT: refused, and nothing is played.
	check(broker.acquire("speaker", "some_addon"), "an add-on takes the speaker")
	var before: int = acts.songs
	topic.publish("/act", HexyMsg.act("speaker", T0 + 1, 620.0, {}))
	check(acts.songs == before, "the wing song is refused while the add-on holds it")
	check(broker.holder("speaker") == "some_addon", "and the add-on still holds it")
	acts.queue_free()


func _test_a_bad_door_is_refused() -> void:
	print("\n[ a door that is not one of the four ]")
	var pair: Array = _acts()
	var acts: HexyActs = pair[1]
	var before: int = acts.refused
	## Published by hand rather than through the topic: HexyMsg.validate would
	## reject the message before it ever reached a door, so the door's OWN
	## refusal is what is being checked here.
	check(not acts.perform({"kind": "act", "door": "laser", "t_ns": T0, "value": 1, "meta": {}}),
		"an unknown door is refused")
	check(acts.refused == before + 1, "and counted as a refusal")
	check(not acts.perform({"kind": "sense", "organ": "tarsi"}),
		"and so is a message that is not an Act at all")
	## The bus itself refuses it too, one layer earlier.
	var topic: HexyTopic = pair[0]
	check(not topic.publish("/act", {"kind": "act", "door": "laser", "t_ns": T0,
		"value": 1, "meta": {}}), "the bus refuses an unknown door before delivery")
	acts.queue_free()


## THE APP'S OWN PRODUCER. The whole app is booted, because the point of this
## check is the WIRING: a pheromone Sense marked in_phase must come back out
## as a speaker Act without anybody in the test touching HexyActs.
func _test_the_app_producer() -> void:
	print("\n[ a conspecific in phase is answered with a wing song ]")
	var scene: PackedScene = load("res://scenes/hexy.tscn")
	var app: Node = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var topic: HexyTopic = app.get("topic")
	check(topic != null, "the app built a bus")
	check(app.get_node_or_null("Acts") != null, "and an Acts node")
	check(app.get_node_or_null("Organs") != null, "and an Organs node")
	if topic == null:
		return

	var acted: Array = []
	topic.subscribe("/act", func(m): acted.append(m))

	## NOT IN PHASE: near is not the same as keeping the same hours.
	topic.publish("/sense", HexyMsg.sense("pheromone", "peer", T0,
		{"strength": 1.0, "solar_hour": 9.0}, {"in_phase": false}))
	check(acted.is_empty(), "a peer that is merely near says nothing (%d acts)" % acted.size())

	## IN PHASE: one speaker Act.
	topic.publish("/sense", HexyMsg.sense("pheromone", "peer", T0 + 1,
		{"strength": 1.0, "solar_hour": 9.0}, {"in_phase": true}))
	check(acted.size() == 1, "a peer in phase is answered once (%d acts)" % acted.size())
	check(acted.size() == 1 and String(acted[0].get("door", "")) == "speaker",
		"and the door it opened is the speaker")

	## THE THROTTLE. A swarm arriving together is one song, not a chorus.
	for i in 5:
		topic.publish("/sense", HexyMsg.sense("pheromone", "peer", T0 + 2 + i,
			{"strength": 1.0, "solar_hour": 9.0}, {"in_phase": true}))
	check(acted.size() == 1, "five more in the same tenth of a second stay quiet (%d)" % acted.size())

	app.queue_free()
