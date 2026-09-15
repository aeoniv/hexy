extends HexyAddon

## HEXY_WIFICSI -- a coarse "channel state" proxy, standing in for real CSI.
##
## Godot exposes no wifi channel-state-information API and
## `IP.get_local_interfaces`/`OS` offer nothing signal-strength-shaped either,
## so this add-on does not attempt a raw radio read. Instead it rides the
## rssi-like float `hexy_example` already publishes on "/sense/wifi" (door
## "wifi", a 0..1 "how crowded the wifi looks" number) and keeps a 10s
## rolling window of it, publishing the window's variance as a coarse motion
## proxy: a wifi link sitting still reads as a flat signal, a room with
## something moving through it reads as a jittery one. `door()` is its own,
## distinct "wifi_csi" -- hexy_example already holds "wifi", so this add-on
## never contends for it and only ever reads its Sense off the bus.

const DOOR := "wifi_csi"
const READ_TOPIC := HexyTopic.TOPIC_SENSE + "/wifi"
const ORGAN := "antenna"
const WINDOW_NS: int = 10_000_000_000
const PUBLISH_INTERVAL_NS: int = 1_000_000_000
## var_10s above this reads as full (1.0) motion; below it scales linearly.
const MOTION_VAR_SCALE: float = 0.05

var _topic: HexyTopic = null
var _broker = null
var _sub_id: int = -1

var _window: Array = []  # [{t_ns:int, rssi:float}, ...] oldest first
var _last_rssi = null
var _last_var_10s: float = 0.0
var _last_motion: float = 0.0
var _last_publish_ns: int = -1
var _samples: int = 0


func doors() -> PackedStringArray:
	return PackedStringArray([DOOR])


func reads() -> PackedStringArray:
	return PackedStringArray([READ_TOPIC])


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
		_sub_id = _topic.subscribe(READ_TOPIC, _on_wifi_sense)


func detach() -> void:
	if _topic != null and _sub_id >= 0:
		_topic.unsubscribe(_sub_id)
	_sub_id = -1
	if _broker != null:
		_broker.release_door(DOOR)
	_broker = null
	_topic = null
	_window = []
	_last_rssi = null
	_last_var_10s = 0.0
	_last_motion = 0.0
	_last_publish_ns = -1
	_samples = 0


func _on_wifi_sense(msg: Dictionary) -> void:
	var value: Variant = msg.get("value", null)
	var t_ns: int = int(msg.get("t_ns", 0))
	if not (value is float or value is int):
		return
	feed(float(value), t_ns)


## ONE READING, fed directly -- what [method _on_wifi_sense] calls, and what
## a test drives without needing a full topic round trip. Returns whether a
## Sense was actually published (false when merely throttled or windowed).
func feed(rssi: float, t_ns: int = 0) -> bool:
	_samples += 1
	_last_rssi = rssi
	_window.append({"t_ns": t_ns, "rssi": rssi})
	_trim(t_ns)

	_last_var_10s = _variance()
	_last_motion = clampf(sqrt(_last_var_10s) / MOTION_VAR_SCALE, 0.0, 1.0)

	if _last_publish_ns >= 0 and t_ns - _last_publish_ns < PUBLISH_INTERVAL_NS:
		return false
	return _publish(t_ns)


## DROPS SAMPLES OLDER THAN THE 10s WINDOW, relative to the newest t_ns seen.
func _trim(latest_t_ns: int) -> void:
	var cutoff: int = latest_t_ns - WINDOW_NS
	var kept: Array = []
	for s in _window:
		if int((s as Dictionary)["t_ns"]) >= cutoff:
			kept.append(s)
	_window = kept


func _variance() -> float:
	if _window.size() < 2:
		return 0.0
	var sum: float = 0.0
	for s in _window:
		sum += float((s as Dictionary)["rssi"])
	var mean: float = sum / float(_window.size())
	var sq_sum: float = 0.0
	for s in _window:
		var d: float = float((s as Dictionary)["rssi"]) - mean
		sq_sum += d * d
	return sq_sum / float(_window.size())


func _publish(t_ns: int) -> bool:
	_last_publish_ns = t_ns
	if _topic == null:
		return false
	return _topic.publish(HexyTopic.TOPIC_SENSE,
		HexyMsg.sense(ORGAN, DOOR, t_ns, {
			"rssi": _last_rssi,
			"var_10s": _last_var_10s,
			"motion": _last_motion,
		}, {}))


func view() -> Control:
	var label := Label.new()
	label.name = "WifiCsiLabel"
	label.text = "csi var=%.3f motion=%.2f" % [_last_var_10s, _last_motion]
	return label
