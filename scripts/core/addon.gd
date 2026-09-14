class_name HexyAddon
extends Node

## THE CONTRACT AN ADD-ON SIGNS, AND THE ONLY DOOR BASE OPENS FOR IT.
##
## An add-on exists only if it opens a HARDWARE DOOR and drives a FLY CIRCUIT
## or one of the six need lines. Those two answers -- [method door] and
## [method line] -- are the whole of its identity: everything else the loader
## does with an add-on it does by asking these.
##
## BASE NEVER LEARNS AN ADD-ON'S NAME. HexyAddons scans
## `res://addons/hexy_*/addon.gd`, builds whatever it finds, checks the
## manifest and hands it the bus. Nothing in scripts/ may name an add-on, and
## no add-on may name another: the only edge is add-on -> base.
##
## ONE STATE, STILL. An attached add-on writes through `store.note_seat`,
## `Character.feed` / `Character.reward_event` and `Config.set_value` -- never
## into a field of its own that somebody else then has to read. That is why
## `store.dump()` before an attach and after a detach must be the same
## dictionary, which is what tests/test_addon_bus.gd proves.

## THE FOUR CIRCUITS a door may drive instead of a need line. The six need
## lines are 0..5 (Character.LINE_BODY .. LINE_CONNECTION); these start at ten
## so no reader can mistake one kind of index for the other.
const CIRCUIT_COMPASS: int = 10
const CIRCUIT_MUSHROOM: int = 11
const CIRCUIT_GIANT_FIBER: int = 12
const CIRCUIT_CIRCADIAN: int = 13

## circuit id -> the word a panel prints for it.
const CIRCUIT_NAMES: Dictionary = {
	CIRCUIT_COMPASS: "compass",
	CIRCUIT_MUSHROOM: "mushroom",
	CIRCUIT_GIANT_FIBER: "giant_fiber",
	CIRCUIT_CIRCADIAN: "circadian",
}

## The six need lines, by index, as Character names them. Carried here so a
## panel may print the rows without loading the brain.
const NEED_NAMES: Array[String] = [
	"body", "food", "breath", "rest", "focus", "connection",
]


# -- the contract -------------------------------------------------------------

## THE HARDWARE DOOR, as the plugin that opens it is called: "ixbody",
## "ixvoice", "ixloc", "ixmesh". One door per plugin; an empty string is not a
## door and the loader will refuse it.
func door() -> String:
	return ""


## WHAT THIS DOOR FEEDS: a need line 0..5, or one of the CIRCUIT_* ids above.
## Anything else is not a line and the loader will refuse it.
func line() -> int:
	return -1


## Take the bus. `store` is the one HexyStore, `config` the live HexyConfig (or
## null when there is none), `bus` the small dictionary
## {store, character, alchemy} -- the seat bus, the homeostat and the walk.
func attach(_store: Object, _config: Object, _bus: Dictionary) -> void:
	pass


## Put everything back. After this the store must dump exactly what it dumped
## before the attach.
func detach() -> void:
	pass


## The tunables this add-on brings, keyed by NAMESPACED key ("body.min_confidence")
## and valued by a row in exactly the shape [method HexyConfig.schema] uses.
## HexyAddons hands the whole dictionary to [method HexyConfig.register].
func config_keys() -> Dictionary:
	return {}


## A face for the dashboard, or null when this add-on has nothing to draw.
func panel() -> Control:
	return null


## What this add-on calls itself. Defaults to the folder it was found in
## ("hexy_body"), which is the only name base ever knows it by.
func addon_name() -> String:
	var path: String = ""
	var s: Script = get_script() as Script
	if s != null:
		path = s.resource_path
	if path == "":
		return door()
	var folder: String = path.get_base_dir().get_file()
	return folder if folder != "" else door()


## The add-on's own version string. A loud mismatch beats a silent one.
func version() -> String:
	return "0"


## THE FOUR THINGS THE LOADER CHECKS. Built from the four methods above so an
## add-on cannot answer the manifest one way and the bus another.
func manifest() -> Dictionary:
	return {
		"name": addon_name(),
		"door": door(),
		"line": line(),
		"version": version(),
	}


# -- validity -----------------------------------------------------------------

## True for a need line 0..5 or one of the four circuit ids.
static func line_valid(l: int) -> bool:
	if l >= 0 and l < NEED_NAMES.size():
		return true
	return CIRCUIT_NAMES.has(l)


## The word for a line or circuit id, or "" when it is neither.
static func line_name(l: int) -> String:
	if l >= 0 and l < NEED_NAMES.size():
		return NEED_NAMES[l]
	return String(CIRCUIT_NAMES.get(l, ""))


## DOES THIS ADD-ON EXIST AT ALL? No door or no line means no add-on, and it
## says so out loud -- a silently ignored add-on is a phone that does nothing
## for a reason nobody can find.
func valid() -> bool:
	var ok: bool = true
	if door().strip_edges() == "":
		push_error("HexyAddon: %s opens no door (door() is empty)" % addon_name())
		ok = false
	if not line_valid(line()):
		push_error("HexyAddon: %s drives no line or circuit (line() = %d)"
			% [addon_name(), line()])
		ok = false
	return ok
