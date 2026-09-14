class_name HexyAddons
extends Node

## THE LOADER: the one place base learns that an add-on exists.
##
## It scans `res://addons/hexy_*/addon.gd`, builds each script, checks the
## manifest against [class HexyAddon], registers whatever tunables the add-on
## brought into the one registry, and hands it the bus. Nothing else in
## scripts/ names an add-on, which is the whole of the "add-on off = base
## unchanged" invariant: delete the folder and this scan finds nothing.
##
## ONE DOOR PER PLUGIN. Two add-ons claiming "ixbody" is a packaging mistake,
## not a runtime choice, so the second one is refused loudly.

## An add-on is now on the bus.
signal attached(addon_name: String)

## An add-on has been taken off it.
signal detached(addon_name: String)

## Where add-ons live and what their entry file is called.
const ADDONS_DIR: String = "res://addons"
const FOLDER_PREFIX: String = "hexy_"
const ENTRY_FILE: String = "addon.gd"

var _addons: Array[HexyAddon] = []
var _doors: Dictionary = {}
var _store: Object = null
var _bus: Dictionary = {}


# -- scanning -----------------------------------------------------------------

## Every `res://addons/hexy_*/addon.gd` on disk, sorted so a boot is repeatable.
static func scan_paths() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(ADDONS_DIR)
	if dir == null:
		return out
	for folder in dir.get_directories():
		if not folder.begins_with(FOLDER_PREFIX):
			continue
		var path: String = "%s/%s/%s" % [ADDONS_DIR, folder, ENTRY_FILE]
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			out.append(path)
	out.sort()
	return out


# -- attaching ----------------------------------------------------------------

## SCAN, BUILD, CHECK, ATTACH. Returns how many add-ons ended up on the bus.
## `bus` is the small dictionary {store, character, alchemy}; `store` is the
## one HexyStore, handed separately because it is the add-on's first argument.
func load_all(store: Object, bus: Dictionary = {}) -> int:
	_store = store
	_bus = bus.duplicate()
	if not _bus.has("store"):
		_bus["store"] = store
	var count: int = 0
	for path in scan_paths():
		var script: Script = load(path) as Script
		if script == null:
			push_error("HexyAddons: %s is not a script" % path)
			continue
		var made: Variant = script.new()
		if not (made is HexyAddon):
			push_error("HexyAddons: %s does not extend HexyAddon" % path)
			if made is Node:
				(made as Node).queue_free()
			continue
		if attach_one(made as HexyAddon):
			count += 1
	return count


## ONE ADD-ON ONTO THE BUS, manifest first. False means it was refused, and
## the reason has already been pushed.
func attach_one(addon: HexyAddon) -> bool:
	if addon == null:
		return false
	if not addon.valid():
		addon.queue_free()
		return false
	var m: Dictionary = addon.manifest()
	var who: String = String(m.get("name", "")).strip_edges()
	if who == "":
		push_error("HexyAddons: an add-on has no name in its manifest")
		addon.queue_free()
		return false
	var d: String = String(m.get("door", ""))
	if _doors.has(d):
		push_error("HexyAddons: door %s is already held by %s" % [d, String(_doors[d])])
		addon.queue_free()
		return false

	var keys: Dictionary = addon.config_keys()
	if not keys.is_empty():
		HexyConfig.instance().register(keys)

	addon.name = who
	add_child(addon)
	_addons.append(addon)
	_doors[d] = who
	addon.attach(_store, HexyConfig.peek(), _bus)
	attached.emit(who)
	return true


## EVERY ADD-ON OFF, newest first, each one given its own detach() before the
## node goes. What the registry grew stays grown -- a tunable is not state.
func detach_all() -> void:
	for i in range(_addons.size() - 1, -1, -1):
		var addon: HexyAddon = _addons[i]
		var who: String = addon.name
		addon.detach()
		_doors.erase(addon.door())
		_addons.remove_at(i)
		remove_child(addon)
		addon.queue_free()
		detached.emit(who)


# -- what a panel may ask for -------------------------------------------------

## The attached add-ons, in attach order.
func addons() -> Array[HexyAddon]:
	return _addons.duplicate()


## Their names, in attach order.
func names() -> Array[String]:
	var out: Array[String] = []
	for a in _addons:
		out.append(String(a.name))
	return out


## line or circuit id -> the doors feeding it. This is the dashboard's whole
## panel 10: six need rows, four circuit rows, and which door lands on each.
func doors() -> Dictionary:
	var out: Dictionary = {}
	for a in _addons:
		var l: int = a.line()
		if not out.has(l):
			out[l] = []
		(out[l] as Array).append(a.door())
	return out
