extends SceneTree

## THE IMPORT WALL.
##
## The glass and the creature are allowed to know the CORE (store, iching,
## qwen, mnn, wmn) and the objects handed to them in bind(). They are not
## allowed to reach for a sense, a socket, a model file or an engine singleton
## on their own. The wall is one-way and it is checked from both sides: the
## sixteen must not know the glass exists either, or the whole point of driving
## them from a test with no device attached is lost.
##
## This is a TEXT test on purpose. A runtime check would only fail on the one
## path a run happens to take; a grep over the source fails the moment the
## import is written.

const UPPER: Array[String] = ["res://scripts/glass", "res://scripts/creature"]
const LOWER: Array[String] = ["res://scripts/senses", "res://scripts/net", "res://scripts/brain"]

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST GLASS WALL (what the glass may not import) ---")
	_test_upper_files_exist()
	_test_upper_does_not_reach_down()
	_test_no_engine_singletons()
	_test_senses_does_not_reach_up()
	if failures == 0:
		print("--- ALL GLASS WALL TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- GLASS WALL TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _test_upper_files_exist() -> void:
	var files: Array[String] = _scan(UPPER)
	check(files.size() >= 3, "the glass and the creature are on disk (%d scripts)" % files.size())
	check("res://scripts/glass/glass.gd" in files, "scripts/glass/glass.gd is there")
	check("res://scripts/glass/app.gd" in files, "scripts/glass/app.gd is there")
	check("res://scripts/creature/creature.gd" in files, "scripts/creature/creature.gd is there")


func _test_upper_does_not_reach_down() -> void:
	for path in _scan(UPPER):
		var text: String = _read(path)
		for banned in LOWER:
			check(not text.contains(banned),
				"%s does not reach for %s" % [path.get_file(), banned])
		for line in _code_lines(text):
			var reaches: bool = false
			for banned in LOWER:
				if line.contains("preload(") and line.contains(banned):
					reaches = true
				if line.contains("load(") and line.contains(banned):
					reaches = true
			check(not reaches, "%s has no preload of a lower layer" % path.get_file())


func _test_no_engine_singletons() -> void:
	for path in _scan(UPPER):
		var text: String = _read(path)
		var dirty: bool = false
		for line in _code_lines(text):
			if line.contains("Engine.has_singleton") or line.contains("Engine.get_singleton"):
				dirty = true
			for sing in ["IxMnn", "IxMesh", "IxSensors"]:
				if line.contains(sing):
					dirty = true
		check(not dirty, "%s asks no engine singleton for anything" % path.get_file())


func _test_senses_does_not_reach_up() -> void:
	var files: Array[String] = _scan((["res://scripts/senses"] as Array[String]))
	check(files.size() >= 17, "the sixteen and their base are on disk (%d scripts)" % files.size())
	for path in files:
		var text: String = _read(path)
		for banned in UPPER:
			check(not text.contains(banned),
				"%s does not know about %s" % [path.get_file(), banned])
		var dirty: bool = false
		for line in _code_lines(text):
			if line.contains("Glass") or line.contains("Creature") or line.contains("HexyApp"):
				dirty = true
		check(not dirty, "%s names no part of the glass" % path.get_file())


# -- reading the tree --------------------------------------------------------

static func _scan(roots: Array[String]) -> Array[String]:
	var out: Array[String] = ([] as Array[String])
	for root in roots:
		_walk(root, out)
	out.sort()
	return out


static func _walk(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if d.current_is_dir():
			_walk(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()


static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


## Every line that is not a comment: a rule about imports must not be tripped
## by a sentence describing the rule.
static func _code_lines(text: String) -> Array[String]:
	var out: Array[String] = ([] as Array[String])
	for raw in text.split("\n"):
		var line: String = String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return out
