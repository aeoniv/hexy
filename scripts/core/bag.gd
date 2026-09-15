class_name HexyBag
extends RefCounted

## W8f -- BAG + REPLAY: how bias is tested without a phone.
##
## A bag is a recorded day of senses: a JSON file holding a header
## {version, name, dt_ms, tick} plus an Array of HexyMsg Sense dictionaries,
## `t_ns` relative to 0 (the first sense recorded / the start of the day),
## sorted ascending. Playing a bag back through a topic is deterministic and
## uses no wall clock -- every timestamp is one this file or the caller
## chose, exactly like tests/brain_bus_smoke.gd already does by hand.
##
## RECORDING (for a real day, later): attach a HexyBag to a live topic with
## [method record]; every "/sense" message published on it is appended,
## its `t_ns` made relative to the first one seen. [method stop] ends the
## subscription; [method save] writes the file. See tests/bag/README.md.
##
## REPLAY: [method load] reads a bag's senses back (sorted); [method play]
## republishes them on a topic at their own `t_ns`, calling `tick_cb` once
## per `dt_ms` of simulated time so a host's own bus_tick(now_ms, dt) runs
## on the same schedule the bag was recorded on -- no timer, no Engine
## clock, purely simulated time advanced by this loop.

const VERSION: int = 1
const DEFAULT_DT_MS: int = 60000

var _topic: RefCounted = null
var _sub: int = -1
var _senses: Array = []
var _t0: int = -1
var _name: String = "bag"
var _dt_ms: int = DEFAULT_DT_MS


## ------------------------------------------------------------- recording ----

func record(topic: RefCounted, name: String = "bag", dt_ms: int = DEFAULT_DT_MS) -> void:
	stop()
	if topic == null:
		return
	_topic = topic
	_name = name
	_dt_ms = dt_ms
	_senses = []
	_t0 = -1
	_sub = int(topic.subscribe("/sense", Callable(self, "_on_sense")))


func _on_sense(msg: Dictionary) -> void:
	if typeof(msg) != TYPE_DICTIONARY or String(msg.get("kind", "")) != "sense":
		return
	var t_ns: int = int(msg.get("t_ns", 0))
	if _t0 < 0:
		_t0 = t_ns
	var rel: Dictionary = (msg as Dictionary).duplicate(true)
	rel["t_ns"] = t_ns - _t0
	_senses.append(rel)


func stop() -> void:
	if _topic != null and _sub >= 0:
		_topic.unsubscribe(_sub)
	_topic = null
	_sub = -1


## Writes the header plus every sense recorded so far. Does not require
## [method stop] first -- a caller may snapshot mid-recording.
func save(path: String) -> bool:
	var out := {
		"version": VERSION,
		"name": _name,
		"dt_ms": _dt_ms,
		"tick": _senses.size(),
		"senses": _senses,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(out))
	f.close()
	return true


## ---------------------------------------------------------------- replay ----

## The header only: {version, name, dt_ms, tick}. {} when the file is
## missing or not a bag.
static func header(path: String) -> Dictionary:
	var d: Dictionary = _read(path)
	if d.is_empty():
		return {}
	return {
		"version": int(d.get("version", VERSION)),
		"name": String(d.get("name", "")),
		"dt_ms": int(d.get("dt_ms", DEFAULT_DT_MS)),
		"tick": int(d.get("tick", 0)),
	}


## Every Sense dictionary in the bag, sorted by `t_ns` ascending. [] when
## the file is missing or not a bag.
static func load(path: String) -> Array:
	var d: Dictionary = _read(path)
	if d.is_empty():
		return []
	var senses: Array = d.get("senses", [])
	senses.sort_custom(func(a, b): return int((a as Dictionary).get("t_ns", 0)) < int((b as Dictionary).get("t_ns", 0)))
	return senses


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## Publishes every Sense in `senses` on `topic` at its own `t_ns` (senses
## due at or before a tick's `t_ns` go out before that tick's callback
## fires), and calls `tick_cb.call(t_ns)` once per tick, `ticks` times, `dt_ms`
## apart. Purely simulated time: nothing here reads the wall clock or waits.
static func play(topic: RefCounted, senses: Array, tick_cb: Callable,
		dt_ms: int = DEFAULT_DT_MS, ticks: int = 0) -> void:
	if topic == null:
		return
	var idx: int = 0
	for i in range(ticks):
		var t_ns: int = i * dt_ms * 1_000_000
		while idx < senses.size() and int((senses[idx] as Dictionary).get("t_ns", 0)) <= t_ns:
			topic.publish("/sense", senses[idx])
			idx += 1
		if tick_cb.is_valid():
			tick_cb.call(t_ns)
	## Anything stamped after the last tick boundary still goes out, so a
	## short `ticks` never silently drops the tail of a longer bag.
	while idx < senses.size():
		topic.publish("/sense", senses[idx])
		idx += 1
