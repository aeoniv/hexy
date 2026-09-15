extends SceneTree

## TOPIC SMOKE — scripts/core/msg.gd + scripts/core/topic.gd (W8a).
## Prints === ALL PASS === or fails.

var _fails := 0
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		_fails += 1


func _initialize() -> void:
	_body_round_trip()
	_body_radar_state()
	_body_json_round_trip()
	_publish_invalid()
	_subscribe_unsubscribe_last()
	_glass_wall()

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


func _fake_fly_state() -> Dictionary:
	# Shaped like Character.get_fly_state(): fly_brain.state() merged with
	# get_neuromodulators().
	return {
		"heading_rad": 1.25,
		"dominant_trigram": "qian",
		"target_alignment": 0.4,
		"coherence": 0.83,
		"startle": 0.0,
		"curl": 0.0,
		"is_startled": false,
		"pdf": 0.5,
		"phase": "Day",
		"solar_hour": 9.0,
		"habit_bias": 0.0,
		"kc_active": [],
		"kc_count": 0,
		"peers": [],
		"dopamine": 0.6,
		"npf": 0.7,
		"octopamine": 0.5,
		"gaba": 0.4,
		"serotonin": 0.55,
		"fruitless": 0.1,
	}


func _body_round_trip() -> void:
	print("\n- body round trip (store bits + wire)")
	var fs := _fake_fly_state()
	var bits := 21  # some non-zero hexagram
	var b := HexyMsg.body_from_fly_state(fs, bits, 1000)
	_check(HexyMsg.validate(b), "body_from_fly_state produces a valid msg")
	_check(HexyMsg.body_bits(b) == bits, "body_bits matches the bits fed in")

	var row := HexyMsg.body_to_wire(b)
	_check(row.has("bits") and row.has("heading_rad") and row.has("phase") and row.has("stage"),
		"body_to_wire carries bits/heading_rad/phase/stage")
	_check(int(row["bits"]) == bits, "wire row bits equal original bits")

	var b2 := HexyMsg.body_from_wire(row, 2000)
	_check(HexyMsg.body_bits(b2) == bits, "body_bits round-trips through to_wire/from_wire")
	_check(is_equal_approx(float(b2["heading_rad"]), float(b["heading_rad"])),
		"heading_rad survives to_wire/from_wire")


func _body_radar_state() -> void:
	print("\n- body to radar state")
	var fs := _fake_fly_state()
	var b := HexyMsg.body_from_fly_state(fs, 5, 3000)
	var rs := HexyMsg.body_to_radar_state(b)
	# Keys FlyCalciumRadar2D.set_state() reads via fs.get(...): heading_rad,
	# coherence, is_startled, dopamine, serotonin, octopamine, gaba,
	# acetylcholine.
	var radar_keys := ["heading_rad", "coherence", "is_startled", "dopamine",
		"serotonin", "octopamine", "gaba", "acetylcholine"]
	for k in radar_keys:
		_check(rs.has(k), "radar state has key '%s'" % k)
	_check(is_equal_approx(float(rs["heading_rad"]), float(b["heading_rad"])),
		"radar state heading_rad matches body")
	_check(is_equal_approx(float(rs["coherence"]), float(b["glow"])),
		"radar state coherence matches body glow")


func _body_json_round_trip() -> void:
	print("\n- body via JSON")
	var fs := _fake_fly_state()
	var b := HexyMsg.body_from_fly_state(fs, 42, 4000)
	var s := JSON.stringify(b)
	var parsed = JSON.parse_string(s)
	_check(typeof(parsed) == TYPE_DICTIONARY, "JSON round trip yields a Dictionary")
	if typeof(parsed) == TYPE_DICTIONARY:
		_check(HexyMsg.validate(parsed), "JSON-round-tripped body still validates")
		_check(int(parsed.get("bits", -1)) == 42, "JSON round trip preserves bits")


func _publish_invalid() -> void:
	print("\n- publish refuses invalid msg")
	var bus := HexyTopic.new()
	var fired := [0]
	var cb := func(_m): fired[0] += 1
	bus.subscribe(HexyTopic.TOPIC_ACT, cb)
	var bad := {"kind": "act", "door": "speaker"}  # missing t_ns/value/meta
	var ok := bus.publish(HexyTopic.TOPIC_ACT, bad)
	_check(ok == false, "publish returns false for an invalid msg")
	_check(fired[0] == 0, "no subscriber fires on an invalid publish")
	_check(bus.last(HexyTopic.TOPIC_ACT).is_empty(), "invalid publish leaves 'last' empty")

	var good := HexyMsg.act("speaker", 10, "hi")
	var ok2 := bus.publish(HexyTopic.TOPIC_ACT, good)
	_check(ok2 == true, "publish returns true for a valid msg")
	_check(fired[0] == 1, "subscriber fires on a valid publish")


func _subscribe_unsubscribe_last() -> void:
	print("\n- subscribe/unsubscribe/last")
	var bus := HexyTopic.new()
	var order: Array = []
	var id_a := bus.subscribe(HexyTopic.TOPIC_SENSE, func(m): order.append("a"))
	var id_b := bus.subscribe(HexyTopic.TOPIC_SENSE, func(m): order.append("b"))
	var msg := HexyMsg.sense("ocelli", "lux", 5, 0.5)
	bus.publish(HexyTopic.TOPIC_SENSE, msg)
	_check(order == ["a", "b"], "subscribers fire in subscription order")
	_check(bus.last(HexyTopic.TOPIC_SENSE) == msg, "last() returns the latest retained msg")

	var door_topic := "%s/lux" % HexyTopic.TOPIC_SENSE
	_check(bus.last(door_topic) == msg, "per-door sub-topic also retains the msg")

	bus.unsubscribe(id_a)
	order.clear()
	bus.publish(HexyTopic.TOPIC_SENSE, HexyMsg.sense("antenna", "gps", 6, 1.0))
	_check(order == ["b"], "unsubscribed id no longer fires")
	_check(id_a != id_b, "subscribe hands out distinct ids")

	_check(bus.topics().has(HexyTopic.TOPIC_SENSE), "topics() lists a topic that has published")
	_check(bus.last("/nothing/here").is_empty(), "last() on an unknown topic is empty")


func _glass_wall() -> void:
	print("\n- glass wall")
	var msg_src := FileAccess.get_file_as_string("res://scripts/core/msg.gd")
	var topic_src := FileAccess.get_file_as_string("res://scripts/core/topic.gd")
	_check(not msg_src.contains("preload(\"res://scripts/brain") and not msg_src.contains("preload('res://scripts/brain"),
		"msg.gd does not preload scripts/brain")
	_check(not msg_src.contains("preload(\"res://scripts/glass") and not msg_src.contains("preload('res://scripts/glass"),
		"msg.gd does not preload scripts/glass")
	_check(not topic_src.contains("preload(\"res://scripts/brain") and not topic_src.contains("preload('res://scripts/brain"),
		"topic.gd does not preload scripts/brain")
	_check(not topic_src.contains("preload(\"res://scripts/glass") and not topic_src.contains("preload('res://scripts/glass"),
		"topic.gd does not preload scripts/glass")
