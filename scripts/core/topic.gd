class_name HexyTopic
extends RefCounted

## W8a — the ROS shape without ROS. A topic bus, nothing else: no timers, no
## state beyond the latest retained message per topic ("latched", like ROS's
## own convention). Publish refuses an invalid HexyMsg. Delivery is
## synchronous, in subscription order; a subscriber whose Callable has gone
## invalid (freed object) is skipped rather than crashing the rest.
##
## Canonical topic names. Per-door traffic additionally uses the convention
## "/sense/<door>" (e.g. "/sense/lux", "/sense/touch") so a subscriber can
## listen to one organ's door without filtering every /sense message itself;
## publish() fans a "/sense" message out to both "/sense" and
## "/sense/<door>" when the msg carries a "door" field.
const TOPIC_SENSE := "/sense"
const TOPIC_BODY := "/body"
const TOPIC_PHASE := "/phase"
const TOPIC_ACT := "/act"

var _subs: Dictionary = {}  # topic:String -> Array[Dictionary{id:int, callable:Callable}]
var _last: Dictionary = {}  # topic:String -> Dictionary (latest retained msg)
var _next_id: int = 1


## Publishes `msg` on `topic`. Returns false and does nothing (no retention,
## no delivery) when HexyMsg.validate(msg) rejects it.
func publish(topic: String, msg: Dictionary) -> bool:
	if not HexyMsg.validate(msg):
		return false
	_last[topic] = msg
	_deliver(topic, msg)
	if topic == TOPIC_SENSE and msg.has("door"):
		var door_topic: String = "%s/%s" % [TOPIC_SENSE, String(msg["door"])]
		_last[door_topic] = msg
		_deliver(door_topic, msg)
	return true


func _deliver(topic: String, msg: Dictionary) -> void:
	var subs: Array = _subs.get(topic, [])
	for entry in subs.duplicate():
		var cb: Callable = entry["callable"]
		if not cb.is_valid():
			continue
		cb.call(msg)


## Subscribes `callable` to `topic`; returns a subscription id for
## unsubscribe(). Delivery order matches subscription order.
func subscribe(topic: String, callable: Callable) -> int:
	if not _subs.has(topic):
		_subs[topic] = []
	var id: int = _next_id
	_next_id += 1
	_subs[topic].append({"id": id, "callable": callable})
	return id


func unsubscribe(id: int) -> void:
	for topic in _subs.keys():
		var subs: Array = _subs[topic]
		for i in range(subs.size() - 1, -1, -1):
			if int(subs[i]["id"]) == id:
				subs.remove_at(i)


## The latest retained message on `topic`, or {} when nothing has published
## there yet.
func last(topic: String) -> Dictionary:
	return _last.get(topic, {})


## Every topic that has ever received a publish (subscribing alone does not
## create one).
func topics() -> PackedStringArray:
	var out := PackedStringArray()
	for t in _last.keys():
		out.append(String(t))
	return out
