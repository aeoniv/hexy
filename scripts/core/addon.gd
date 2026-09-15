class_name HexyAddon
extends Node

## W8d -- THE ADD-ON CONTRACT: a modular FUNCTION, not a body part.
##
## An organ is base. An add-on is something bolted onto the organism from
## outside -- rig a camera, mesh in a djay, echo-locate a room, read csi
## sensors -- that opens doors through the broker, subscribes to organism
## topics, publishes Sense in and Act out, and may bring a view. OFF MEANS
## BASE UNCHANGED: `store.dump()` before an attach and after the matching
## detach must be the same dictionary, because everything an add-on may
## write goes through the bus, never into a field of its own.
##
## THE FOUR THINGS THE LOADER CHECKS, built from the methods below so an
## add-on cannot answer the manifest one way and the bus another:
##   - [method doors]  -- which broker doors this add-on may ever acquire.
##     Asking for one not on this list is refused by the wrapped broker
##     [HexyAddons] hands it in `attach`'s bus.
##   - [method reads]  -- which topics it subscribes to. Advisory: the
##     loader does not stop a subscribe, but a manifest that lies here is a
##     manifest a panel will draw wrong.
##   - [method writes] -- which topics it publishes on. Only "/sense",
##     "/sense/<door>" and "/act" are ever allowed; an add-on naming
##     anything else is refused outright at attach.
##
## BASE NEVER LEARNS AN ADD-ON'S NAME. `HexyAddons` scans
## `res://addons/hexy_*/addon.gd`; nothing in scripts/ may name an add-on and
## no add-on may name another -- the only edge is add-on -> base.

## THE THREE TOPICS AN ADD-ON MAY EVER WRITE. "/sense/<door>" is checked as a
## prefix of "/sense/", so a door-specific fan-out topic is allowed without
## the loader needing to know every door name in advance.
const WRITE_TOPICS := [HexyTopic.TOPIC_SENSE, HexyTopic.TOPIC_ACT]
const WRITE_PREFIX := "/sense/"


# -- the contract -------------------------------------------------------------

## THE BROKER DOORS this add-on may ever [method Broker.acquire]. Anything
## not named here is refused by the wrapped broker it is handed.
func doors() -> PackedStringArray:
	return PackedStringArray()


## THE TOPICS this add-on subscribes to.
func reads() -> PackedStringArray:
	return PackedStringArray()


## THE TOPICS this add-on publishes on. Only "/sense", "/sense/<door>" and
## "/act" are ever allowed -- see [const WRITE_TOPICS].
func writes() -> PackedStringArray:
	return PackedStringArray()


## A FACE FOR THE DASHBOARD, or null when this add-on has nothing to draw.
func view() -> Control:
	return null


## TAKE THE BUS. `bus` is {topic: HexyTopic, broker: Broker (wrapped so an
## undeclared door is refused), gauge: HexyGauge, consents: Consents (the
## static class itself), store: HexyStore (read only -- an add-on writes
## through Sense/Act, never through the store directly)}.
func attach(_bus: Dictionary) -> void:
	pass


## PUT EVERYTHING BACK: unsubscribe every topic, release every door. After
## this the add-on holds nothing and has said nothing new.
func detach() -> void:
	pass


## WHAT THIS ADD-ON CALLS ITSELF. Defaults to the folder it was found in
## ("hexy_example"), which is the only name base ever knows it by.
func addon_name() -> String:
	var path: String = ""
	var s: Script = get_script() as Script
	if s != null:
		path = s.resource_path
	if path == "":
		return ""
	var folder: String = path.get_base_dir().get_file()
	return folder


## THE ADD-ON'S OWN VERSION STRING. A loud mismatch beats a silent one.
func version() -> String:
	return "0"


## THE MANIFEST, built from the four methods above so it can never drift
## from what [method attach] actually does.
func manifest() -> Dictionary:
	return {
		"name": addon_name(),
		"doors": doors(),
		"reads": reads(),
		"writes": writes(),
		"version": version(),
	}


# -- validity -----------------------------------------------------------------

## A TOPIC AN ADD-ON MAY WRITE ON: "/sense", "/act", or "/sense/<door>".
static func write_topic_valid(topic: String) -> bool:
	if WRITE_TOPICS.has(topic):
		return true
	return topic.begins_with(WRITE_PREFIX)


## EVERY WRITE THIS ADD-ON DECLARES IS ALLOWED, or the loader refuses it.
func writes_valid() -> bool:
	for t in writes():
		if not write_topic_valid(String(t)):
			return false
	return true


## DOES THIS ADD-ON EXIST AT ALL? At least one door or one write is the bar --
## an add-on with neither touches nothing and does nothing, which is not a
## function, it is a folder.
func valid() -> bool:
	var ok: bool = true
	if addon_name().strip_edges() == "":
		push_error("HexyAddon: an add-on has no name (addon_name() is empty)")
		ok = false
	if doors().is_empty() and writes().is_empty():
		push_error("HexyAddon: %s opens no door and writes nothing" % addon_name())
		ok = false
	if not writes_valid():
		push_error("HexyAddon: %s writes outside Sense/Act (%s)"
			% [addon_name(), str(writes())])
		ok = false
	return ok
