extends SceneTree

## THE ADD-ON CONTRACT, PROVED ON A FAKE DOOR.
##
## An add-on is allowed to write through the seat bus, the homeostat and the
## registry, and nowhere else. The claim this file makes is the one the plan
## makes: ATTACH AND DETACH LEAVES THE STORE EXACTLY AS IT FOUND IT. A fake
## add-on is attached to a fresh HexyStore, it feeds a need line and lands a
## seat, it is detached, and `store.dump()` has to be the same dictionary it
## was before anyone touched it.
##
## And the two ways an add-on does not exist -- no door, or a line that is
## neither a need nor a circuit -- are refused by the loader rather than
## quietly carried.

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


## A DOOR THAT IS NOT THERE. It answers the whole contract, remembers the bus
## it was handed, and puts back on detach() everything it changed.
class FakeAddon extends HexyAddon:
	var attached_store: Object = null
	var attached_bus: Dictionary = {}
	var attached_config: Object = null
	## Written by the test and shared with it, because the loader FREES an
	## add-on it detaches -- a counter on the node itself would be unreadable
	## the moment the thing being counted is gone.
	var log: Array = []
	var _seat_before: Dictionary = {}

	func door() -> String:
		return "ixfake"

	func line() -> int:
		return 0  # Character.LINE_BODY

	func addon_name() -> String:
		return "hexy_fake"

	func version() -> String:
		return "1"

	func config_keys() -> Dictionary:
		return {
			"fake.min_confidence": {
				"type": "float", "min": 0.0, "max": 1.0, "step": 0.01,
				"default": 0.4, "doc": "How sure the fake door has to be."},
		}

	func attach(store: Object, config: Object, bus: Dictionary) -> void:
		attached_store = store
		attached_config = config
		attached_bus = bus.duplicate()
		_seat_before = (store.call("dump") as Dictionary).duplicate(true)
		## The two writes an add-on is allowed: one down the seat bus, one into
		## the homeostat.
		store.call("note_seat", 0, {"kind": "fake", "value": 1})
		var ch: Variant = bus.get("character", null)
		if ch != null and ch.has_method("feed"):
			ch.feed(0, 0.2, "fake", 1000)

	func detach() -> void:
		log.append("detach")
		if attached_store != null and not _seat_before.is_empty():
			attached_store.call("load_dump", _seat_before)


## NO DOOR AT ALL: valid() must say so and the loader must refuse it.
class DoorlessAddon extends HexyAddon:
	func door() -> String:
		return ""

	func line() -> int:
		return 0


## A LINE THAT IS NEITHER A NEED NOR A CIRCUIT.
class WrongLineAddon extends HexyAddon:
	func door() -> String:
		return "ixwrong"

	func line() -> int:
		return 99


func _initialize() -> void:
	print("\n--- TEST ADDON BUS (the contract) ---")
	await _run()
	if failures == 0:
		print("--- ALL ADDON BUS TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- ADDON BUS TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	# -- the contract itself --------------------------------------------------
	check(HexyAddon.line_valid(0) and HexyAddon.line_valid(5),
		"the six need lines are lines")
	check(HexyAddon.line_valid(HexyAddon.CIRCUIT_COMPASS)
			and HexyAddon.line_valid(HexyAddon.CIRCUIT_CIRCADIAN),
		"the four circuits are lines too")
	check(not HexyAddon.line_valid(6) and not HexyAddon.line_valid(99)
			and not HexyAddon.line_valid(-1),
		"and nothing else is")
	check(HexyAddon.line_name(0) == "body"
			and HexyAddon.line_name(HexyAddon.CIRCUIT_COMPASS) == "compass",
		"every line and circuit has a word")

	var cfg := HexyConfig.instance()
	cfg.autosave = false
	cfg.reset()

	var store := HexyStore.new()
	store.name = "Store"
	root.add_child(store)
	await process_frame
	var before: Dictionary = store.dump().duplicate(true)

	var loader := HexyAddons.new()
	loader.name = "Addons"
	root.add_child(loader)
	loader._store = store
	loader._bus = {
		"store": store,
		"character": store.get_character(),
		"alchemy": null,
	}

	var heard: Array[String] = []
	loader.attached.connect(func(n: String) -> void: heard.append("+" + n))
	loader.detached.connect(func(n: String) -> void: heard.append("-" + n))

	# -- the fake door goes on ------------------------------------------------
	var fake := FakeAddon.new()
	var fake_log: Array = []
	fake.log = fake_log
	check(loader.attach_one(fake), "the fake add-on attaches")
	check(loader.names() == ["hexy_fake"], "the loader holds it by name (%s)" % str(loader.names()))
	check(heard == ["+hexy_fake"], "and said so on attached() (%s)" % str(heard))
	check(fake.attached_store == store, "it was handed the one store")
	check(fake.attached_config == cfg, "and the live registry")
	check(fake.attached_bus.has("store") and fake.attached_bus.has("character")
			and fake.attached_bus.has("alchemy"),
		"the bus carries store, character and alchemy")
	check(fake.attached_bus.get("character", null) == store.get_character(),
		"and the character on it is the store's own")

	var m: Dictionary = fake.manifest()
	check(String(m.get("name", "")) == "hexy_fake" and String(m.get("door", "")) == "ixfake"
			and int(m.get("line", -1)) == 0 and String(m.get("version", "")) == "1",
		"the manifest carries name, door, line and version (%s)" % str(m))

	check(loader.doors().get(0, []) == ["ixfake"],
		"the loader maps the body line to the fake door (%s)" % str(loader.doors()))

	# -- the config key it brought --------------------------------------------
	check(cfg.keys().has("fake.min_confidence"), "its namespaced key joined the drawer")
	check(String(cfg.row("fake.min_confidence")["group"]) == "fake",
		"the group came from the namespace")
	check(is_equal_approx(float(cfg.get_value("fake.min_confidence")), 0.4),
		"the default is what the add-on asked for")
	cfg.set_value("fake.min_confidence", 9.0)
	check(is_equal_approx(float(cfg.get_value("fake.min_confidence")), 1.0),
		"and it clamps to the row's ceiling like a built-in (got %s)"
			% str(cfg.get_value("fake.min_confidence")))
	cfg.set_value("fake.min_confidence", -3.0)
	check(is_equal_approx(float(cfg.get_value("fake.min_confidence")), 0.0),
		"and to its floor")
	var rev: int = cfg.revision()
	cfg.register({"fake.min_confidence": {"type": "float", "default": 0.9}})
	check(cfg.revision() == rev, "registering a key twice changes nothing")
	check(is_equal_approx(float(cfg.row("fake.min_confidence")["default"]), 0.4),
		"and cannot move the row already there")
	var schema_keys: Array[String] = []
	for row in cfg.schema():
		schema_keys.append(String(row["key"]))
	check(schema_keys.has("fake.min_confidence"), "schema() carries it like any other row")

	# -- the two refusals -----------------------------------------------------
	print("-- two add-ons that do not exist (two push_errors are the point) --")
	check(not loader.attach_one(DoorlessAddon.new()), "an add-on with no door is refused")
	check(not loader.attach_one(WrongLineAddon.new()), "an add-on with line 99 is refused")
	check(loader.names().size() == 1, "and neither stands on the bus")

	# -- the doors panel names it ---------------------------------------------
	var dash := HexyDashboard.new()
	root.add_child(dash)
	await process_frame
	check(dash.panel("doors") != null, "the doors panel stands on the column")
	check(String(HexyDashboard.TITLES["doors"]).begins_with("10 ·"), "doors is panel 10")
	check(dash.doors_text().contains("food: —"),
		"a panel with no loader draws a dash on every row")
	dash.set_addons(loader)
	var text: String = dash.doors_text()
	print(text)
	check(text.contains("body: ixfake"), "the body row names the fake door")
	check(text.contains("food: —") and text.contains("connection: —"),
		"the rows nothing feeds stay dashes")
	check(text.contains("compass: —") and text.contains("circadian: —"),
		"the circuits have rows of their own")

	# -- and off again --------------------------------------------------------
	loader.detach_all()
	await process_frame
	check(fake_log.size() == 1, "detach_all() called detach() once (%s)" % str(fake_log))
	check(loader.names().is_empty(), "the bus is empty again")
	check(heard == ["+hexy_fake", "-hexy_fake"], "and it said so (%s)" % str(heard))
	check(dash.doors_text().contains("body: —"), "the doors panel forgets it too")

	var after: Dictionary = store.dump()
	check(str(after) == str(before),
		"the store dumps exactly what it dumped before the attach")

	# -- a scan on a tree with no add-on folders ------------------------------
	for path in HexyAddons.scan_paths():
		check(String(path).begins_with("res://addons/hexy_"),
			"scan_paths only ever names res://addons/hexy_* (%s)" % path)
	check(HexyAddons.scan_paths().size() >= 0, "the scan survives a tree with no add-ons")

	dash.queue_free()
	loader.queue_free()
	store.queue_free()
	cfg.reset()
	HexyConfig.forget()
	await process_frame
