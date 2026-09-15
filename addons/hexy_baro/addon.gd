extends HexyAddon

## HEXY_BARO -- a barometric altitude add-on, honest about having no sensor.
##
## Godot has no barometer API of its own, and a `javap -p` pass over
## `addons/ixmnn/bin/debug/ixmnn-debug.aar` (com/ix64/hexy/mnn/IxMnn.class)
## turned up `get_ambient_lux`/`get_proximity` and nothing pressure-shaped --
## the plugin registers light and proximity sensors only, no barometer. So
## this add-on never reads a live pressure value on its own: it declares the
## door, publishes one honest "no source" Sense at attach, and exposes
## [method feed] for a future reader (or a test) to call with a real hPa
## number. When fed, it derives a relative altitude change from a slow (60s)
## EMA baseline via the barometric formula, and republishes at most every
## half second.

const DOOR := "barometer"
## THE ORGAN NAME. None of HexyMsg.SENSE_ORGANS names anything
## pressure-shaped; "antenna" is the same generic "novel sensor" organ
## hexy_example uses for its own made-up door.
const ORGAN := "antenna"
## Publish no more than twice a second.
const PUBLISH_INTERVAL_NS: int = 500_000_000
## THE SLOW BASELINE'S TIME CONSTANT, in seconds -- see [method _ema_alpha].
const BASELINE_TAU_S: float = 60.0

var _topic: HexyTopic = null
var _broker = null
var _sub_id: int = -1

var _baseline_hpa: float = NAN
var _last_hpa = null
var _last_d_alt_m = null
var _last_feed_ns: int = -1
var _last_publish_ns: int = -1
var _samples: int = 0


func doors() -> PackedStringArray:
	return PackedStringArray([DOOR])


func reads() -> PackedStringArray:
	return PackedStringArray()


func writes() -> PackedStringArray:
	return PackedStringArray(["%s/%s" % [HexyTopic.TOPIC_SENSE, DOOR]])


func version() -> String:
	return "1"


func attach(bus: Dictionary) -> void:
	_topic = bus.get("topic", null) as HexyTopic
	_broker = bus.get("broker", null)
	if _broker != null:
		_broker.acquire(DOOR, addon_name())
	## ONE HONEST PUBLISH AT ATTACH: no plugin exposes pressure on this
	## device, so the first (and, until [method feed] is called, only) Sense
	## says exactly that rather than staying silent about it.
	_publish(0, null, null, "none")


func detach() -> void:
	if _topic != null and _sub_id >= 0:
		_topic.unsubscribe(_sub_id)
	_sub_id = -1
	if _broker != null:
		_broker.release_door(DOOR)
	_broker = null
	_topic = null
	_baseline_hpa = NAN
	_last_hpa = null
	_last_d_alt_m = null
	_last_feed_ns = -1
	_last_publish_ns = -1
	_samples = 0


## A READER (OR A TEST) HANDS IN ONE PRESSURE SAMPLE. `t_ns` drives both the
## slow EMA baseline (elapsed time since the last feed) and the ≤1/2s publish
## throttle -- callers own the clock, exactly like [method
## HexyAddonBaro.feed]'s siblings elsewhere in this app. Returns whether a
## Sense was actually published (false when merely throttled).
func feed(hpa: float, t_ns: int = 0) -> bool:
	_samples += 1
	if is_nan(_baseline_hpa):
		_baseline_hpa = hpa
	else:
		var dt_s: float = 0.0
		if _last_feed_ns >= 0 and t_ns > _last_feed_ns:
			dt_s = float(t_ns - _last_feed_ns) / 1_000_000_000.0
		var alpha: float = _ema_alpha(dt_s)
		_baseline_hpa = lerpf(_baseline_hpa, hpa, alpha)
	_last_feed_ns = t_ns

	## THE BAROMETRIC FORMULA, relative to this add-on's own slow baseline --
	## a RELATIVE change (d_alt_m), not an absolute altitude, since the
	## baseline itself drifts with weather, not just height.
	var d_alt_m: float = 44330.0 * (1.0 - pow(hpa / _baseline_hpa, 1.0 / 5.255))
	_last_hpa = hpa
	_last_d_alt_m = d_alt_m

	if _last_publish_ns >= 0 and t_ns - _last_publish_ns < PUBLISH_INTERVAL_NS:
		return false
	return _publish(t_ns, hpa, d_alt_m, "device")


## lerpf(baseline, sample, alpha) with alpha shaped so a longer `dt` pulls the
## baseline further toward the fresh sample -- the standard 1 - e^(-dt/tau)
## EMA weight, tau = [const BASELINE_TAU_S].
func _ema_alpha(dt_s: float) -> float:
	if dt_s <= 0.0:
		return 0.0
	return 1.0 - exp(-dt_s / BASELINE_TAU_S)


func _publish(t_ns: int, hpa, d_alt_m, source: String) -> bool:
	_last_publish_ns = t_ns
	if _topic == null:
		return false
	return _topic.publish(HexyTopic.TOPIC_SENSE,
		HexyMsg.sense(ORGAN, DOOR, t_ns, {
			"hpa": hpa,
			"d_alt_m": d_alt_m,
			"source": source,
		}, {}))


func view() -> Control:
	var label := Label.new()
	label.name = "BaroLabel"
	if _last_hpa == null:
		label.text = "baro -- --"
	else:
		label.text = "baro %.1f hPa %.2f m" % [float(_last_hpa), float(_last_d_alt_m)]
	return label
