extends SceneTree

## THE STUDIO'S COPY OF THE SCHEMA IS STILL THE SCHEMA.
##
## tools/visualizer/index.html draws its CONFIG card from
## tools/visualizer/config_schema.json, which is a DEAD COPY: a file written
## once by tools/gen_config_schema.gd and then left on disk. A dead copy rots
## the moment somebody adds a key to scripts/core/config.gd and does not rerun
## the generator, and nothing in a build would say so -- the studio would just
## quietly stop showing one tunable.
##
## This is the file that says so. It parses the JSON, then holds it against
## HexyConfig.schema() key by key, type by type, bound by bound. When it goes
## red the fix is one line:
##
##   godot --headless --path . -s tools/gen_config_schema.gd

const JSON_PATH: String = "res://tools/visualizer/config_schema.json"

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST CONFIG SCHEMA JSON (the studio's copy) ---")
	_run()
	if failures == 0:
		print("--- ALL CONFIG SCHEMA JSON TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CONFIG SCHEMA JSON TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	check(FileAccess.file_exists(JSON_PATH), "the generator has written %s" % JSON_PATH)
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "and it parses as a JSON object")
	if not (parsed is Dictionary):
		return
	var doc: Dictionary = parsed as Dictionary
	check(doc.has("rows") and doc.has("groups") and doc.has("defaults"),
		"the document carries rows, groups and defaults")

	var cfg := HexyConfig.new()
	cfg.autosave = false
	var live: Array[Dictionary] = cfg.schema()
	var rows: Array = doc.get("rows", []) as Array

	# -- the key set, exactly ------------------------------------------------
	var want: Array[String] = cfg.keys()
	var got: Array[String] = []
	for r in rows:
		got.append(String((r as Dictionary).get("key", "")))
	check(got.size() == want.size(),
		"the file has %d rows and the schema has %d" % [got.size(), want.size()])
	var missing: Array[String] = []
	for k in want:
		if not got.has(k):
			missing.append(k)
	check(missing.is_empty(), "no key is missing from the file (%s)" % str(missing))
	var extra: Array[String] = []
	for k in got:
		if not want.has(k):
			extra.append(k)
	check(extra.is_empty(), "and the file invented none (%s)" % str(extra))
	check(got == want, "and the order is the order a person should meet them in")

	# -- every row, field by field -------------------------------------------
	var drift: Array[String] = []
	for i in range(mini(rows.size(), live.size())):
		var a: Dictionary = rows[i] as Dictionary
		var b: Dictionary = live[i]
		for field in ["key", "group", "type", "doc"]:
			if str(a.get(field, null)) != str(b.get(field, null)):
				drift.append("%s.%s" % [String(b["key"]), field])
		if not _same(a.get("default", null), b.get("default", null)):
			drift.append("%s.default" % String(b["key"]))
		for field in ["min", "max", "step"]:
			if not is_equal_approx(float(a.get(field, 0.0)), float(b[field])):
				drift.append("%s.%s" % [String(b["key"]), field])
		if str(a.get("options", [])) != str(b["options"]):
			drift.append("%s.options" % String(b["key"]))
	check(drift.is_empty(), "no row has drifted from the schema (%s)" % str(drift))

	# -- the groups and the default drawer -----------------------------------
	check(str(doc.get("groups", [])) == str(cfg.groups()),
		"the groups match, in schema order")
	var defaults: Dictionary = doc.get("defaults", {}) as Dictionary
	check(defaults.size() == want.size(), "the defaults drawer holds every key")
	var wrong: Array[String] = []
	for k in want:
		if not _same(defaults.get(k, null), cfg.row(k)["default"]):
			wrong.append(k)
	check(wrong.is_empty(), "and every default is the schema's own (%s)" % str(wrong))

	## THE ROUND TRIP THE STUDIO PROMISES. What the studio exports is the same
	## shape as the defaults drawer, so feeding it straight back into the
	## registry must be accepted whole.
	check(cfg.from_json(JSON.stringify(defaults)),
		"the defaults drawer imports as a HexyConfig document")
	var back: Dictionary = JSON.parse_string(cfg.to_json()) as Dictionary
	var differs: Array[String] = []
	for k in want:
		if not _same(back.get(k, null), defaults.get(k, null)):
			differs.append(k)
	check(differs.is_empty(), "and a fresh drawer writes that document back out (%s)" % str(differs))
	HexyConfig.forget()


## JSON HAS ONE NUMBER AND GDSCRIPT HAS TWO. An int default comes back out of
## the file as a float, so 4096 and 4096.0 are the SAME default and only a
## string compare would say otherwise.
static func _same(a: Variant, b: Variant) -> bool:
	var a_num: bool = a is float or a is int
	var b_num: bool = b is float or b is int
	if a_num and b_num:
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)
