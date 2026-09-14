extends SceneTree
## THE HANDSHAKE, CHECKED WITHOUT A PHONE.
##
## Every seam that talks to an Android plugin carries `const REQUIRES :=
## "<plugin>/<n>"`, and `scripts/seam.gd` compares it with what the aar answers
## at attach. Nothing on desktop ever runs that comparison, so this smoke walks
## the scripts instead: the string must have the shape seam.gd can compare, the
## plugin half must name a module that actually exists under `android_plugin/`,
## the version half must be an integer, and the Kotlin side must declare the
## same string in its own `PLUGIN_VERSION`.
##
## The name is `REQUIRES` and not `NEEDS` on purpose: `NEEDS` is already the
## fly-brain's six need lines, and one word cannot mean both.

const SCRIPT_ROOT := "res://scripts"
const PLUGIN_ROOT := "res://android_plugin"

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		printerr("FAIL ", what)


func _initialize() -> void:
	print("\n--- PLUGIN VERSION HANDSHAKE SMOKE ---")
	var declarations := {}
	_walk(SCRIPT_ROOT, declarations)

	_check(not declarations.is_empty(), "at least one script declares REQUIRES")

	for path: String in declarations:
		var req: String = declarations[path]
		var parts := req.split("/")
		_check(parts.size() == 2, "%s: REQUIRES is <plugin>/<n>, got %s" % [path, req])
		if parts.size() != 2:
			continue
		var plugin := String(parts[0])
		var version := String(parts[1])
		_check(plugin != "", "%s: names a plugin" % path)
		_check(version.is_valid_int(), "%s: version half `%s` is an int" % [path, version])
		var dir := "%s/%s" % [PLUGIN_ROOT, plugin]
		_check(DirAccess.dir_exists_absolute(dir),
			"%s: `%s` is a real module at %s" % [path, plugin, dir])
		_check(_kotlin_declares(plugin, req),
			"%s: the %s Kotlin declares PLUGIN_VERSION = \"%s\"" % [path, plugin, req])

	# The one this milestone is about: the MNN seam skipped the handshake for
	# eleven versions, which is the exact silent failure it exists to name.
	var mnn := "res://scripts/brain/mnn_runtime.gd"
	_check(declarations.has(mnn), "mnn_runtime declares REQUIRES")
	if declarations.has(mnn):
		_check(String(declarations[mnn]) == "ixmnn/2",
			"mnn_runtime requires ixmnn/2, got %s" % declarations[mnn])
	_check(MnnRuntime.REQUIRES == String(declarations.get(mnn, "")),
		"the constant the engine loads matches the source line")

	# And nothing anywhere may still spell it `NEEDS` at a plugin seam.
	var stale: Array[String] = []
	_walk_stale(SCRIPT_ROOT, stale)
	_check(stale.is_empty(), "no plugin seam still spells it NEEDS: %s" % str(stale))

	if _fails == 0:
		print("=== ALL PASS ===")
	print("--- PLUGIN VERSION SMOKE: %d failures ---\n" % _fails)
	quit(0 if _fails == 0 else 1)


## Every `res://scripts/**/*.gd` with a `const REQUIRES := "..."` line, mapped
## to the string it declares.
func _walk(dir_path: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(full, out)
		elif name.ends_with(".gd"):
			var req := _requires_of(full)
			if req != "":
				out[full] = req
		name = d.get_next()
	d.list_dir_end()


func _requires_of(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("const REQUIRES :=") or line.begins_with("const REQUIRES:="):
			var q := line.find("\"")
			var q2 := line.rfind("\"")
			if q >= 0 and q2 > q:
				return line.substr(q + 1, q2 - q - 1)
	return ""


## A seam that still calls its handshake `NEEDS` — the word the fly brain owns.
func _walk_stale(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk_stale(full, out)
		elif name.ends_with(".gd"):
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				while not f.eof_reached():
					var line := f.get_line().strip_edges()
					# A plugin handshake looks like `const NEEDS := "name/1"`.
					if line.begins_with("const NEEDS") and line.contains("/") \
							and line.contains("\""):
						out.append(full)
						break
		name = d.get_next()
	d.list_dir_end()


## True when the module's Kotlin carries the same version string.
func _kotlin_declares(plugin: String, req: String) -> bool:
	var root := "%s/%s/src/main/kotlin" % [PLUGIN_ROOT, plugin]
	return _grep(root, "PLUGIN_VERSION = \"%s\"" % req)


func _grep(dir_path: String, needle: String) -> bool:
	var d := DirAccess.open(dir_path)
	if d == null:
		return false
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if _grep(full, needle):
				d.list_dir_end()
				return true
		elif name.ends_with(".kt"):
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null and f.get_as_text().contains(needle):
				d.list_dir_end()
				return true
		name = d.get_next()
	d.list_dir_end()
	return false
