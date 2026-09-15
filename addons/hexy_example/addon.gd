extends HexyAddon

## HEXY_EXAMPLE -- a tiny "csi sensors" style mock add-on, and nothing more.
##
## It declares one door ("wifi"), reads "/body" so it can shape its guess
## around what the body is already doing, and writes a Sense on "/sense/wifi"
## -- one made-up "how crowded the wifi looks" number, published as an
## antenna organ. Used by tests/test_addon_bus.gd to prove the contract end
## to end: a real add-on's Sense reaches the brain and a Body on "/body"
## changes because of it.

const DOOR := "wifi"

var _topic: HexyTopic = null
var _broker = null
var _sub_id: int = -1
var _last_body: Dictionary = {}
var _ticks: int = 0


func doors() -> PackedStringArray:
	return PackedStringArray([DOOR])


func reads() -> PackedStringArray:
	return PackedStringArray([HexyTopic.TOPIC_BODY])


func writes() -> PackedStringArray:
	return PackedStringArray(["%s/%s" % [HexyTopic.TOPIC_SENSE, DOOR]])


func version() -> String:
	return "1"


func attach(bus: Dictionary) -> void:
	_topic = bus.get("topic", null) as HexyTopic
	_broker = bus.get("broker", null)
	if _broker != null:
		_broker.acquire(DOOR, addon_name())
	if _topic != null:
		_sub_id = _topic.subscribe(HexyTopic.TOPIC_BODY, _on_body)


func detach() -> void:
	if _topic != null and _sub_id >= 0:
		_topic.unsubscribe(_sub_id)
	_sub_id = -1
	if _broker != null:
		_broker.release_door(DOOR)
	_broker = null
	_topic = null
	_last_body = {}


func _on_body(msg: Dictionary) -> void:
	_last_body = msg


## THE ONE READING: a made-up "wifi crowding" number, published as an
## antenna Sense -- the mushroom body listens to antenna, so this is what
## reaches the brain in the test.
func sample(t_ns: int, crowding: float) -> bool:
	_ticks += 1
	if _topic == null:
		return false
	return _topic.publish(HexyTopic.TOPIC_SENSE,
		HexyMsg.sense("antenna", DOOR, t_ns, clampf(crowding, 0.0, 1.0), {}))


func view() -> Control:
	var label := Label.new()
	label.name = "WifiLabel"
	label.text = "wifi · %d samples" % _ticks
	return label
