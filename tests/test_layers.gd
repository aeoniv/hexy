extends SceneTree
## LAYERS: each of the six techs loads only what the table allows; the shell
## may load all six; no tech loads the shell.
##
##   tech     folders                                        may load
##   senses   scripts/logic/senses/, addons/                 --
##   brain    scripts/logic/brain/                           q6
##   q6       scripts/logic/q6/                              --
##   voice    scripts/logic/voice/                           q6, brain
##   mesh     scripts/logic/mesh/                            journal
##   journal  scripts/logic/journal/                         q6
##   shell    ui/, scenes/, scripts/integration/             all six (and anything else)
## A layer always may load its own folders. For the six techs anything not in
## the table -- the shell, tools/, tests/, a stray res:// folder, an unknown
## uid -- is forbidden (the rule test_q6_pure.gd enforces for q6, applied to all).
##
## Every text file under a layer's folders is scanned (any depth). Four ways a
## file reaches another file:
##   1. a "res://..." literal anywhere (preload, load, extends, ext_resource,
##      or a plain string/comment -- deliberately strict, as test_q6_pure);
##   2. a "uid://..." literal, resolved through the project's *.uid files and
##      the uid="" headers of .tscn/.tres;
##   3. a relative path in preload("..")/load("..")/extends ".." resolved
##      against the file's folder;
##   4. (.gd only) a bare global class_name used in code -- outside comments and
##      strings -- whose script lives in a forbidden layer.
## Negative controls prove each detector and the table fire before trusting
## their silence.

const TEXT_EXT: PackedStringArray = ["gd", "tscn", "tres", "json", "cfg", "gdshader", "txt"]
const ROOTS: Dictionary = {
	"senses": ["res://scripts/logic/senses/", "res://addons/"],
	"brain": ["res://scripts/logic/brain/"],
	"q6": ["res://scripts/logic/q6/"],
	"voice": ["res://scripts/logic/voice/"],
	"mesh": ["res://scripts/logic/mesh/"],
	"journal": ["res://scripts/logic/journal/"],
	"shell": ["res://ui/", "res://scenes/", "res://scripts/integration/"],
}
const MAY_LOAD: Dictionary = {
	"senses": [],
	"brain": ["q6"],
	"q6": [],
	"voice": ["q6", "brain"],
	"mesh": ["journal"],
	"journal": ["q6"],
	"shell": ["senses", "brain", "q6", "voice", "mesh", "journal"],
}
const SIX: PackedStringArray = ["senses", "brain", "q6", "voice", "mesh", "journal"]

var failed: bool = false
var _path_re: RegEx = RegEx.new()
var _uid_re: RegEx = RegEx.new()
var _rel_re: RegEx = RegEx.new()
var _ident_re: RegEx = RegEx.new()
var _string_re: RegEx = RegEx.new()
var _header_uid_re: RegEx = RegEx.new()
var _classes: Dictionary = {}   # class_name -> script path
var _uids: Dictionary = {}      # "uid://x" -> res:// path


func _initialize() -> void:
	_path_re.compile("res://[^\"'\\s)\\]]*")
	_uid_re.compile("uid://[a-z0-9]+")
	_rel_re.compile("(?:\\bpreload|\\bload)\\s*\\(\\s*[\"']([^\"']+)[\"']|\\bextends\\s+[\"']([^\"']+)[\"']")
	_ident_re.compile("\\b[A-Z][A-Za-z0-9_]*\\b")
	_string_re.compile("\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'")
	_header_uid_re.compile("^\\[gd_(?:scene|resource)[^\\]]*\\buid=\"(uid://[a-z0-9]+)\"")
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_classes[String(entry.get("class", ""))] = String(entry.get("path", ""))
	_index_uids("res://")

	_controls()

	check(_classes.has("Q6Core") and _owner(_classes["Q6Core"]) == "q6",
		"global class list is loaded (Q6Core lives in q6)")
	check(_uids.size() > 0, "uid index built (%d uids)" % _uids.size())
	for layer: String in ROOTS:
		var files: PackedStringArray = PackedStringArray()
		for root: String in ROOTS[layer]:
			_walk(root, files)
		check(files.size() > 0, "%s: scanned %d files" % [layer, files.size()])
		var bad_files: int = 0
		for f: String in files:
			var bad: PackedStringArray = _violations(layer, f, FileAccess.get_file_as_string(f))
			if not bad.is_empty():
				bad_files += 1
				check(false, "%s (%s) loads forbidden %s" % [f, layer, str(bad)])
		check(bad_files == 0, "%s loads only itself + %s" % [layer, str(MAY_LOAD[layer])])
	quit(1 if failed else 0)


## Which layer owns a res:// path ("" = none). Longest root wins.
func _owner(path: String) -> String:
	var best: String = ""
	var best_len: int = -1
	for layer: String in ROOTS:
		for root: String in ROOTS[layer]:
			if path.begins_with(root) and root.length() > best_len:
				best = layer
				best_len = root.length()
	return best


func _allowed(layer: String, target: String) -> bool:
	var owner: String = _owner(target)
	if owner == layer:
		return true
	if layer == "shell":
		return true  # the shell may load all six and anything outside the techs
	return owner != "" and MAY_LOAD[layer].has(owner)


## Forbidden targets reached by `text`, a file at `file_path` in `layer`.
func _violations(layer: String, file_path: String, text: String, classes: Dictionary = {}) -> PackedStringArray:
	if classes.is_empty():
		classes = _classes
	var out: PackedStringArray = PackedStringArray()
	for m: RegExMatch in _path_re.search_all(text):
		_flag(layer, m.get_string(), m.get_string(), out)
	for m: RegExMatch in _uid_re.search_all(text):
		var uid: String = m.get_string()
		_flag(layer, String(_uids.get(uid, "")), uid + " (unresolved)" if not _uids.has(uid) else uid + " -> " + String(_uids[uid]), out)
	for m: RegExMatch in _rel_re.search_all(text):
		var p: String = m.get_string(1) if not m.get_string(1).is_empty() else m.get_string(2)
		if p.begins_with("res://") or p.begins_with("uid://") or p.begins_with("user://"):
			continue
		var abs_path: String = file_path.get_base_dir().path_join(p).simplify_path()
		_flag(layer, abs_path, "%s -> %s" % [p, abs_path], out)
	if file_path.ends_with(".gd"):
		for raw: String in text.split("\n"):
			var code: String = _string_re.sub(raw, "\"\"", true)
			var hash_at: int = code.find("#")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			for m: RegExMatch in _ident_re.search_all(code):
				var name: String = m.get_string()
				if classes.has(name):
					_flag(layer, String(classes[name]), "class %s (%s)" % [name, classes[name]], out)
	return out


func _flag(layer: String, target: String, label: String, out: PackedStringArray) -> void:
	if (target.is_empty() or not _allowed(layer, target)) and not out.has(label):
		out.append(label)


func _index_uids(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_index_uids(dir_path.path_join(sub))
	for file: String in dir.get_files():
		var full: String = dir_path.path_join(file)
		if file.ends_with(".uid"):
			_uids[FileAccess.get_file_as_string(full).strip_edges()] = full.trim_suffix(".uid")
		elif file.ends_with(".tscn") or file.ends_with(".tres"):
			var f: FileAccess = FileAccess.open(full, FileAccess.READ)
			if f != null:
				var m: RegExMatch = _header_uid_re.search(f.get_line())
				if m != null:
					_uids[m.get_string(1)] = full


func _walk(dir_path: String, found: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_walk(dir_path.path_join(sub), found)
	for file: String in dir.get_files():
		if TEXT_EXT.has(file.get_extension()):
			found.append(dir_path.path_join(file))


func _controls() -> void:
	# The table.
	check(_allowed("voice", "res://scripts/logic/brain/brain.gd") and _allowed("voice", "res://scripts/logic/q6/q6.gd"),
		"control: voice may load brain and q6")
	check(not _allowed("brain", "res://scripts/logic/voice/voice.gd"), "control: brain may not load voice")
	check(not _allowed("q6", "res://scripts/logic/brain/brain.gd"), "control: q6 may not load brain")
	check(_allowed("senses", "res://addons/x/plugin.gd"), "control: senses owns addons/")
	check(not _allowed("journal", "res://addons/x/plugin.gd"), "control: journal may not load addons/ (senses)")
	var no_tech_loads_shell: bool = true
	for t: String in SIX:
		for r: String in ROOTS["shell"]:
			no_tech_loads_shell = no_tech_loads_shell and not _allowed(t, r + "x.gd")
	check(no_tech_loads_shell, "control: no tech may load any shell folder")
	var shell_loads_all: bool = true
	for t: String in SIX:
		shell_loads_all = shell_loads_all and _allowed("shell", ROOTS[t][0] + "x.gd")
	check(shell_loads_all, "control: shell may load all six")
	check(not _allowed("mesh", "res://tools/run_tests.gd"), "control: a tech may not load outside the table")
	# Detector 1: res:// literals.
	var f_mesh: String = "res://scripts/logic/mesh/m.gd"
	check(not _violations("mesh", f_mesh, "const B = preload(\"res://scripts/logic/brain/brain.gd\")").is_empty(),
		"control: res:// to a forbidden tech is caught")
	check(_violations("mesh", f_mesh, "const J = preload(\"res://scripts/logic/journal/journal.gd\")").is_empty(),
		"control: res:// to an allowed tech passes")
	check(not _violations("q6", "res://scripts/logic/q6/a.tscn",
		"[ext_resource type=\"Script\" path=\"res://scenes/x.gd\" id=\"1\"]").is_empty(),
		"control: a .tscn ext_resource into the shell is caught")
	# Detector 2: uid:// literals.
	var brain_uid: String = FileAccess.get_file_as_string("res://scripts/logic/brain/brain.gd.uid").strip_edges()
	check(brain_uid.begins_with("uid://") and not _violations("q6", "res://scripts/logic/q6/a.tscn",
		"[ext_resource type=\"Script\" uid=\"%s\" id=\"1\"]" % brain_uid).is_empty(),
		"control: a uid:// resolving to a forbidden tech is caught")
	check(_violations("voice", "res://scripts/logic/voice/a.tscn",
		"[ext_resource type=\"Script\" uid=\"%s\" id=\"1\"]" % brain_uid).is_empty(),
		"control: a uid:// resolving to an allowed tech passes")
	check(not _violations("q6", "res://scripts/logic/q6/a.tscn", "uid=\"uid://zzzznotreal\"").is_empty(),
		"control: an unresolved uid:// in a tech is caught")
	# Detector 3: relative paths.
	check(not _violations("q6", "res://scripts/logic/q6/a.gd", "const B = preload(\"../brain/brain.gd\")").is_empty(),
		"control: a relative preload escaping the folder is caught")
	check(_violations("q6", "res://scripts/logic/q6/a.gd", "const L = preload(\"q6_lattice.gd\")").is_empty(),
		"control: a relative preload inside the folder passes")
	check(not _violations("journal", "res://scripts/logic/journal/a.gd", "extends \"../../integration/ring.gd\"").is_empty(),
		"control: a relative extends into the shell is caught")
	# Detector 4: global class_name.
	var fake: Dictionary = _classes.duplicate()
	fake["BrainThing"] = "res://scripts/logic/brain/thing.gd"
	fake["ShellThing"] = "res://ui/thing.gd"
	check(not _violations("q6", "res://scripts/logic/q6/a.gd", "var x = BrainThing.new()", fake).is_empty(),
		"control: a global class from a forbidden tech is caught")
	check(_violations("voice", "res://scripts/logic/voice/a.gd", "var x = BrainThing.new()", fake).is_empty(),
		"control: a global class from an allowed tech passes")
	check(not _violations("senses", "res://addons/x/a.gd", "extends ShellThing", fake).is_empty(),
		"control: extends a shell class_name is caught")
	check(_violations("q6", "res://scripts/logic/q6/a.gd",
		"# BrainThing only in a comment\nvar s = \"BrainThing\"", fake).is_empty(),
		"control: class names in comments and strings are not loads")


func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed = true
