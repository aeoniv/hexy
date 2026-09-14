extends SceneTree

## CONSENTS SMOKE — scripts/core/consents.gd. Driven through a suite-local
## path so it never touches the profile of whoever runs the suite.
## Prints === ALL PASS === or fails.

const SUITE_PATH := "user://consents_smoke_test.json"

var _fails := 0
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		_fails += 1


func _initialize() -> void:
	Consents.set_path(SUITE_PATH)
	Consents.clear()

	_never_asked_is_null()
	_resolve_falls_back()
	_remember_round_trips()
	_unknown_key_is_ignored()
	_no_timestamps_no_device_id_no_history()
	_clear_forgets()

	Consents.clear()
	Consents.set_path("")
	_check(Consents.path() == Consents.PATH, "set_path('') restores the default path")

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


func _never_asked_is_null() -> void:
	_check(Consents.saved(Consents.VOICE) == null,
		"a switch never written to is null, not false")
	_check(Consents.load_all().is_empty(),
		"a fresh path has no saved consents at all")


func _resolve_falls_back() -> void:
	_check(Consents.resolve(Consents.VISION, true) == true,
		"resolve() falls back to the caller's default when unsaved")
	_check(Consents.resolve(Consents.VISION, false) == false,
		"resolve() honours whichever default the caller passes")


func _remember_round_trips() -> void:
	_check(Consents.remember(Consents.BODY, false) == true,
		"remember() reports a successful write")
	_check(Consents.saved(Consents.BODY) == false,
		"a stored NO round-trips as false, not as absence")
	_check(Consents.resolve(Consents.BODY, true) == false,
		"resolve() prefers the stored NO over the caller's default")
	_check(Consents.remember(Consents.AGENT, true) == true,
		"remember() also stores a YES")
	_check(Consents.saved(Consents.AGENT) == true,
		"a stored YES round-trips as true")


func _unknown_key_is_ignored() -> void:
	_check(Consents.remember("not_a_real_switch", true) == false,
		"remember() refuses a key outside KEYS")
	_check(Consents.saved("not_a_real_switch") == null,
		"an unknown key never appears as saved")


## THE GREP: the file must hold only the four keys, and nothing that looks
## like a timestamp, a device id or a history of changes.
func _no_timestamps_no_device_id_no_history() -> void:
	var f := FileAccess.open(Consents.path(), FileAccess.READ)
	_check(f != null, "the consents file exists on disk after writes")
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	for forbidden in ["timestamp", "time", "device_id", "history", "uuid"]:
		_check(not raw.to_lower().contains(forbidden),
			"the consents file does not contain '%s'" % forbidden)
	var all := Consents.load_all()
	for k: String in all.keys():
		_check(Consents.KEYS.has(k), "every key on disk is one of the four switches")


func _clear_forgets() -> void:
	Consents.clear()
	_check(Consents.saved(Consents.BODY) == null,
		"clear() forgets a previously stored NO")
	_check(not FileAccess.file_exists(Consents.path()),
		"clear() removes the file from disk")
