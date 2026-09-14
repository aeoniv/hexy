class_name Consents
extends RefCounted

## THE CONSENT STORE. Ported from ix64-hexy's Phase 9.7.
##
## A stored answer PERSISTS: a consent switched off must stay off across a
## restart, and a stored `true` buys nothing on its own — every sensor this
## file gates still asks its own OS permission dialog and its own runtime
## gate before it opens anything.
##
## WHAT IS IN THE FILE, EXHAUSTIVELY: four booleans and nothing else. No
## timestamps, no device id, no history of switching.
## `user://consents.json`, plain JSON, rewritten whole on every change.
##
## IT NEVER CROSSES THE WIRE. Nothing in this file, and nothing that reads
## it, may put a consent on a signal, a mesh event or a socket.
##
## PURE AND STATIC, so the whole of it is drivable in a test with `set_path`
## and no scene tree, no node and no app.
##
## PERSISTENCE NOTE — this writes synchronously on every [method remember]
## rather than debouncing like [HexyConfig] does (see `scripts/core/config.gd`
## for that pattern). A consent toggle is a deliberate, rare tap — not a
## slider dragged across its range — so there is no burst of writes to
## collapse, and a debounce would only add a window where a crash right after
## toggling a switch to OFF could lose exactly the answer this file exists to
## keep. [Broker] (`scripts/core/broker.gd`), whose state can change several
## times a second, uses the debounced pattern instead.

## The four switches. The strings are the file's keys and the app's names for
## them, deliberately the same: a rename that changed one and not the other
## would silently forget a person's NO.
const VOICE := "voice"
const VISION := "vision"
const BODY := "body"
const AGENT := "agent"
const KEYS := [VOICE, VISION, BODY, AGENT]

const PATH := "user://consents.json"

## Overridable so a test writes into its own file and never touches the
## profile of whoever is running the suite. Static, like everything else here.
static var _path := PATH


static func set_path(p: String) -> void:
	_path = p if p != "" else PATH


static func path() -> String:
	return _path


## Everything on disk, as {key: bool}. An unreadable, absent or corrupt file is
## an EMPTY dictionary and never an error: a profile that failed to parse must
## fall back to the defaults, not to a crash on the first frame of the app.
static func load_all() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return {}
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out := {}
	for k: Variant in (parsed as Dictionary):
		var key := String(k)
		if not KEYS.has(key):
			# A key this build does not know is DROPPED rather than carried.
			continue
		out[key] = bool((parsed as Dictionary)[k])
	return out


## What was saved for one switch, or `null` when nothing ever was. `null` and
## not `false`, because "never asked" and "said no" are different answers.
static func saved(key: String) -> Variant:
	var all := load_all()
	if not all.has(key):
		return null
	return bool(all[key])


## THE ONE READ THE APP MAKES. The saved answer if there is one, the build's
## default if there is not.
static func resolve(key: String, fallback: bool) -> bool:
	var s: Variant = saved(key)
	if s == null:
		return fallback
	return bool(s)


## THE ONE WRITE. Called from the seams that already own each switch, on every
## change and only on a change. Returns whether the file was actually written.
static func remember(key: String, on: bool) -> bool:
	if not KEYS.has(key):
		return false
	var all := load_all()
	all[key] = on
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		print("consents: could not write ", _path)
		return false
	f.store_string(JSON.stringify(all, "  "))
	f.close()
	return true


## Forget everything. Not wired to any button — it exists so a test can start
## from a phone that has never been consented on.
static func clear() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
