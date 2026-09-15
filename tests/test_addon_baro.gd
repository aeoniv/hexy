extends SceneTree

## N5 -- hexy_baro, proved on a bare bus (no full HexyStore needed: this
## add-on reads nothing, so there is no Body to move). Covers: the honest
## "no source" Sense at attach, feed()'s baseline/altitude math, the ≤1/2s
## publish throttle, door acquire/release, and a contended door being
## refused up front -- the same shape test_addon_bus.gd proves for
## hexy_example.

const AddonScript = preload("res://addons/hexy_baro/addon.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST ADDON BARO ---")
	_run()
	if failures == 0:
		print("--- ALL ADDON BARO TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- ADDON BARO TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	var topic := HexyTopic.new()
	var broker := Broker.new()
	broker.autosave = false
	var bus: Dictionary = {"topic": topic, "broker": broker}

	var loader := HexyAddons.new()
	loader.name = "AddonsBaro"
	root.add_child(loader)
	loader._bus = bus
	loader._broker = broker

	var addon: HexyAddon = AddonScript.new()
	check(addon.addon_name() == "hexy_baro", "addon_name reads the folder name")
	check(addon.doors().has("barometer"), "doors() declares barometer")
	check(addon.writes().has("/sense/barometer"), "writes() declares /sense/barometer")
	check(addon.valid(), "the add-on passes valid()")

	check(loader.attach_one(addon), "hexy_baro attaches")
	check(broker.holder("barometer") == "hexy_baro", "the broker shows hexy_baro holding barometer")

	var first: Dictionary = topic.last("/sense/barometer")
	check(not first.is_empty(), "attach published one Sense on /sense/barometer")
	check(HexyMsg.kind_of(first) == "sense", "it is a Sense message")
	var first_val: Dictionary = first.get("value", {})
	check(first_val.get("source", "") == "none",
		"the honest attach-time Sense says source=none (%s)" % str(first_val))
	check(first_val.get("hpa", "?") == null, "and hpa is null on the honest Sense")
	check(first_val.get("d_alt_m", "?") == null, "and d_alt_m is null on the honest Sense")

	## -- feed(): baseline seeds on the first sample, so d_alt_m starts at 0 --
	var t0: int = 1_000_000_000
	check(addon.call("feed", 1013.25, t0), "the first feed (past the attach throttle window) publishes")
	var s1: Dictionary = topic.last("/sense/barometer")
	var v1: Dictionary = s1.get("value", {})
	check(float(v1.get("hpa", -1.0)) == 1013.25, "the published hpa matches the fed value")
	check(absf(float(v1.get("d_alt_m", 1.0))) < 0.001,
		"d_alt_m reads ~0 on the sample that seeds the baseline (%s)" % str(v1))
	check(String(v1.get("source", "")) == "device", "source flips to device once fed")

	## -- throttle: a second feed inside 0.5s does not publish -----------------
	var t1: int = t0 + 100_000_000  # +0.1s
	check(not addon.call("feed", 1000.0, t1),
		"a feed within the 0.5s window is throttled (returns false)")
	check(str(topic.last("/sense/barometer")) == str(s1),
		"and the throttled feed did not touch the topic")

	## -- lower pressure, past the throttle window, reads as higher altitude --
	var t2: int = t0 + 600_000_000  # +0.6s from t0, past the 0.5s throttle
	check(addon.call("feed", 1000.0, t2), "a feed past the throttle window publishes")
	var s2: Dictionary = topic.last("/sense/barometer")
	var v2: Dictionary = s2.get("value", {})
	check(float(v2.get("d_alt_m", 0.0)) > 0.0,
		"lower pressure than the baseline reads as a positive altitude change (%s)" % str(v2))

	## -- view() ---------------------------------------------------------------
	var view: Control = addon.view()
	check(view != null, "view() returns a Control")
	check(view is Label, "and it is a Label")
	check(String((view as Label).text).begins_with("baro "), "labelled 'baro ...' (%s)" % (view as Label).text)

	## -- detach: door released, state cleared ---------------------------------
	loader.detach_all()
	check(broker.holder("barometer") == "", "detach releases the barometer door")
	var fresh: HexyAddon = AddonScript.new()
	check(fresh.view().text == "baro -- --", "a fresh instance's view shows the honest placeholder")
	fresh.free()
	loader.queue_free()

	## -- a contended door is refused up front ---------------------------------
	var loader2 := HexyAddons.new()
	loader2.name = "AddonsBaro2"
	root.add_child(loader2)
	loader2._bus = bus
	loader2._broker = broker
	broker.acquire("barometer", "someone_else")
	var rival: HexyAddon = AddonScript.new()
	check(not loader2.attach_one(rival), "attach_one refuses when barometer is already held")
	broker.release_door("barometer", "someone_else")
	loader2.queue_free()
