extends SceneTree
## Q6 IS PURE: nothing under res://scripts/logic/q6/ may reach outside it.
##
## Two ways a file reaches another file, both checked over every file in the
## folder (any depth, any extension Godot keeps as text):
##   1. a "res://..." path literal (preload, load, extends "res://...",
##      ext_resource) that does not start with res://scripts/logic/q6/;
##   2. a bare global class_name (ProjectSettings global class list) used in
##      code whose script lives outside res://scripts/logic/q6/ -- the way the
##      frozen source tangled q6 with brain without one res:// string.
## A negative control proves each detector fires before trusting its silence.

const ROOT: String = "res://scripts/logic/q6/"
const TEXT_EXT: PackedStringArray = ["gd", "tscn", "tres", "json", "cfg", "gdshader", "txt"]

var failed: bool = false
var _path_re: RegEx = RegEx.new()
var _ident_re: RegEx = RegEx.new()
var _string_re: RegEx = RegEx.new()
var _outside_classes: Dictionary = {}


func _initialize() -> void:
	_path_re.compile("res://[^\"'\\s)\\]]*")
	_ident_re.compile("\\b[A-Z][A-Za-z0-9_]*\\b")
	_string_re.compile("\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'")
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = String(entry.get("path", ""))
		if not path.begins_with(ROOT):
			_outside_classes[String(entry.get("class", ""))] = path

	# Negative controls: each detector must fire on a known-bad line.
	check(not _bad_paths("const B = preload(\"res://scripts/logic/brain/brain.gd\")").is_empty(),
		"control: a res:// path outside q6 is caught")
	check(_bad_paths("const L = preload(\"res://scripts/logic/q6/q6_lattice.gd\")").is_empty(),
		"control: a res:// path inside q6 is allowed")
	var fake: Dictionary = _outside_classes.duplicate()
	fake["OutsideThing"] = "res://scripts/logic/brain/outside.gd"
	check(not _bad_classes("var x = OutsideThing.new()  # OutsideThing", fake).is_empty(),
		"control: a bare global class from outside q6 is caught")
	check(_bad_classes("# OutsideThing only in a comment\nvar s = \"OutsideThing\"", fake).is_empty(),
		"control: names in comments and strings are not loads")

	var files: PackedStringArray = PackedStringArray()
	_walk(ROOT, files)
	check(files.size() > 0 and files.has(ROOT + "q6.gd"), "scanned %d files under %s" % [files.size(), ROOT])
	for f: String in files:
		var text: String = FileAccess.get_file_as_string(f)
		var paths: PackedStringArray = _bad_paths(text)
		check(paths.is_empty(), "%s loads no res:// path outside q6 %s" % [f, str(paths) if not paths.is_empty() else ""])
		if f.ends_with(".gd"):
			var classes: PackedStringArray = _bad_classes(text, _outside_classes)
			check(classes.is_empty(), "%s names no global class outside q6 %s" % [f, str(classes) if not classes.is_empty() else ""])
	quit(1 if failed else 0)


func _bad_paths(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for m: RegExMatch in _path_re.search_all(text):
		var p: String = m.get_string()
		if not p.begins_with(ROOT):
			out.append(p)
	return out


func _bad_classes(text: String, outside: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for raw: String in text.split("\n"):
		var code: String = _string_re.sub(raw, "\"\"", true)
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		for m: RegExMatch in _ident_re.search_all(code):
			var name: String = m.get_string()
			if outside.has(name) and not out.has(name):
				out.append(name)
	return out


func _walk(dir_path: String, found: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_walk(dir_path.path_join(sub) + "/", found)
	for file: String in dir.get_files():
		if TEXT_EXT.has(file.get_extension()):
			found.append(dir_path.path_join(file) if not dir_path.ends_with("/") else dir_path + file)


func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed = true
