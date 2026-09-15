class_name HexyAddons
extends Node

## W8d -- THE LOADER, ON THE NEW CONTRACT.
##
## Scans `res://addons/hexy_*/addon.gd`, builds each script, refuses an
## add-on whose [method HexyAddon.writes] names anything outside Sense/Act,
## wraps the broker it hands out so an undeclared [method Broker.acquire]
## is refused and pushed, and enforces one holder per door across every
## add-on on the bus. Nothing else in scripts/ names an add-on: delete the
## folder and this scan finds nothing, which is the whole of "add-on off =
## base unchanged".

signal attached(addon_name: String)
signal detached(addon_name: String)

const ADDONS_DIR: String = "res://addons"
const FOLDER_PREFIX: String = "hexy_"
const ENTRY_FILE: String = "addon.gd"

var _addons: Array[HexyAddon] = []
var _bus: Dictionary = {}
var _broker: Broker = null


## A BROKER THAT ONLY OPENS THE DOORS ITS OWNER DECLARED. Wraps the real
## [Broker] so `acquire()` on anything outside `allowed` is refused and
## pushed loudly, exactly like the doorless/wrong-write refusals at attach.
class GuardedBroker extends RefCounted:
	var _real: Broker
	var _who: String
	var _allowed: PackedStringArray

	func _init(real: Broker, who: String, allowed: PackedStringArray) -> void:
		_real = real
		_who = who
		_allowed = allowed

	func acquire(door: String, who: String = "") -> bool:
		if not _allowed.has(door):
			push_warning("HexyAddons: %s asked for undeclared door %s" % [_who, door])
			return false
		return _real.acquire(door, _who)

	## THE DOOR TABLE'S OWN NAME, mirrored exactly: [method Broker.release_door].
	func release_door(door: String, who: String = "") -> void:
		if not _allowed.has(door):
			push_warning("HexyAddons: %s asked to release undeclared door %s" % [_who, door])
			return
		_real.release_door(door, _who)

	## DEPRECATED: the door table has no `release(door, holder)` of its own --
	## that name belongs to [method Broker.release]'s four-law resource
	## table. Kept only so an old add-on still built against this guard does
	## not crash; forwards to [method release_door] with a warning.
	func release(door: String, who: String = "") -> void:
		push_warning("HexyAddons: %s called deprecated release(%s); use release_door()" % [_who, door])
		release_door(door, who)

	func holder(door: String) -> String:
		return _real.holder(door)

	## EVERY DOOR THIS HOLDER HAS, guarded the same way: [method Broker.release_all_doors].
	func release_all_doors(who: String = "") -> void:
		_real.release_all_doors(_who)


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

## `bus` is {topic: HexyTopic, broker: Broker, gauge: HexyGauge (optional),
## store: HexyStore (read only)}. Each add-on is handed its own wrapped copy
## with `broker` replaced by a [GuardedBroker].
func load_all(bus: Dictionary = {}) -> int:
	_bus = bus.duplicate()
	_broker = _bus.get("broker", null) as Broker
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


## ONE ADD-ON ONTO THE BUS, contract first. False means it was refused, and
## the reason has already been pushed.
func attach_one(addon: HexyAddon) -> bool:
	if addon == null:
		return false
	if not addon.valid():
		addon.queue_free()
		return false
	var who: String = addon.addon_name().strip_edges()
	if who == "":
		addon.queue_free()
		return false
	for a in _addons:
		if a.addon_name() == who:
			push_error("HexyAddons: %s is already on the bus" % who)
			addon.queue_free()
			return false
	## ONE HOLDER PER DOOR, checked before the door is even offered: an
	## add-on that DECLARES a door a live organ (or an earlier add-on)
	## already holds is refused up front, loudly, rather than let it find
	## out the first time it calls acquire().
	if _broker != null:
		for d in addon.doors():
			var door: String = String(d)
			var owner: String = _broker.holder(door)
			if owner != "" and owner != who:
				push_error("HexyAddons: %s wants door %s, %s already holds it"
					% [who, door, owner])
				addon.queue_free()
				return false

	var addon_bus: Dictionary = _bus.duplicate()
	if _broker != null:
		addon_bus["broker"] = GuardedBroker.new(_broker, who, addon.doors())

	addon.name = who
	add_child(addon)
	_addons.append(addon)
	addon.attach(addon_bus)
	attached.emit(who)
	return true


## EVERY ADD-ON OFF, newest first, each given its own detach() before the
## node goes, and every door it holds released whether it remembered to or
## not.
func detach_all() -> void:
	for i in range(_addons.size() - 1, -1, -1):
		var addon: HexyAddon = _addons[i]
		var who: String = addon.name
		addon.detach()
		if _broker != null:
			_broker.release_all_doors(who)
		_addons.remove_at(i)
		remove_child(addon)
		addon.queue_free()
		detached.emit(who)


# -- what a panel may ask for -------------------------------------------------

func addons() -> Array[HexyAddon]:
	return _addons.duplicate()


func names() -> Array[String]:
	var out: Array[String] = []
	for a in _addons:
		out.append(String(a.name))
	return out


## DOOR -> HOLDER, for every door any attached add-on declared, plus TOPIC ->
## WRITERS. This is the dashboard's panel 10.
func doors() -> Dictionary:
	var out: Dictionary = {}
	for a in _addons:
		for d in a.doors():
			out[String(d)] = _broker.holder(String(d)) if _broker != null else String(a.name)
	return out


func topic_writers() -> Dictionary:
	var out: Dictionary = {}
	for a in _addons:
		for t in a.writes():
			var topic: String = String(t)
			if not out.has(topic):
				out[topic] = []
			(out[topic] as Array).append(String(a.name))
	return out
