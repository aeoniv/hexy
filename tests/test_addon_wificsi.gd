extends SceneTree

## N5 -- hexy_wificsi, on a bare bus. Covers: reading hexy_example's
## rssi-like Sense off "/sense/wifi", the 10s rolling variance/motion
## computation, the ≤1/1s publish throttle, door acquire/release under its
## own distinct door name "wifi_csi" (never contending with hexy_example's
## "wifi"), and detach.

const AddonScript = preload("res://addons/hexy_wificsi/addon.gd")
const ExampleScript = preload("res://addons/hexy_example/addon.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST ADDON WIFICSI ---")
	_run()
	if failures == 0:
		print("--- ALL ADDON WIFICSI TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- ADDON WIFICSI TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	var topic := HexyTopic.new()
	var broker := Broker.new()
	broker.autosave = false
	var bus: Dictionary = {"topic": topic, "broker": broker}

	var loader := HexyAddons.new()
	loader.name = "AddonsWificsi"
	root.add_child(loader)
	loader._bus = bus
	loader._broker = broker

	var addon: HexyAddon = AddonScript.new()
	check(addon.addon_name() == "hexy_wificsi", "addon_name reads the folder name")
	check(addon.doors().has("wifi_csi"), "doors() declares wifi_csi, distinct from hexy_example's wifi")
	check(addon.reads().has("/sense/wifi"), "reads() declares /sense/wifi")
	check(addon.writes().has("/sense/wifi_csi"), "writes() declares /sense/wifi_csi")
	check(addon.valid(), "the add-on passes valid()")

	## -- hexy_example already holds "wifi": no contention with "wifi_csi" -----
	var example: HexyAddon = ExampleScript.new()
	check(loader.attach_one(example), "hexy_example attaches and holds its own wifi door")
	check(loader.attach_one(addon), "hexy_wificsi attaches beside it with no door conflict")
	check(broker.holder("wifi") == "hexy_example", "hexy_example still holds wifi")
	check(broker.holder("wifi_csi") == "hexy_wificsi", "hexy_wificsi holds its own distinct door")

	## -- flat signal: low variance, near-zero motion --------------------------
	var t0: int = 1_000_000_000
	addon.call("feed", 0.5, t0)
	addon.call("feed", 0.5, t0 + 100_000_000)
	var published: bool = addon.call("feed", 0.5, t0 + 1_100_000_000)  # past the 1s throttle
	check(published, "a feed past the 1s throttle publishes")
	var flat: Dictionary = topic.last("/sense/wifi_csi").get("value", {})
	check(float(flat.get("var_10s", 1.0)) < 0.001, "a flat signal reads ~0 variance (%s)" % str(flat))
	check(float(flat.get("motion", 1.0)) < 0.05, "and near-zero motion (%s)" % str(flat))

	## -- throttle: a feed inside 1s of the last publish does not publish ------
	var before: Dictionary = topic.last("/sense/wifi_csi")
	check(not addon.call("feed", 0.9, t0 + 1_200_000_000),
		"a feed within the 1s throttle window returns false")
	check(str(topic.last("/sense/wifi_csi")) == str(before), "and did not touch the topic")

	## -- jittery signal: higher variance, higher motion -----------------------
	var t1: int = t0 + 3_000_000_000
	addon.call("feed", 0.1, t1)
	addon.call("feed", 0.9, t1 + 100_000_000)
	addon.call("feed", 0.1, t1 + 200_000_000)
	var jitter: bool = addon.call("feed", 0.9, t1 + 1_300_000_000)  # past throttle again
	check(jitter, "a feed past the throttle window publishes")
	var jittery: Dictionary = topic.last("/sense/wifi_csi").get("value", {})
	check(float(jittery.get("var_10s", 0.0)) > float(flat.get("var_10s", 0.0)),
		"a jittery signal reads higher variance than the flat one (%s vs %s)"
			% [str(jittery), str(flat)])
	check(float(jittery.get("motion", 0.0)) > float(flat.get("motion", 0.0)),
		"and higher motion")

	## -- reading through the actual topic (hexy_example's own Sense) ---------
	var t2: int = t1 + 20_000_000_000  # far enough to clear the 10s window
	example.call("sample", t2, 0.2)
	var via_topic: Dictionary = topic.last("/sense/wifi_csi").get("value", {})
	check(float(via_topic.get("rssi", -1.0)) == 0.2,
		"a Sense arriving on /sense/wifi (not just feed()) updates hexy_wificsi too (%s)"
			% str(via_topic))

	## -- view() ---------------------------------------------------------------
	var view: Control = addon.view()
	check(view != null, "view() returns a Control")
	check(view is Label, "and it is a Label")
	check(String((view as Label).text).begins_with("csi var="),
		"labelled 'csi var=...' (%s)" % (view as Label).text)

	## -- detach: both doors released, hexy_wificsi unsubscribed ---------------
	loader.detach_all()
	check(broker.holder("wifi") == "", "detach also frees hexy_example's wifi door")
	check(broker.holder("wifi_csi") == "", "and hexy_wificsi's own door")
	loader.queue_free()
