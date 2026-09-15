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
	_test_glass_writes_nothing()
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
	check("res://scripts/glass/hud3.gd" in files, "scripts/glass/hud3.gd is there")
	check("res://scripts/glass/app.gd" in files, "scripts/glass/app.gd is there")
	## W10c -- THE DEAD GLASS IS GONE. glass.gd, mobile_hud_store.gd and
	## hud_bridge.gd (with scenes/hud.tscn under it) were a surface nothing
	## instantiated any more, and all three still wrote the store directly.
	## Nothing may put them back without being noticed here.
	for gone in ["res://scripts/glass/glass.gd", "res://scripts/glass/mobile_hud_store.gd",
			"res://scripts/glass/hud_bridge.gd"]:
		check(not (gone in files), "%s is gone and stays gone" % gone.get_file())
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


# -- W8e: the glass only looks ------------------------------------------------

## THE FIVE NAMES A PAGE OF THE GLASS MAY NOT SPEAK.
##
## Each of them was, until W8e, a way for a page to WRITE the organism instead
## of subscribing to it: a clock the front kept for itself (Entrain), a second
## writer of the body (Alchemy), a stage rule in a const block (Journey), a
## dial reaching through the store into the fan-shaped body
## (set_target_heading), and a tap handing the mushroom body its dopamine
## (reward_event). All five are gone; what replaced them is one topic, one
## gauge, and subscriptions.
##
## W10c adds the three WRITES THEMSELVES. Every page is a subscriber and none
## is a writer: a dial says what a finger did as a Sense and the store, which
## owns seat state, applies it. So no file under scripts/glass may call
## `note_seat(`, `note_cast(` or `broadcast(` -- not the pages, not the root.
## W10d -- ALCHEMY IS GONE OUTRIGHT: alchemy.gd is deleted, and with it the
## root's old exemption for wiring the deprecated pressure shim. Nothing
## under scripts/glass, root included, may name it any more.
const BANNED: Array[String] = [
	"Entrain", "entrain",
	"Journey", "journey",
	"Alchemy", "alchemy",
	"set_target_heading",
	"reward_event",
	"note_seat(",
	"note_cast(",
	"broadcast(",
]


func _test_glass_writes_nothing() -> void:
	for path in _scan((["res://scripts/glass"] as Array[String])):
		var text: String = _read(path)
		var dirty: Array[String] = ([] as Array[String])
		for line in _code_lines(text):
			for word in BANNED:
				if line.contains(word) and not dirty.has(word):
					dirty.append(word)
		check(dirty.is_empty(), "%s writes no organism state (%s)"
			% [path.get_file(), ", ".join(dirty) if not dirty.is_empty() else "clean"])
