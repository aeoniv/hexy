extends SceneTree

## THE ADD-ON CONTRACT (W8d), PROVED ON REAL DOORS.
##
## An add-on is allowed to write Sense and Act, and nowhere else. It may only
## acquire a broker door it declared, and only if nothing else already holds
## it. And ATTACH/DETACH LEAVES THE STORE EXACTLY AS IT FOUND IT: the example
## add-on under addons/hexy_example is attached to a fresh HexyStore's bus, it
## publishes a Sense that reaches the brain and moves the Body on "/body",
## it is detached, and store.dump() is the same dictionary it was before.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


## WRITES OUTSIDE SENSE/ACT: refused at attach.
class BadWriteAddon extends HexyAddon:
	func addon_name() -> String:
		return "hexy_badwrite"

	func doors() -> PackedStringArray:
		return PackedStringArray(["wifi"])

	func writes() -> PackedStringArray:
		return PackedStringArray(["/store"])


## A DOOR IT NEVER DECLARED: the wrapped broker refuses the acquire.
class UndeclaredDoorAddon extends HexyAddon:
	var acquired: bool = true
	var _guard = null  ## the GuardedBroker attach() was handed, kept for FIX 2's asserts

	func addon_name() -> String:
		return "hexy_sneaky"

	func doors() -> PackedStringArray:
		return PackedStringArray(["wifi"])

	func writes() -> PackedStringArray:
		return PackedStringArray(["/sense/wifi"])

	func attach(bus: Dictionary) -> void:
		var broker = bus.get("broker", null)
		_guard = broker
		acquired = broker.acquire("camera", addon_name())


## NEITHER A DOOR NOR A WRITE: refused as not existing.
class EmptyAddon extends HexyAddon:
	func addon_name() -> String:
		return "hexy_empty"


func _initialize() -> void:
	print("\n--- TEST ADDON BUS (the W8d contract) ---")
	await _run()
	if failures == 0:
		print("--- ALL ADDON BUS TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- ADDON BUS TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	# -- refusals, on fakes, no filesystem scan involved ----------------------
	var topic := HexyTopic.new()
	var broker := Broker.new()
	broker.autosave = false
	var bus: Dictionary = {"topic": topic, "broker": broker}

	var loader := HexyAddons.new()
	loader.name = "Addons"
	root.add_child(loader)

	check(not loader.attach_one(EmptyAddon.new()),
		"an add-on with no door and no write is refused")
	check(not loader.attach_one(BadWriteAddon.new()),
		"an add-on writing outside Sense/Act is refused")

	loader._bus = bus
	loader._broker = broker
	var sneaky := UndeclaredDoorAddon.new()
	check(loader.attach_one(sneaky), "the sneaky add-on itself attaches fine")
	check(not sneaky.acquired, "but its undeclared acquire('camera') was refused")
	loader.detach_all()
	check(loader.names().is_empty(), "and it is off the bus again")

	# -- a contended door an organ already holds -------------------------------
	broker.acquire("wifi", "organ")
	check(not loader.attach_one(UndeclaredDoorAddon.new()),
		"attach_one refuses outright when a declared door is already held")
	broker.release_door("wifi", "organ")

	# -- the real example add-on, scanned off disk -----------------------------
	var cfg := HexyConfig.instance()
	cfg.autosave = false
	cfg.reset()

	var store: HexyStore = HexyStoreScript.new()
	store.name = "Store"
	root.add_child(store)
	await process_frame
	var ch: RefCounted = store.get_character()
	ch.attach_bus(topic)
	store.attach_bus(topic)
	ch.tick(1_700_000_000_000)
	var before: Dictionary = store.dump().duplicate(true)

	var loader2 := HexyAddons.new()
	loader2.name = "Addons2"
	root.add_child(loader2)
	var heard: Array[String] = []
	loader2.attached.connect(func(n: String) -> void: heard.append("+" + n))
	loader2.detached.connect(func(n: String) -> void: heard.append("-" + n))

	var count: int = loader2.load_all({"topic": topic, "broker": broker, "store": store})
	## ATTACH ALONE MOVES NOTHING: the example add-on's attach() only
	## subscribes and acquires a door, so the store must read exactly as it
	## did before the loader ever scanned the folder.
	check(str(store.dump()) == str(before),
		"attach alone leaves the store exactly as it found it")
	check(count >= 1, "the scan found at least the example add-on (%d)" % count)
	check(loader2.names().has("hexy_example"), "hexy_example is on the bus (%s)" % str(loader2.names()))
	check(heard.has("+hexy_example"), "and said so on attached()")
	check(loader2.doors().get("wifi", "") == "hexy_example",
		"the doors panel shows hexy_example holding wifi (%s)" % str(loader2.doors()))
	check(loader2.topic_writers().get("/sense/wifi", []).has("hexy_example"),
		"and the topic->writers map names it too")

	## A second add-on trying the same declared door is refused up front.
	var rival := UndeclaredDoorAddon.new()
	check(not loader2.attach_one(rival), "a second add-on cannot also take wifi")

	var example: HexyAddon = null
	for a in loader2.addons():
		if a.addon_name() == "hexy_example":
			example = a
	check(example != null, "the example add-on object is reachable")

	var body_before: Dictionary = topic.last("/body")
	example.call("sample", 1_700_000_010_000 * 1_000_000, 0.9)
	ch.bus_tick(1_700_000_011_000, 1.0)
	var body_after: Dictionary = topic.last("/body")
	check(not body_after.is_empty(), "a Body arrived on /body after the example's Sense")
	check(str(body_after) != str(body_before) or body_before.is_empty(),
		"and the example add-on's Sense reached the brain")

	var v: Control = example.view()
	check(v != null, "the example add-on brings a view")

	## DETACH ALONE MOVES NOTHING EITHER: whatever the example's Sense already
	## did to the store is real and stays; detach() only unsubscribes and
	## releases its door, so the store must read the same immediately before
	## and immediately after it.
	var before_detach: Dictionary = store.dump().duplicate(true)
	loader2.detach_all()
	await process_frame
	check(loader2.names().is_empty(), "the bus is empty again")
	check(heard.has("-hexy_example"), "and it said so")
	check(broker.holder("wifi") == "", "and the wifi door is free again")
	check(str(store.dump()) == str(before_detach),
		"detach alone leaves the store exactly as it found it")

	ch.detach_bus()
	store.detach_bus()

	# -- scan_paths sanity ------------------------------------------------------
	for path in HexyAddons.scan_paths():
		check(String(path).begins_with("res://addons/hexy_"),
			"scan_paths only ever names res://addons/hexy_* (%s)" % path)

	# -- FIX 2: GuardedBroker mirrors the door table exactly --------------------
	print("\n[ GuardedBroker: release_door, deprecated release, undeclared refusals ]")
	var guard_bus: Dictionary = {"topic": topic, "broker": broker}
	var loader3 := HexyAddons.new()
	loader3.name = "Addons3"
	root.add_child(loader3)
	loader3._bus = guard_bus
	loader3._broker = broker
	var guarded_addon := UndeclaredDoorAddon.new()
	check(loader3.attach_one(guarded_addon), "an add-on declaring wifi attaches")
	check(guarded_addon._guard != null, "the add-on was handed a GuardedBroker")
	check(guarded_addon._guard.acquire("wifi", "hexy_sneaky"), "it can acquire its declared door")
	check(broker.holder("wifi") == "hexy_sneaky", "and the real broker shows it holding wifi")
	guarded_addon._guard.release_door("wifi", "hexy_sneaky")
	check(broker.holder("wifi") == "", "release_door hands the real door back")
	check(guarded_addon._guard.acquire("wifi", "hexy_sneaky"), "it re-acquires wifi")
	guarded_addon._guard.release("wifi", "hexy_sneaky")
	check(broker.holder("wifi") == "", "the deprecated release() still works, forwarding to release_door")
	check(not guarded_addon._guard.acquire("camera", "hexy_sneaky"), "acquire still refuses an undeclared door")
	guarded_addon._guard.release_door("camera", "hexy_sneaky")
	check(broker.holder("camera") == "", "release_door on an undeclared door is refused too, not forwarded")
	loader3.detach_all()
	loader3.queue_free()

	loader.queue_free()
	loader2.queue_free()
	store.queue_free()
	cfg.reset()
	HexyConfig.forget()
	await process_frame
