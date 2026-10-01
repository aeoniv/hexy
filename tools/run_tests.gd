extends SceneTree
## Headless test runner for Hexy.
##
## Run (from the project folder):
##   godot --headless --path . --import            # once, builds .godot/
##   godot --headless --path . -s res://tools/run_tests.gd [-- <filter> ...]
## or the thin wrappers tools/run_tests.sh / tools/run_tests.ps1.
## Filters are substrings; a file runs when its res:// path contains any one.
##
## WHICH FILES RUN
##   res://tests/**/test_*.gd       (any depth)
##   res://tests/acceptance/*.gd    (every script in that folder)
## Nothing else under tests/ is run: helpers, fixtures and golden data may sit
## beside the tests freely. No tests/ folder, or no matching file, prints
## "0 tests" and exits 0.
##
## THE CONTRACT A TEST FILE FOLLOWS
## It is the shape of the frozen source's tests (D:/GitHub/hexy/tests), so a
## ported test runs unchanged:
##   1. `extends SceneTree` (or MainLoop) and does its work from _initialize().
##      Each file runs in its OWN Godot process:
##        godot --headless --path <project> -s res://tests/.../test_x.gd
##   2. One line per check on stdout, starting with the word PASS or FAIL:
##        print("PASS: ", label)    /    print("FAIL: ", label)
##      ("PASS " and "FAIL " without the colon count too.)
##   3. It ends with quit(0) when every check held and a non-zero quit
##      otherwise. It must quit: a file that never quits hangs the run.
## A file PASSES only when its exit code is 0, it printed no FAIL line, and
## Godot printed no "SCRIPT ERROR" / "Parse Error" for it. n/n counts its
## PASS lines over PASS+FAIL lines. Each file's full output is written to
## build/test-logs/<path with / as __>.log.
##
## OUTPUT: one line per file, then a total, e.g.
##   PASS 12/12  res://tests/test_ring.gd
##   FAIL 3/4    res://tests/acceptance/ac_sixg1.gd  (exit 1)
##   TOTAL 1/2 files passed, 15/16 checks -- FAIL
## Exit code: 0 when every file passed, 1 otherwise.
##
## TIMEOUT: files run strictly one after another (each child is waited on
## before the next starts, so frozen-source tests never fight over network
## ports). A file gets 120 s of wall time; set HEXY_TEST_TIMEOUT=<seconds> to
## change it. On timeout the child is killed, the file counts as a failure and
## the run continues:
##   FAIL 0/0    res://tests/test_hang.gd  (timeout 120s)
## Child output goes to the log via Godot's --log-file (readable even after a
## kill); the runner polls OS.is_process_running instead of blocking.

const TESTS_ROOT: String = "res://tests"
const ACCEPTANCE_DIR: String = "res://tests/acceptance"
const LOG_DIR: String = "res://build/test-logs"
const DEFAULT_TIMEOUT_S: int = 120
const POLL_MS: int = 50


func _initialize() -> void:
	var filters: PackedStringArray = OS.get_cmdline_user_args()
	var files: PackedStringArray = _collect()
	var chosen: PackedStringArray = PackedStringArray()
	for f: String in files:
		if filters.is_empty() or _matches(f, filters):
			chosen.append(f)

	if chosen.is_empty():
		print("0 tests")
		quit(0)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	var exe: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")

	var timeout_s: int = DEFAULT_TIMEOUT_S
	var env_timeout: String = OS.get_environment("HEXY_TEST_TIMEOUT").strip_edges()
	if env_timeout.is_valid_int() and env_timeout.to_int() > 0:
		timeout_s = env_timeout.to_int()

	var files_passed: int = 0
	var checks_passed: int = 0
	var checks_total: int = 0
	for path: String in chosen:
		var log_path: String = ProjectSettings.globalize_path(LOG_DIR.path_join(_log_name(path)))
		DirAccess.remove_absolute(log_path)
		var args: PackedStringArray = PackedStringArray([
			"--headless", "--path", project, "--log-file", log_path, "-s", path])
		var pid: int = OS.create_process(exe, args)
		var timed_out: bool = false
		var code: int = -1
		if pid > 0:
			var started: int = Time.get_ticks_msec()
			while OS.is_process_running(pid):
				if Time.get_ticks_msec() - started >= timeout_s * 1000:
					timed_out = true
					OS.kill(pid)
					break
				OS.delay_msec(POLL_MS)
			if not timed_out:
				code = OS.get_process_exit_code(pid)
			else:
				var waited: int = Time.get_ticks_msec()
				while OS.is_process_running(pid) and Time.get_ticks_msec() - waited < 5000:
					OS.delay_msec(POLL_MS)
		var text: String = ""
		if FileAccess.file_exists(log_path):
			text = FileAccess.get_file_as_string(log_path)

		var passes: int = 0
		var fails: int = 0
		var errors: int = 0
		for raw: String in text.split("\n"):
			var line: String = raw.strip_edges()
			if _is_mark(line, "PASS"):
				passes += 1
			elif _is_mark(line, "FAIL"):
				fails += 1
			if line.begins_with("SCRIPT ERROR") or line.contains("Parse Error"):
				errors += 1

		var n: int = passes + fails
		checks_passed += passes
		checks_total += n
		var ok: bool = not timed_out and pid > 0 and code == 0 and fails == 0 and errors == 0
		if ok:
			files_passed += 1
			print("PASS %d/%d  %s" % [passes, n, path])
		else:
			var why: String = "exit %d" % code
			if timed_out:
				why = "timeout %ds" % timeout_s
			elif pid <= 0:
				why = "could not start"
			if errors > 0:
				why += ", %d script error(s)" % errors
			print("FAIL %d/%d  %s  (%s)" % [passes, n, path, why])
			_print_tail(text)

	var all_ok: bool = files_passed == chosen.size()
	print("TOTAL %d/%d files passed, %d/%d checks -- %s" % [
		files_passed, chosen.size(), checks_passed, checks_total, "PASS" if all_ok else "FAIL"])
	quit(0 if all_ok else 1)


func _collect() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if DirAccess.dir_exists_absolute(TESTS_ROOT):
		_walk(TESTS_ROOT, found)
	found.sort()
	return found


func _walk(dir_path: String, found: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_walk(dir_path.path_join(sub), found)
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var full: String = dir_path.path_join(file)
		if file.begins_with("test_") or dir_path == ACCEPTANCE_DIR:
			if not found.has(full):
				found.append(full)


func _matches(path: String, filters: PackedStringArray) -> bool:
	for f: String in filters:
		if path.contains(f):
			return true
	return false


func _is_mark(line: String, word: String) -> bool:
	if line == word:
		return true
	return line.begins_with(word + ":") or line.begins_with(word + " ")


func _log_name(path: String) -> String:
	return path.trim_prefix("res://").replace("/", "__").trim_suffix(".gd") + ".log"


func _print_tail(text: String) -> void:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var start: int = maxi(0, lines.size() - 20)
	for i: int in range(start, lines.size()):
		print("    | ", lines[i])
