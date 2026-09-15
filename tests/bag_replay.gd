extends SceneTree

## W8f -- BAG + REPLAY (tests/bag/README.md, scripts/core/bag.gd).
##
## How bias is tested without a phone: a recorded day of senses replays
## through the same graph deterministically. Two gauges, two caption sets,
## one body.
##
## Time is driven entirely by HexyBag.play()'s simulated tick loop -- nothing
## here waits on a clock.

const HexyStoreScript = preload("res://scripts/core/store.gd")

const QUIET_PATH: String = "res://tests/bag/quiet_day.json"
const BUSY_PATH: String = "res://tests/bag/busy_day.json"
const GAUGE_PATH: String = "user://gauge_bagtest.json"

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
	print("\n--- TEST BAG REPLAY (recorded senses, one body out) ---")
	var t_start: int = Time.get_ticks_msec()

	var hdr: Dictionary = HexyBag.header(QUIET_PATH)
	check(not hdr.is_empty(), "quiet_day.json has a header")
	check(int(hdr.get("tick", 0)) > 0, "and it names a nonzero tick count (%d)" % int(hdr.get("tick", 0)))
	check(int(hdr.get("dt_ms", 0)) == 60000, "one tick is 60 simulated seconds")
	check(String(hdr.get("name", "")) == "quiet_day", "and the header names itself quiet_day")
	var senses: Array = HexyBag.load(QUIET_PATH)
	check(senses.size() > 0, "quiet_day.json carries senses (%d)" % senses.size())
	var sorted: bool = true
	for i in range(1, senses.size()):
		if int((senses[i - 1] as Dictionary)["t_ns"]) > int((senses[i] as Dictionary)["t_ns"]):
			sorted = false
	check(sorted, "and HexyBag.load returns them sorted by t_ns")
	var all_valid: bool = true
	for s in senses:
		if not HexyMsg.validate(s):
			all_valid = false
			break
	check(all_valid, "every sense in quiet_day.json is a valid HexyMsg")

	var hdr_busy: Dictionary = HexyBag.header(BUSY_PATH)
	var senses_busy: Array = HexyBag.load(BUSY_PATH)
	check(int(hdr_busy.get("tick", 0)) == int(hdr.get("tick", 0)),
		"busy_day.json covers the same tick count as quiet_day.json")
	check(senses_busy.size() > senses.size(),
		"busy_day.json carries more senses than quiet_day.json (%d vs %d)"
		% [senses_busy.size(), senses.size()])

	_test_determinism()
	_test_gauge_does_not_touch_the_body()
	_test_senses_matter()

	if FileAccess.file_exists(GAUGE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GAUGE_PATH))
	check(not FileAccess.file_exists(GAUGE_PATH), "the temp gauge file is cleaned up")

	var elapsed_s: float = float(Time.get_ticks_msec() - t_start) / 1000.0
	print("\nreplay wall time: %.2fs" % elapsed_s)
	check(elapsed_s < 140.0, "the whole replay ran comfortably under the 150s budget (%.2fs)" % elapsed_s)

	print("\nPassed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("--- ALL BAG REPLAY TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- BAG REPLAY TESTS FAILED: ", failures, " ---\n")
		quit(1)


## A bus with a store-backed organism on it, and nothing else -- the same
## shape tests/brain_bus_smoke.gd's store test rigs by hand.
func _rig() -> Dictionary:
	var topic := HexyTopic.new()
	var store: HexyStore = HexyStoreScript.new()
	var ch: RefCounted = store.get_character()
	ch.attach_bus(topic)
	store.attach_bus(topic)
	return {"topic": topic, "store": store, "ch": ch}


func _snapshot(b: Dictionary) -> Dictionary:
	var lines: Array = []
	for v in (b.get("lines", []) as Array):
		lines.append(snappedf(float(v), 0.000001))
	return {
		"bits": int(b.get("bits", 0)),
		"lines": lines,
		"heading": snappedf(float(b.get("heading_rad", 0.0)), 0.000001),
	}


## Plays one bag through a fresh rig and returns the whole /body sequence,
## one snapshot per tick.
func _play(path: String) -> Array:
	var rig: Dictionary = _rig()
	var topic: HexyTopic = rig["topic"]
	var ch: RefCounted = rig["ch"]
	var senses: Array = HexyBag.load(path)
	var hdr: Dictionary = HexyBag.header(path)
	var dt_ms: int = int(hdr.get("dt_ms", 60000))
	var ticks: int = int(hdr.get("tick", 0))
	var bodies: Array = []
	var cb := func(t_ns: int) -> void:
		ch.bus_tick(int(t_ns / 1_000_000), float(dt_ms) / 1000.0)
		var b: Dictionary = topic.last("/body")
		if not b.is_empty():
			bodies.append(_snapshot(b))
	HexyBag.play(topic, senses, cb, dt_ms, ticks)
	ch.detach_bus()
	(rig["store"] as HexyStore).detach_bus()
	return bodies


## --- 1. determinism: the same bag, played twice, is the same body path ---
func _test_determinism() -> void:
	print("\n[ the same recorded day plays back the same body, twice ]")
	var run1: Array = _play(QUIET_PATH)
	var run2: Array = _play(QUIET_PATH)
	check(run1.size() == run2.size() and run1.size() > 0,
		"both runs produced the same number of Bodies (%d, %d)" % [run1.size(), run2.size()])
	check(run1 == run2, "and the whole bits/lines/heading sequence is byte-identical across runs")
	var all_in_range: bool = true
	for s in run1:
		for v in (s as Dictionary)["lines"]:
			if float(v) < 0.0 or float(v) > 1.0:
				all_in_range = false
	check(all_in_range, "every line fill in the replayed body stays within 0..1")
	_last_quiet_run = run1


var _last_quiet_run: Array = []


## --- 2. the gauge is a reading, never a second brain ---------------------
func _test_gauge_does_not_touch_the_body() -> void:
	print("\n[ two gauges, two caption sets, one body ]")
	var run_a: Array = _play(QUIET_PATH)
	var run_b: Array = _play(QUIET_PATH)
	var lines_a: Array = []
	var lines_b: Array = []
	for s in run_a:
		lines_a.append((s as Dictionary)["lines"])
	for s in run_b:
		lines_b.append((s as Dictionary)["lines"])
	check(lines_a == lines_b,
		"the /body lines sequence is byte-identical whichever gauge will later read it")

	## A second interpretation: a thumb on every line, a threshold moved, and
	## a whole new vocabulary -- written to disk exactly as the glass would.
	var d: Dictionary = HexyGauge.defaults()
	d["line_lean"] = [0.3, -0.3, 0.3, -0.3, 0.3, -0.3]
	d["lean_threshold"] = 0.3
	(d["words"] as Dictionary)["line_words"] = [
		["low", "mid", "high"], ["low", "mid", "high"], ["low", "mid", "high"],
		["low", "mid", "high"], ["low", "mid", "high"], ["low", "mid", "high"],
	]
	var f := FileAccess.open(GAUGE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

	var g_default := HexyGauge.new("user://gauge_bagtest_default_missing.json")
	var g_second := HexyGauge.new(GAUGE_PATH)
	check(g_second.load(), "the second gauge file loads")

	var bits_differ: bool = false
	var stage_differ: bool = false
	var caption_differ: bool = false
	var path_default: Array[int] = ([] as Array[int])
	var path_second: Array[int] = ([] as Array[int])
	for s in run_a:
		var lines: Array = (s as Dictionary)["lines"]
		var bits_default: int = g_default.bits_of(lines)
		var bits_second: int = g_second.bits_of(lines)
		if bits_default != bits_second:
			bits_differ = true
		path_default.append(bits_default)
		path_second.append(bits_second)

		var cap_default: String = Sentence.of(bits_default, {}, [], {"phase_name": "day"},
			[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], {}, "", g_default)
		var cap_second: String = Sentence.of(bits_second, {}, [], {"phase_name": "day"},
			[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], {}, "", g_second)
		if cap_default != cap_second:
			caption_differ = true

	check(bits_differ, "bits_of(lines) reads at least one tick as a different hexagram between gauges")
	check(caption_differ, "and Sentence.of(..., gauge) says a different caption for at least one tick")

	for i in range(1, path_default.size()):
		var stage_d: int = g_default.stage_of([path_default[i - 1], path_default[i]], 0)
		var stage_s: int = g_second.stage_of([path_second[i - 1], path_second[i]], 0)
		if stage_d != stage_s:
			stage_differ = true
			break
	check(stage_differ, "and stage_of reads at least one step of the walk as a different chapter")


## --- 3. senses matter: a different day plays back a different body -------
func _test_senses_matter() -> void:
	print("\n[ a busier day writes a different body ]")
	var quiet: Array = _last_quiet_run if not _last_quiet_run.is_empty() else _play(QUIET_PATH)
	var busy: Array = _play(BUSY_PATH)
	check(busy.size() > 0, "busy_day.json plays back at all (%d bodies)" % busy.size())
	var lines_quiet: Array = []
	var lines_busy: Array = []
	for s in quiet:
		lines_quiet.append((s as Dictionary)["lines"])
	for s in busy:
		lines_busy.append((s as Dictionary)["lines"])
	check(lines_quiet != lines_busy, "the busy day's line sequence differs from the quiet day's")
	check(lines_quiet.size() == lines_busy.size(),
		"both days still cover the same number of ticks (%d)" % lines_quiet.size())
