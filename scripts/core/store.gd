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
signal head_changed(h: Dictionary)
signal body_changed(b: Dictionary)
signal flipped(f: Dictionary)
signal machine_changed(m: Dictionary)
signal human_changed(h: Dictionary)
signal room_changed(r: Dictionary)
signal answer_changed(a: String)

## THE HEAD (moon, upper trigram, the Oracle). Moved by the user alone: a coin
## cast, a prev/next, a tap on the head ring. It walks HuohoutuData.HEAD_SEQUENCE.
## {bits, moving, throws, when, who, source, sig, seq_index}
var head: Dictionary = _empty_hexagram()

## THE BODY (sun, lower trigram, the Tensegrity). Moved by the senses alone,
## one line at a time. It walks HuohoutuData.BODY_SEQUENCE.
var body: Dictionary = _empty_hexagram()

## The last line that turned, and why. {line:int 0..5, to_yang:bool, reason, when}
var last_flip: Dictionary = _empty_flip()

## THE OLD NAME OF THE BODY. Every caller written before there were two figures
## reads store.hexagram, and every one of them meant the body; so this is not a
## copy but the body itself, through a property.
var hexagram: Dictionary:
	get:
		return body
	set(value):
		set_body(value)

## {trigram:int 0..7, score:float, sentence:String}
var machine: Dictionary = _empty_family()

## {trigram:int 0..7, score:float, sentence:String}
var human: Dictionary = _empty_family()

const CharacterScript := preload("res://scripts/brain/character.gd")

## {bits:int, moving:int, peers:int}
var room: Dictionary = _empty_room()

var answer: String = ""

## Biological Fruit Fly Character Homeostat
var character: RefCounted = null


func _init() -> void:
	character = CharacterScript.new()
	character.line_opened.connect(_on_character_line_opened)
	character.line_closed.connect(_on_character_line_closed)


func _on_character_line_opened(line: int) -> void:
	var meta = character.fly_neuromodulator(line - 1)
	set_last_flip({
		"line": line - 1,
		"to_yang": true,
		"reason": meta.get("transmitter", "open"),
		"when": Time.get_ticks_msec()
	})


func _on_character_line_closed(line: int) -> void:
	var meta = character.fly_neuromodulator(line - 1)
	set_last_flip({
		"line": line - 1,
		"to_yang": false,
		"reason": meta.get("transmitter", "closed"),
		"when": Time.get_ticks_msec()
	})


func get_character() -> RefCounted:
	if character == null:
		character = CharacterScript.new()
	return character


static func _empty_hexagram() -> Dictionary:
	return {
		"bits": 0,
		"moving": 0,
		"throws": ([] as Array[int]),
		"when": 0,
		"who": "",
		"source": "tap",
		"sig": "",
		"seq_index": 0,
	}


static func _empty_flip() -> Dictionary:
	return {"line": 0, "to_yang": false, "reason": "", "when": 0}


static func _empty_family() -> Dictionary:
	return {"trigram": 0, "score": 0.0, "sentence": ""}


static func _empty_room() -> Dictionary:
	return {"bits": 0, "moving": 0, "peers": 0}


# --- the two figures --------------------------------------------------------

## The body moved. Emits body_changed, then hexagram_changed, because the
## hexagram IS the body and the old signal must keep its old meaning.
func set_body(b: Dictionary) -> bool:
	var next: Dictionary = _normalise_hexagram(b, false)
	if _same(next, body):
		return false
	body = next
	body_changed.emit(body)
	hexagram_changed.emit(body)
	return true


## The old name. It always meant the body; it still does.
func set_hexagram(h: Dictionary) -> bool:
	return set_body(h)


## The head moved. NEVER emits hexagram_changed: the coupling is one way, and
## a head that woke the body's listeners would be the loop this model forbids.
func set_head(h: Dictionary) -> bool:
	var next: Dictionary = _normalise_hexagram(h, true)
	if _same(next, head):
		return false
	head = next
	head_changed.emit(head)
	return true


func set_last_flip(f: Dictionary) -> bool:
	var next: Dictionary = _empty_flip()
	next["line"] = clampi(int(f.get("line", 0)), 0, 5)
	next["to_yang"] = bool(f.get("to_yang", false))
	next["reason"] = String(f.get("reason", ""))
	next["when"] = int(f.get("when", 0))
	if _same(next, last_flip):
		return false
	last_flip = next
	flipped.emit(last_flip)
	return true


func head_bits() -> int:
	return int(head.get("bits", 0)) & 63


func body_bits() -> int:
	return int(body.get("bits", 0)) & 63


## The seat a figure holds on its own wheel, 0..63. Absent, it is derived from
## the bits through the King Wen id, because the wheels are keyed by id.
static func seq_index_of(bits: int, is_head: bool) -> int:
	var id: int = int(HuohoutuData.get_by_bits(bits & 63).get("id", 1))
	if is_head:
		return HuohoutuData.find_head_index_by_id(id)
	return HuohoutuData.find_body_index_by_id(id)


func _normalise_hexagram(h: Dictionary, is_head: bool = false) -> Dictionary:
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
	if h.has("seq_index"):
		out["seq_index"] = clampi(int(h["seq_index"]), 0, 63)
	else:
		out["seq_index"] = seq_index_of(out["bits"], is_head)
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
	return body_bits()


func transformed() -> int:
	return (int(body.get("bits", 0)) ^ int(body.get("moving", 0))) & 63


func dump() -> Dictionary:
	return {
		"hexagram": body.duplicate(true),
		"head": head.duplicate(true),
		"body": body.duplicate(true),
		"last_flip": last_flip.duplicate(true),
		"machine": machine.duplicate(true),
		"human": human.duplicate(true),
		"room": room.duplicate(true),
		"answer": answer,
	}


func load_dump(d: Dictionary) -> void:
	if d.has("head") and d["head"] is Dictionary:
		set_head(d["head"] as Dictionary)
	if d.has("body") and d["body"] is Dictionary:
		set_body(d["body"] as Dictionary)
	elif d.has("hexagram") and d["hexagram"] is Dictionary:
		set_body(d["hexagram"] as Dictionary)
	if d.has("last_flip") and d["last_flip"] is Dictionary:
		set_last_flip(d["last_flip"] as Dictionary)
	if d.has("machine") and d["machine"] is Dictionary:
		set_machine(d["machine"] as Dictionary)
	if d.has("human") and d["human"] is Dictionary:
		set_human(d["human"] as Dictionary)
	if d.has("room") and d["room"] is Dictionary:
		set_room(d["room"] as Dictionary)
	if d.has("answer"):
		set_answer(String(d["answer"]))


func reset() -> void:
	set_head(_empty_hexagram())
	set_body(_empty_hexagram())
	set_last_flip(_empty_flip())
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
