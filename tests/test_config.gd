extends SceneTree

## Headless checks for scripts/core/config.gd: the schema's own honesty, the
## clamps, the signal, the JSON round trip, the reset -- and then the proof
## that any of it MATTERS, which is a Pacing built under a config with a half
## second civil fire turning a line in a half second of still walking.

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST CONFIG (the one drawer) ---")

	_test_schema_is_complete()
	_test_defaults_are_in_bounds()
	_test_groups()
	_test_clamp()
	_test_enum_snaps()
	_test_changed_emits()
	_test_no_signal_on_a_write_that_changes_nothing()
	_test_round_trip()
	_test_reset()
	_test_peek_never_builds()
	_test_pacing_is_live()
	_test_qwen_sentence_clip()
	_test_mesh_topk()

	if failures == 0:
		print("--- ALL CONFIG TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CONFIG TESTS FAILED: ", failures, " ---\n")
		quit(1)


## A config nobody has written to yet: built fresh, reset to defaults, and
## never allowed to touch user://.
func _fresh() -> HexyConfig:
	HexyConfig.forget()
	var cfg: HexyConfig = HexyConfig.instance()
	cfg.autosave = false
	cfg.reset()
	_built.append(cfg)
	return cfg


## Every config this file built. They are Nodes and never enter a tree, so the
## suite frees them itself at the end rather than leaving Godot to report a
## pile of leaked instances over a green run.
var _built: Array[HexyConfig] = []


func _cleanup() -> void:
	HexyConfig.forget()
	for c in _built:
		if is_instance_valid(c):
			c.free()
	_built.clear()


const TYPES: Array[String] = ["float", "int", "bool", "enum"]


func _test_schema_is_complete() -> void:
	var cfg: HexyConfig = _fresh()
	var rows: Array[Dictionary] = cfg.schema()
	check(rows.size() >= 26, "schema carries every registered key (%d)" % rows.size())

	var seen: Dictionary = {}
	var ok_shape: bool = true
	var ok_docs: bool = true
	for r in rows:
		for field in ["key", "group", "type", "default", "options", "doc"]:
			if not r.has(field):
				ok_shape = false
				print("    missing ", field, " in ", r)
		if not TYPES.has(String(r.get("type", ""))):
			ok_shape = false
		if String(r.get("group", "")) == "":
			ok_shape = false
		if String(r.get("doc", "")).length() < 12:
			ok_docs = false
			print("    thin doc on ", r.get("key"))
		seen[String(r.get("key", ""))] = true
	check(ok_shape, "every row has key/group/type/default/options/doc")
	check(ok_docs, "every row's doc is a sentence, not a stub")
	check(seen.size() == rows.size(), "no key appears twice")

	# The contract's own list, named out loud so a rename breaks this test.
	var required: Array[String] = [
		"pacing.civil_fire_s", "pacing.rearm_s", "pacing.mutation_cooldown_s",
		"pacing.martial_threshold", "pacing.inject_lockout_s", "pacing.civil_t",
		"pacing.martial_t", "pacing.beta", "pacing.anchor", "pacing.journal_max",
		"prior.follows_stillness", "prior.max", "prior.weight",
		"qwen.max_sentences", "qwen.max_tokens", "qwen.one_line_only",
		"senses.period_ms",
		"hud.dwell_ring", "hud.line_flash", "hud.earth_mode", "hud.bubble_ttl_s",
		"hud.status_mode", "hud.room_highlight",
		"mesh.q6_on_wire", "mesh.q6_topk",
		"creature.breathe_with_dwell",
	]
	var missing: Array[String] = []
	for k in required:
		if not seen.has(k):
			missing.append(k)
	check(missing.is_empty(), "every contracted key is registered (missing: %s)" % str(missing))


func _test_defaults_are_in_bounds() -> void:
	var cfg: HexyConfig = _fresh()
	var ok: bool = true
	for r in cfg.schema():
		var key: String = String(r["key"])
		var d: Variant = r["default"]
		match String(r["type"]):
			"float", "int":
				var lo: float = float(r["min"])
				var hi: float = float(r["max"])
				if float(d) < lo or float(d) > hi or lo > hi:
					ok = false
					print("    out of bounds: ", key)
			"enum":
				if not (r["options"] as Array).has(String(d)):
					ok = false
					print("    default not an option: ", key)
			"bool":
				if not (d is bool):
					ok = false
					print("    non-bool default: ", key)
		if not HexyConfig._same(cfg.get_value(key), d):
			ok = false
			print("    fresh value is not the default: ", key)
	check(ok, "every default sits inside its own row's bounds and is the live value")


func _test_groups() -> void:
	var cfg: HexyConfig = _fresh()
	var g: Array[String] = cfg.groups()
	check(g.has("pacing") and g.has("prior") and g.has("qwen") and g.has("senses")
			and g.has("hud") and g.has("mesh") and g.has("creature"),
		"groups() names all seven drawers")
	var dup: bool = false
	var seen: Dictionary = {}
	for name in g:
		if seen.has(name):
			dup = true
		seen[name] = true
	check(not dup, "groups() repeats nothing")


func _test_clamp() -> void:
	var cfg: HexyConfig = _fresh()
	cfg.set_value("pacing.martial_threshold", 9.0)
	check(is_equal_approx(float(cfg.get_value("pacing.martial_threshold")), 1.0),
		"a float above max clamps to max")
	cfg.set_value("pacing.martial_threshold", -4.0)
	check(is_equal_approx(float(cfg.get_value("pacing.martial_threshold")), 0.0),
		"a float below min clamps to min")
	cfg.set_value("mesh.q6_topk", 999)
	check(int(cfg.get_value("mesh.q6_topk")) == 64, "an int above max clamps to max")
	cfg.set_value("qwen.max_sentences", 0)
	check(int(cfg.get_value("qwen.max_sentences")) == 1, "an int below min clamps to min")
	cfg.set_value("pacing.journal_max", 4096.7)
	check(int(cfg.get_value("pacing.journal_max")) == 4097, "a float written to an int rounds")
	check(cfg.get_value("no.such.key") == null, "an unknown key answers null")


func _test_enum_snaps() -> void:
	var cfg: HexyConfig = _fresh()
	cfg.set_value("hud.earth_mode", "stations")
	check(String(cfg.get_value("hud.earth_mode")) == "stations", "an enum takes a legal option")
	cfg.set_value("hud.earth_mode", "moonbeams")
	check(String(cfg.get_value("hud.earth_mode")) == "lines",
		"an enum handed nonsense falls back to its default")


var _heard: Array = []


func _on_changed(key: String, value: Variant) -> void:
	_heard.append([key, value])


func _test_changed_emits() -> void:
	var cfg: HexyConfig = _fresh()
	_heard.clear()
	cfg.changed.connect(_on_changed)
	var rev_before: int = cfg.revision()
	cfg.set_value("senses.period_ms", 1200)
	check(_heard.size() == 1, "one write, one changed")
	check(_heard.size() == 1 and String(_heard[0][0]) == "senses.period_ms",
		"changed names the key")
	check(_heard.size() == 1 and int(_heard[0][1]) == 1200, "changed carries the clamped value")
	check(cfg.revision() == rev_before + 1, "a write moves the revision")

	_heard.clear()
	cfg.set_value("senses.period_ms", 99999999)
	check(_heard.size() == 1 and int(_heard[0][1]) == 60000,
		"changed carries the CLAMPED value, never the raw one")
	cfg.changed.disconnect(_on_changed)


func _test_no_signal_on_a_write_that_changes_nothing() -> void:
	var cfg: HexyConfig = _fresh()
	cfg.set_value("hud.bubble_ttl_s", 4.0)
	_heard.clear()
	cfg.changed.connect(_on_changed)
	var rev: int = cfg.revision()
	cfg.set_value("hud.bubble_ttl_s", 4.0)
	check(_heard.is_empty(), "writing the same value again is silent")
	check(cfg.revision() == rev, "a silent write does not move the revision")
	cfg.changed.disconnect(_on_changed)


func _test_round_trip() -> void:
	var cfg: HexyConfig = _fresh()
	cfg.set_value("pacing.civil_fire_s", 7.5)
	cfg.set_value("hud.status_mode", "telemetry")
	cfg.set_value("mesh.q6_on_wire", false)
	cfg.set_value("qwen.max_tokens", 160)
	var text: String = cfg.to_json()
	check(text.length() > 100, "to_json produces a whole drawer")

	var back: HexyConfig = _fresh()
	check(back.from_json(text), "from_json accepts its own output")
	var ok: bool = true
	for r in cfg.schema():
		var key: String = String(r["key"])
		if not HexyConfig._same(back.get_value(key), cfg.get_value(key)):
			ok = false
			print("    round trip lost ", key, ": ", cfg.get_value(key),
				" -> ", back.get_value(key))
	check(ok, "every key survives to_json -> from_json unchanged")

	check(not back.from_json("[1, 2, 3]"), "from_json refuses a non-object")
	check(back.from_json('{"no.such.key": 4, "qwen.max_tokens": 99}'),
		"from_json ignores keys it does not know")
	check(int(back.get_value("qwen.max_tokens")) == 99,
		"...and still takes the ones it does")
	back.from_json('{"qwen.max_tokens": 99999}')
	check(int(back.get_value("qwen.max_tokens")) == 512,
		"an import cannot smuggle past the clamps")


func _test_reset() -> void:
	var cfg: HexyConfig = _fresh()
	cfg.set_value("pacing.beta", 40.0)
	cfg.set_value("prior.weight", 0.3)
	cfg.reset("pacing.beta")
	check(is_equal_approx(float(cfg.get_value("pacing.beta")), 2.5),
		"reset(key) returns one key to its default")
	check(is_equal_approx(float(cfg.get_value("prior.weight")), 0.3),
		"...and leaves the others alone")
	cfg.reset()
	check(is_equal_approx(float(cfg.get_value("prior.weight")), 0.0),
		"reset() returns the whole drawer")


func _test_peek_never_builds() -> void:
	HexyConfig.forget()
	check(HexyConfig.peek() == null, "peek on an empty world answers null")
	check(HexyConfig.peek() == null, "...and asking did not build one")
	var cfg: HexyConfig = HexyConfig.instance()
	cfg.autosave = false
	check(HexyConfig.peek() == cfg, "peek finds the one instance once it exists")
	check(HexyConfig.instance() == cfg, "instance is a singleton")
	HexyConfig.forget()


# --- and now: does any of it actually reach the app? -------------------------

## THE PROOF. A Pacing built with a drawer whose civil fire is half a second
## turns a line inside half a second of still walking -- where the same walk
## under the default 2.5 s turns nothing at all.
func _test_pacing_is_live() -> void:
	HexyConfig.forget()
	var slow: Pacing = Pacing.new()
	slow.reset(0)
	check(is_equal_approx(slow.civil_fire_s, Pacing.CIVIL_FIRE_THRESHOLD),
		"a Pacing born with no drawer keeps its consts")
	check(_walk_flips(slow, 600) == false,
		"...and at 2.5 s it turns nothing in a 0.6 s still walk")

	var cfg: HexyConfig = _fresh()
	cfg.set_value("pacing.civil_fire_s", 0.5)
	cfg.set_value("pacing.rearm_s", 0.0)
	var fast: Pacing = Pacing.new()
	fast.reset(0)
	check(is_equal_approx(fast.civil_fire_s, 0.5), "a Pacing born under the drawer reads 0.5")
	check(_walk_flips(fast, 600), "civil_fire_s = 0.5 turns a line in a 0.5 s still walk")

	# And live, not just at birth: an existing Pacing follows a later write.
	cfg.set_value("pacing.mutation_cooldown_s", 9.0)
	fast.tick(700, 63, 1.0, 0.0)
	check(is_equal_approx(fast.mutation_cooldown_s, 9.0),
		"a running Pacing picks up a later write on its next tick")
	HexyConfig.forget()


## Walk `ms` milliseconds of perfect stillness toward figure 63, 20 ms a step.
## True when any line turned.
func _walk_flips(p: Pacing, ms: int) -> bool:
	var t: int = 0
	while t <= ms:
		var out: Dictionary = p.tick(t, 63, 1.0, 0.0)
		if not out.is_empty():
			return true
		t += 20
	return false


func _test_qwen_sentence_clip() -> void:
	check(Qwen.first_sentences("One. Two. Three.", 1) == "One.",
		"one sentence is the first sentence")
	check(Qwen.first_sentences("One. Two. Three.", 2) == "One. Two.",
		"two sentences stop at the second full stop")
	check(Qwen.first_sentences("Really? Yes!", 1) == "Really?",
		"a question mark ends a sentence")
	check(Qwen.first_sentences("What?! Now.", 1) == "What?!",
		"a run of marks ends ONE sentence")
	check(Qwen.first_sentences("安静。再说。", 1) == "安静。",
		"the Chinese full stop ends a sentence")
	check(Qwen.first_sentences("no terminator here", 1) == "no terminator here",
		"an unterminated answer comes back whole")
	check(Qwen.first_sentences("One. Two.", 6) == "One. Two.",
		"asking for more sentences than there are keeps them all")


func _test_mesh_topk() -> void:
	var mass := PackedFloat32Array()
	mass.resize(64)
	mass[3] = 0.5
	mass[40] = 0.25
	mass[7] = 0.125

	var full: Dictionary = MeshFabric.bio_payload(0.0, 0.5, [], mass, 0)
	check(full.has("q6") and not full.has("q6k"), "topk 0 sends the full cube")
	check((full["q6"] as PackedFloat32Array).size() == 64, "...all 64 corners of it")

	var thin: Dictionary = MeshFabric.bio_payload(0.0, 0.5, [], mass, 2)
	check(thin.has("q6k") and not thin.has("q6"), "topk 2 sends pairs instead")
	check((thin["q6k"] as PackedFloat32Array).size() == 4, "...two (index, mass) pairs")
	check(int((thin["q6k"] as PackedFloat32Array)[0]) == 3, "the heaviest corner leads")

	var read_full: PackedFloat32Array = MeshFabric.q6_of(full)
	var read_thin: PackedFloat32Array = MeshFabric.q6_of(thin)
	check(read_full.size() == 64 and is_equal_approx(read_full[3], 0.5),
		"the reader understands the full cube")
	check(read_thin.size() == 64 and is_equal_approx(read_thin[3], 0.5)
			and is_equal_approx(read_thin[40], 0.25) and is_equal_approx(read_thin[7], 0.0),
		"the reader understands the thinned one, and the corners it dropped read zero")
	check(MeshFabric.q6_of({}).is_empty(), "a pulse with no cube answers an empty mass")
