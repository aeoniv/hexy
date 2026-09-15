extends SceneTree

## THE FFBRAIN WALL (W8c).
##
## ffbrain is canon: immutable, heuristic-free, and with no external writer.
## Two rules say so, and both are checked as TEXT, because a runtime check only
## fails on the path a run happens to take while a grep over the source fails
## the moment the line is written:
##
##   1. NOTHING UNDER scripts/brain KNOWS THE INTERPRETERS. The gauge, alchemy,
##      entrain, the journey, the sentence and the whole glass are readings OF
##      the brain; a brain that read one of them back would be a brain with an
##      opinion about its own output. Senses come in as HexyMsg on a HexyTopic
##      and the two messages go out; that is the whole seam.
##
##   2. THE BODY'S BITS HAVE ONE WRITER. `store.set_body` is internal to
##      store.gd and to scripts/brain: everything else reaches the body by
##      publishing a Body message on "/body", which the store's own subscriber
##      takes. A second setter anywhere under scripts/ fails this file.
##
## Comment lines are skipped throughout: a rule must not be tripped by the
## sentence that describes it.

const BRAIN: String = "res://scripts/brain"
const CORE: String = "res://scripts/core"

## The interpreters. A brain may not name any of them, by path or by class.
const BANNED_PATHS: Array[String] = [
	"res://scripts/core/gauge.gd",
	"res://scripts/core/alchemy.gd",
	"res://scripts/core/entrain.gd",
	"res://scripts/core/iching/journey.gd",
	"res://scripts/core/sentence.gd",
	"res://scripts/glass",
]
const BANNED_NAMES: Array[String] = [
	"HexyGauge", "Alchemy", "Entrain", "Journey", "Sentence", "Front", "Dashboard",
]

## The one setter, and the two places it may be reached from.
const SETTER: String = "set_body("
const SETTER_ALLOWED: Array[String] = ["res://scripts/core/store.gd", "res://scripts/brain"]

## W10a -- THE HOMEOSTAT'S OTHER FOUR WRITERS. `set_body` was only the bits;
## these four are the LINES, and each one is the brain's internal API:
##   reward_event(  -- a dopaminergic event, edge-detected inside the brain.
##   feed_senses(   -- the whole pre-bus ad-hoc feed path.
##   feed(          -- a line fill.
##   _set_fullness( -- a line, written outright.
## Everything outside scripts/brain (and store.gd, which owns the character)
## reaches all four the one way: publish a Sense and let route_sense decide.
const BRAIN_API: Array[String] = [
	"reward_event(", "feed_senses(", "feed(", "_set_fullness(",
]

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
	print("\n--- TEST GAUGE WALL (what ffbrain may not know) ---")
	_test_the_brain_is_on_disk()
	_test_brain_names_no_interpreter()
	_test_brain_preloads_only_itself()
	_test_the_body_has_one_setter()
	_test_the_homeostat_has_no_outside_writer()
	_test_the_oracle_has_no_fallback()
	_test_the_seam_exists()
	print("\nPassed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("--- ALL GAUGE WALL TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- GAUGE WALL TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _test_the_brain_is_on_disk() -> void:
	print("\n[ the brain is where the wall says it is ]")
	var files: Array[String] = _scan([BRAIN])
	check(files.size() >= 8, "scripts/brain holds the organism (%d scripts)" % files.size())
	check("res://scripts/brain/fly_brain.gd" in files, "fly_brain.gd is there")
	check("res://scripts/brain/character.gd" in files, "character.gd is there")


func _test_brain_names_no_interpreter() -> void:
	print("\n[ ffbrain reads no reading of itself ]")
	for path in _scan([BRAIN]):
		var dirty: Array[String] = ([] as Array[String])
		for line in _code_lines(_read(path)):
			for banned in BANNED_PATHS:
				if line.contains(banned):
					dirty.append(banned)
			for name in BANNED_NAMES:
				if _names(line, name):
					dirty.append(name)
		check(dirty.is_empty(), "%s names no interpreter%s" % [
			path.get_file(), "" if dirty.is_empty() else " (found %s)" % ", ".join(dirty)])


## A brain may preload its own organs and the small shared things a runtime
## needs (a seam, an identity); it may NOT load a reading of itself, by preload
## or by a runtime load(), and no glass at all.
func _test_brain_preloads_only_itself() -> void:
	print("\n[ and loads no reading of itself ]")
	for path in _scan([BRAIN]):
		var outside: Array[String] = ([] as Array[String])
		for line in _code_lines(_read(path)):
			if not (line.contains("preload(") or line.contains("load(")):
				continue
			var at: int = line.find("res://")
			if at < 0:
				continue
			var rest: String = line.substr(at)
			var quote: int = rest.find("\"")
			var loaded: String = rest.substr(0, quote) if quote > 0 else rest
			for banned in BANNED_PATHS:
				if loaded.begins_with(banned):
					outside.append(loaded)
		check(outside.is_empty(), "%s loads no interpreter%s" % [
			path.get_file(), "" if outside.is_empty() else " (found %s)" % ", ".join(outside)])


func _test_the_body_has_one_setter() -> void:
	print("\n[ the body's bits have one writer, and it is the /body subscriber ]")
	var callers: Array[String] = ([] as Array[String])
	for path in _scan([CORE, "res://scripts/glass", "res://scripts/senses",
			"res://scripts/net", "res://scripts/creature", "res://scripts/social"]):
		if _allowed(path):
			continue
		for line in _code_lines(_read(path)):
			## `set_body_bits` / `set_body_slot` / `set_body_hexagram` are the
			## glass's own dial names and write no store.
			if line.contains("set_body_bits") or line.contains("set_body_slot"):
				continue
			if line.contains("set_body_hexagram"):
				continue
			if line.contains(SETTER):
				callers.append("%s: %s" % [path.get_file(), line.strip_edges()])
	check(callers.is_empty(), "nothing outside store.gd and scripts/brain calls set_body%s" % (
		"" if callers.is_empty() else " (found %d: %s)" % [callers.size(), callers[0]]))

	var store_text: String = _read("res://scripts/core/store.gd")
	check(store_text.contains("func attach_bus("), "the store subscribes to a bus at all")
	check(store_text.contains("_on_body_msg"), "and takes the body off /body")
	check(not FileAccess.file_exists("res://scripts/core/alchemy.gd"),
		"alchemy.gd does not exist")


## W10a. The same shape as the set_body rule, for the four calls that write a
## LINE rather than the bits.
func _test_the_homeostat_has_no_outside_writer() -> void:
	print("
[ the six lines have no writer outside the brain ]")
	for api in BRAIN_API:
		var callers: Array[String] = ([] as Array[String])
		for path in _scan([CORE, "res://scripts/glass", "res://scripts/senses",
				"res://scripts/net", "res://scripts/creature", "res://scripts/social"]):
			if _allowed(path):
				continue
			for line in _code_lines(_read(path)):
				var at: int = line.find(api)
				if at < 0:
					continue
				## `func feed(` is a DEFINITION, not a call, and so is any other
				## name that merely ENDS with the one being hunted --
				## `_feed_fly_brain(`, `speed(`, `set_fullness(`.
				var before: String = line.substr(at - 1, 1) if at > 0 else " "
				if before.is_valid_identifier() or before == "_":
					continue
				if line.strip_edges().begins_with("func "):
					continue
				callers.append("%s: %s" % [path.get_file(), line.strip_edges()])
		check(callers.is_empty(), "nothing outside store.gd and scripts/brain calls %s%s" % [
				api, "" if callers.is_empty() else " (found %d: %s)" % [callers.size(), callers[0]]])


## W10a. The oracle published a halteres Sense the organs also publish, and
## fell back to writing the character directly when no topic was bound. Both
## are gone: one producer per door, and an unbound bus is an error, not a
## quieter path that nothing notices.
func _test_the_oracle_has_no_fallback() -> void:
	print("
[ the oracle has one way out, and it is the bus ]")
	var oracle: String = _code(_read("res://scripts/sensor_oracle.gd"))
	check(oracle != "", "sensor_oracle.gd is on disk")
	check(not oracle.contains("ch.reward_event("),
		"the oracle no longer calls reward_event directly")
	check(not oracle.contains("ch.feed_senses("),
		"the oracle no longer calls feed_senses directly")
	check(not oracle.contains("\"halteres\""),
		"and no longer publishes halteres -- HexySenses is the one producer")
	check(oracle.contains("push_error("),
		"an unbound topic is a loud error, not a silent fallback")
	var organs: String = _code(_read("res://scripts/core/senses.gd"))
	check(organs.contains("func poll("), "HexySenses polls its own doors")
	check(organs.contains("sample_imu"),
		"and it is the one that publishes halteres")


func _test_the_seam_exists() -> void:
	print("\n[ the seam ffbrain is allowed to have ]")
	var brain_text: String = _code(_read("res://scripts/brain/fly_brain.gd"))
	check(brain_text.contains("func attach_bus("), "the fly brain takes a bus")
	check(brain_text.contains("func route_sense("), "and routes a sense by organ")
	var ch_text: String = _code(_read("res://scripts/brain/character.gd"))
	check(ch_text.contains("HexyMsg.body_from_fly_state"), "the organism builds a Body msg")
	check(ch_text.contains("\"/phase\"") or ch_text.contains("BUS_TOPIC_PHASE"),
		"and a Phase msg")


# -- reading the tree --------------------------------------------------------

static func _allowed(path: String) -> bool:
	for ok in SETTER_ALLOWED:
		if path.begins_with(ok):
			return true
	return false


## True when `line` uses `name` as a word, not as a piece of a longer one.
static func _names(line: String, name: String) -> bool:
	var at: int = line.find(name)
	while at >= 0:
		var before: String = line.substr(at - 1, 1) if at > 0 else " "
		var after_at: int = at + name.length()
		var after: String = line.substr(after_at, 1) if after_at < line.length() else " "
		var word_before: bool = before.is_valid_identifier() or before == "_"
		var word_after: bool = after.is_valid_identifier() or after == "_"
		if not word_before and not word_after:
			return true
		at = line.find(name, at + 1)
	return false


static func _scan(roots: Array) -> Array[String]:
	var out: Array[String] = ([] as Array[String])
	for root in roots:
		_walk(String(root), out)
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


static func _code(text: String) -> String:
	return "\n".join(_code_lines(text))


## Every line that is not a comment.
static func _code_lines(text: String) -> Array[String]:
	var out: Array[String] = ([] as Array[String])
	for raw in text.split("\n"):
		var line: String = String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return out
