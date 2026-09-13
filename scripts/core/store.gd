class_name HexyStore
extends Node

## The ONLY shared state of the Hexy core.
##
## Autoload-able singleton. Everything else (glass, senses, room, net) reads
## from here and writes through the setters. Setters emit only on real change.
##
## Bit convention (see scripts/core/iching/king_wen.gd):
##   bit i = line i+1 counted from the bottom, yang = 1.
##   lower trigram = bits & 7, upper trigram = bits >> 3.

signal hexagram_changed(h: Dictionary)
signal machine_changed(m: Dictionary)
signal human_changed(h: Dictionary)
signal room_changed(r: Dictionary)
signal answer_changed(a: String)

## {bits:int, moving:int, throws:Array[int], when:int, who:String, source:String, sig:String}
var hexagram: Dictionary = _empty_hexagram()

## {trigram:int 0..7, score:float, sentence:String}
var machine: Dictionary = _empty_family()

## {trigram:int 0..7, score:float, sentence:String}
var human: Dictionary = _empty_family()

## {bits:int, moving:int, peers:int}
var room: Dictionary = _empty_room()

var answer: String = ""


static func _empty_hexagram() -> Dictionary:
	return {
		"bits": 0,
		"moving": 0,
		"throws": ([] as Array[int]),
		"when": 0,
		"who": "",
		"source": "tap",
		"sig": "",
	}


static func _empty_family() -> Dictionary:
	return {"trigram": 0, "score": 0.0, "sentence": ""}


static func _empty_room() -> Dictionary:
	return {"bits": 0, "moving": 0, "peers": 0}


# --- hexagram ---------------------------------------------------------------

func set_hexagram(h: Dictionary) -> bool:
	var next: Dictionary = _normalise_hexagram(h)
	if _same(next, hexagram):
		return false
	hexagram = next
	hexagram_changed.emit(hexagram)
	return true


func _normalise_hexagram(h: Dictionary) -> Dictionary:
	var out: Dictionary = _empty_hexagram()
	out["bits"] = int(h.get("bits", 0)) & 63
	out["moving"] = int(h.get("moving", 0)) & 63
	var throws: Array[int] = ([] as Array[int])
	var raw: Variant = h.get("throws", [])
	if raw is Array:
		for v in (raw as Array):
			throws.append(int(v))
	out["throws"] = throws
	out["when"] = int(h.get("when", 0))
	out["who"] = String(h.get("who", ""))
	var src: String = String(h.get("source", "tap"))
	if not (src in ["tap", "senses", "room"]):
		src = "tap"
	out["source"] = src
	out["sig"] = String(h.get("sig", ""))
	return out


# --- families ---------------------------------------------------------------

func set_machine(m: Dictionary) -> bool:
	var next: Dictionary = _normalise_family(m)
	if _same(next, machine):
		return false
	machine = next
	machine_changed.emit(machine)
	return true


func set_human(h: Dictionary) -> bool:
	var next: Dictionary = _normalise_family(h)
	if _same(next, human):
		return false
	human = next
	human_changed.emit(human)
	return true


func _normalise_family(f: Dictionary) -> Dictionary:
	var out: Dictionary = _empty_family()
	out["trigram"] = clampi(int(f.get("trigram", 0)), 0, 7)
	out["score"] = float(f.get("score", 0.0))
	out["sentence"] = String(f.get("sentence", ""))
	return out


# --- room -------------------------------------------------------------------

func set_room(r: Dictionary) -> bool:
	var next: Dictionary = _empty_room()
	next["bits"] = int(r.get("bits", 0)) & 63
	next["moving"] = int(r.get("moving", 0)) & 63
	next["peers"] = maxi(0, int(r.get("peers", 0)))
	if _same(next, room):
		return false
	room = next
	room_changed.emit(room)
	return true


# --- answer -----------------------------------------------------------------

func set_answer(a: String) -> bool:
	if a == answer:
		return false
	answer = a
	answer_changed.emit(answer)
	return true


# --- helpers ----------------------------------------------------------------

func primary() -> int:
	return int(hexagram.get("bits", 0)) & 63


func transformed() -> int:
	return (int(hexagram.get("bits", 0)) ^ int(hexagram.get("moving", 0))) & 63


func dump() -> Dictionary:
	return {
		"hexagram": hexagram.duplicate(true),
		"machine": machine.duplicate(true),
		"human": human.duplicate(true),
		"room": room.duplicate(true),
		"answer": answer,
	}


func load_dump(d: Dictionary) -> void:
	if d.has("hexagram") and d["hexagram"] is Dictionary:
		set_hexagram(d["hexagram"] as Dictionary)
	if d.has("machine") and d["machine"] is Dictionary:
		set_machine(d["machine"] as Dictionary)
	if d.has("human") and d["human"] is Dictionary:
		set_human(d["human"] as Dictionary)
	if d.has("room") and d["room"] is Dictionary:
		set_room(d["room"] as Dictionary)
	if d.has("answer"):
		set_answer(String(d["answer"]))


func reset() -> void:
	set_hexagram(_empty_hexagram())
	set_machine(_empty_family())
	set_human(_empty_family())
	set_room(_empty_room())
	set_answer("")


static func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
		var av: Variant = a[k]
		var bv: Variant = b[k]
		if av is Array and bv is Array:
			if (av as Array) != (bv as Array):
				return false
		elif av != bv:
			return false
	return true
