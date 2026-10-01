extends SceneTree
## PARITY LEDGER: tests/parity/parity.json accounts for every GREEN test of
## the frozen source (seeded from sdlc/hexy/baseline.json by
## tools/parity_seed.py), and every test here is accounted for by it.
##
## FAIL when
##   - the ledger is missing, unreadable, or its entry count differs from
##     frozen_green, or a frozen file appears twice;
##   - an entry is malformed: frozen not "tests/<x>.gd", tech unknown, status
##     not ported|deferred|dropped|todo, an unknown key, `here` on a non-ported
##     entry, `reason` on a ported/todo entry;
##   - a ported entry's `here` is not a runner-collected test path or the file
##     does not exist;
##   - a deferred/dropped entry has no reason;
##   - a test file the runner would collect (tests/**/test_*.gd,
##     tests/acceptance/*.gd) is named by no ported entry -- except the guard
##     tests themselves and test_ring.
## `todo` never fails. Whether a ported test is GREEN is the runner's job:
## nothing is run from here.
## Negative controls prove each detector fires before trusting its silence.

const LEDGER: String = "res://tests/parity/parity.json"
const TESTS_ROOT: String = "res://tests"
const ACCEPTANCE_DIR: String = "res://tests/acceptance"
const STATUSES: PackedStringArray = ["ported", "deferred", "dropped", "todo"]
const TECHS: PackedStringArray = ["senses", "brain", "q6", "voice", "mesh", "journal", "shell", "other"]
const KEYS: PackedStringArray = ["frozen", "tech", "status", "here", "reason"]
## Tests that belong to this repo, not to the frozen source.
const OWN: PackedStringArray = [
	"res://tests/test_parity.gd",
	"res://tests/test_layers.gd",
	"res://tests/test_q6_pure.gd",
	"res://tests/test_ring.gd",
]

var failed: bool = false


func _initialize() -> void:
	_controls()

	var text: String = FileAccess.get_file_as_string(LEDGER)
	var doc: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not (doc is Dictionary and doc.get("entries") is Array):
		check(false, "%s parses to {entries: [...]}" % LEDGER)
		quit(1)
		return
	var entries: Array = doc["entries"]
	var total: int = int(doc.get("frozen_green", -1))
	check(total > 0 and entries.size() == total,
		"ledger holds %d entries for frozen_green %d" % [entries.size(), total])

	var counts: Dictionary = {"ported": 0, "deferred": 0, "dropped": 0, "todo": 0}
	var seen: Dictionary = {}
	var claimed: Dictionary = {}
	var bad: int = 0
	for e: Variant in entries:
		var errs: PackedStringArray = _entry_errors(e, func(p: String) -> bool: return FileAccess.file_exists(p))
		var frozen: String = String(e.get("frozen", "?")) if e is Dictionary else "?"
		if e is Dictionary and seen.has(frozen):
			errs.append("duplicate frozen file")
		seen[frozen] = true
		if not errs.is_empty():
			bad += 1
			check(false, "%s: %s" % [frozen, ", ".join(errs)])
			continue
		counts[e["status"]] += 1
		if e["status"] == "ported":
			claimed["res://" + String(e["here"])] = true
	check(bad == 0, "every ledger entry is well formed (%d bad)" % bad)

	var files: PackedStringArray = _collect()
	var orphans: PackedStringArray = _orphans(files, claimed)
	check(orphans.is_empty(), "every test here is named by a ported entry (%d collected) %s" % [
		files.size(), str(orphans) if not orphans.is_empty() else ""])

	check(true, "parity: ported %d · deferred %d · dropped %d · todo %d of %d" % [
		counts.ported, counts.deferred, counts.dropped, counts.todo, total])
	quit(1 if failed else 0)


## Problems with one entry; `exists` answers whether a res:// file exists.
func _entry_errors(e: Variant, exists: Callable) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if not e is Dictionary:
		errs.append("not an object")
		return errs
	for k: Variant in e.keys():
		if not KEYS.has(String(k)):
			errs.append("unknown key %s" % k)
	var frozen: Variant = e.get("frozen")
	if not (frozen is String and frozen.begins_with("tests/") and frozen.ends_with(".gd")):
		errs.append("frozen must be \"tests/<x>.gd\"")
	if not (e.get("tech") is String and TECHS.has(e.get("tech"))):
		errs.append("tech %s not in %s" % [e.get("tech"), TECHS])
	var status: Variant = e.get("status")
	if not (status is String and STATUSES.has(status)):
		errs.append("status %s not in %s" % [status, STATUSES])
		return errs
	var reason: Variant = e.get("reason")
	if status == "ported":
		var here: Variant = e.get("here")
		if not (here is String and _is_runner_test("res://" + here)):
			errs.append("ported needs here = a runner-collected test path, got %s" % here)
		elif not exists.call("res://" + here):
			errs.append("here %s does not exist" % here)
	elif e.has("here"):
		errs.append("here only on ported")
	if status == "deferred" or status == "dropped":
		if not (reason is String and not reason.strip_edges().is_empty()):
			errs.append("%s needs a reason" % status)
	elif e.has("reason"):
		errs.append("reason only on deferred/dropped")
	return errs


func _orphans(files: PackedStringArray, claimed: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: String in files:
		if not OWN.has(f) and not claimed.has(f):
			out.append(f)
	return out


## Same rule as tools/run_tests.gd: tests/**/test_*.gd and tests/acceptance/*.gd.
func _is_runner_test(path: String) -> bool:
	if not (path.begins_with(TESTS_ROOT + "/") and path.ends_with(".gd")):
		return false
	return path.get_file().begins_with("test_") or path.get_base_dir() == ACCEPTANCE_DIR


func _collect() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	_walk(TESTS_ROOT, found)
	found.sort()
	return found


func _walk(dir_path: String, found: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_walk(dir_path.path_join(sub), found)
	for file: String in dir.get_files():
		var full: String = dir_path.path_join(file)
		if _is_runner_test(full):
			found.append(full)


func _controls() -> void:
	var yes: Callable = func(_p: String) -> bool: return true
	var no: Callable = func(_p: String) -> bool: return false
	check(_entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "todo"}, yes).is_empty(),
		"control: a plain todo entry is well formed")
	check(_entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "ported",
		"here": "tests/q6/test_a.gd"}, yes).is_empty(), "control: a ported entry with an existing here is well formed")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "ported",
		"here": "tests/q6/test_a.gd"}, no).is_empty(), "control: ported with a missing here file is caught")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "ported"}, yes).is_empty(),
		"control: ported without here is caught")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "ported",
		"here": "tests/q6/helper.gd"}, yes).is_empty(), "control: here outside the runner's patterns is caught")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "deferred"}, yes).is_empty(),
		"control: deferred without reason is caught")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "dropped", "reason": "  "}, yes).is_empty(),
		"control: dropped with a blank reason is caught")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "done"}, yes).is_empty(),
		"control: an unknown status is caught")
	check(not _entry_errors({"frozen": "a.gd", "tech": "q6", "status": "todo"}, yes).is_empty(),
		"control: a frozen path outside tests/ is caught")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "x", "status": "todo"}, yes).is_empty(),
		"control: an unknown tech is caught")
	check(not _entry_errors({"frozen": "tests/a.gd", "tech": "q6", "status": "todo", "note": 1}, yes).is_empty(),
		"control: an unknown key is caught")
	var orphans: PackedStringArray = _orphans(PackedStringArray([
		"res://tests/q6/test_a.gd", "res://tests/q6/test_b.gd", "res://tests/test_ring.gd"]),
		{"res://tests/q6/test_a.gd": true})
	check(orphans == PackedStringArray(["res://tests/q6/test_b.gd"]),
		"control: an unclaimed test file is caught, own guard tests are not")


func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed = true
