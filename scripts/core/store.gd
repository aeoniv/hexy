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
signal earth_changed(e: Dictionary)
signal flipped(f: Dictionary)
signal machine_changed(m: Dictionary)
signal human_changed(h: Dictionary)
signal room_changed(r: Dictionary)
signal answer_changed(a: String)
## A CAST LANDED AND IS MEANT FOR THE BODY. The glass announces the gesture
## here and never writes the body itself; the app alone hears this and
## re-anchors the cube on it, so pacing re-anchors instead of being
## overwritten behind its back.
signal cast_landed(c: Dictionary)

## THE ONE BUS FOR ALL THREE SEATS. A gesture is announced here and the seat's
## own writer answers; `cast_landed` is the old name of the BODY half of it and
## is still emitted, so nothing written before there were three seats breaks.
signal seat_landed(seat: int, c: Dictionary)

## THE WHOLE STATE WAS PUT BACK. `load_dump` and `reset` say so when they are
## done, because a figure that arrives whole is not a figure that moved: the
## cube must be re-anchored on it rather than walked towards it.
signal restored()

## THE THREE SEATS A FIGURE CAN SIT IN. The order is the order they are drawn,
## moon over sun over altar, and the numbers are wire-stable.
enum Seat { HEAD = 0, BODY = 1, EARTH = 2 }

## The last 64-corner cube mass the app published. Empty until a first tick.
var _q6_mass: PackedFloat32Array = PackedFloat32Array()

## THE CUBE, AS THE APP LAST PUBLISHED IT, so a dump carries the pacing that
## the body was standing on and a restore can put it back. Publish only: the
## store never computes these, it only remembers and persists them.
var _pacing_bits: int = 0
var _journal_tail: Dictionary = {}

## TRUE ONCE THE APP HAS CLAIMED THE BODY. With a claim, `note_seat(BODY, ...)`
## only announces and the app alone writes, so pacing re-anchors instead of
## being overwritten behind its back. Without one -- a bare store in a test, a
## headless tool, the glass with no core behind it -- the announcement still
## has to land somewhere, so the store writes the body itself. One writer
## either way; never none, never two.
var _body_claimed: bool = false

## THE HEAD (moon, upper trigram, the Oracle). Moved by the user alone: a coin
## cast, a prev/next, a tap on the head ring. It walks HuohoutuData.HEAD_SEQUENCE.
## {bits, moving, throws, when, who, source, sig, seq_index}
var head: Dictionary = _empty_hexagram()

## THE BODY (sun, lower trigram, the Tensegrity). Moved by the senses alone,
## one line at a time. It walks HuohoutuData.BODY_SEQUENCE.
var body: Dictionary = _empty_hexagram()

## THE EARTH (altar, manual controls, the exclusive Hexagram).
var earth: Dictionary = _empty_hexagram()

## The last line that turned, and why. {line:int 0..5, to_yang:bool, reason, when}
var last_flip: Dictionary = _empty_flip()

## THE OLD NAME OF THE BODY. Every caller written before there were two figures
## reads store.hexagram, and every one of them meant the body; so this is not a
## copy but the body itself, through a property.
## THE OLD NAME OF THE BODY, and an announcement like any other: it goes down
## the seat bus so the body keeps its single writer whoever spells it this way.
var hexagram: Dictionary:
	get:
		return body
	set(value):
		note_seat(Seat.BODY, value)

## {trigram:int 0..7, score:float, sentence:String}
var machine: Dictionary = _empty_family()

## {trigram:int 0..7, score:float, sentence:String}
var human: Dictionary = _empty_family()

const CharacterScript := preload("res://scripts/brain/character.gd")

## The most the room may turn this body, in radians per second.
const MAX_SWARM_YAW: float = 1.0

## {bits:int, moving:int, peers:int}
var room: Dictionary = _empty_room()

var answer: String = ""

## THE SWARM'S PULL, in radians per second. MeshFabric computes a Kuramoto
## coupling from the headings of everyone in the room and Wmn ticks it in here
## twice a second; the sensor oracle adds it to the gyro yaw rate it samples,
## so a room full of hexys slowly turns to face the same way. Zero means a
## room of one, which is also what it reads with no mesh at all.
var swarm_yaw: float = 0.0

## WHERE THE BODY HAS BEEN, newest last, as plain six-bit figures. Journey's
## ROAD_BACK rule needs more than one step of memory to fire at all, and the
## store is the only thing here that outlives a run, so the path is kept with
## the figure rather than in whatever glass happens to be watching.
var _path: Array[int] = ([] as Array[int])
## How many steps of the path are kept. Journey looks back eight; a little
## more than that is enough for it and small enough to carry in a dump.
const PATH_MAX: int = 32

## Biological Fruit Fly Character Homeostat
var character: RefCounted = null


func _init() -> void:
	character = CharacterScript.new()
	character.line_opened.connect(_on_character_line_opened)
	character.line_closed.connect(_on_character_line_closed)
	earth = _normalise_hexagram({"id": 2, "bits": 2})


func _on_character_line_opened(line: int) -> void:
	var meta = character.fly_neuromodulator(line - 1)
	set_last_flip({
		"line": line - 1,
		"to_yang": true,
		"reason": meta.get("transmitter", "open"),
		"when": Clock.now_ms()
	})


func _on_character_line_closed(line: int) -> void:
	var meta = character.fly_neuromodulator(line - 1)
	set_last_flip({
		"line": line - 1,
		"to_yang": false,
		"reason": meta.get("transmitter", "closed"),
		"when": Clock.now_ms()
	})


## The swarm's pull on this body. Clamped: a coupling is a nudge, never a spin.
func set_swarm_yaw(rad_per_s: float) -> void:
	swarm_yaw = clampf(rad_per_s, -MAX_SWARM_YAW, MAX_SWARM_YAW)


func get_character() -> RefCounted:
	if character == null:
		character = CharacterScript.new()
	return character


## A CAST LANDED. The glass owns the cast gestures, so the glass must say so:
## call this the moment a cast is confirmed and committed.
##
## W8e -- THE CAST IS A SENSE NOW, NOT A WRITE. This used to reach straight
## into the organism and hand the mushroom body its dopamine, which made the
## glass a writer of brain state. It no longer does: the cast is recorded
## (the seat bus still carries it) and then published on "/sense" as a words
## door "cast" message, exactly like a spoken utterance. Whatever the brain
## decides that is worth is the brain's business.
##
## Returns 1.0 when the Sense went out on a bus, 0.0 when there is no bus to
## put it on -- the same "did anything happen" shape the old return had.
func note_cast(kind: String = "cast_confirmed", c: Dictionary = {}) -> float:
	if not c.is_empty():
		note_seat(Seat.BODY, c)
	if _bus == null:
		return 0.0
	var ok: bool = bool(_bus.publish("/sense", HexyMsg.sense("words", "cast",
		Time.get_ticks_usec() * 1000, 1.0, {"kind": kind})))
	return 1.0 if ok else 0.0


## A FIGURE LANDED IN A SEAT. The glass owns the gestures and says so here; it
## never writes a seat itself, so every seat has one event shape and one writer:
##
##   HEAD  -> the store, straight through set_head (no cube; the head is free).
##   BODY  -> the app, through inject, so pacing re-anchors on it. With no
##            app listening the store writes it, so an announcement never
##            falls on the floor.
##   EARTH -> the store, straight through set_earth (the altar, not the body).
func note_seat(seat: int, c: Dictionary) -> void:
	var is_head: bool = seat != Seat.BODY
	var n: Dictionary = _normalise_hexagram(c, is_head)
	seat_landed.emit(seat, n)
	match seat:
		Seat.HEAD:
			set_head(n)
		Seat.EARTH:
			set_earth(n)
		_:
			## The old name of this same announcement, for readers written
			## before the bus was general. The app listens on ONE of the two.
			cast_landed.emit(n)
			## A CAST MAKES A WARM CHAT STALE. Folded from the deleted
			## alchemy.gd (W10d): the figure the decode loop was leaning on
			## is not the figure the body stands on the moment a seat lands,
			## even before the body bits themselves are written below.
			Q6Core.bump_cast_version()
			if not _body_claimed or c.get("source", "") in ["tap", "wheel", "manual"]:
				set_body(n)


## The app says "the body is mine" here, once, at bind. Nothing else may.
func claim_body(claimed: bool = true) -> void:
	_body_claimed = claimed


## PUBLISH ONLY, from the app, so `dump` can carry the cube the body stood on.
func set_pacing_state(bits: int, journal_tail: Dictionary = {}) -> void:
	_pacing_bits = bits & 63
	_journal_tail = journal_tail.duplicate(true)


func pacing_bits() -> int:
	return _pacing_bits


func journal_tail() -> Dictionary:
	return _journal_tail


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


# --- the body comes off the bus ---------------------------------------------

## W8c -- THE BODY IS DERIVED, AND THE HOMEOSTAT DERIVES IT.
##
## `store.body["bits"]` used to have four writers: the old alchemy shim (its own hysteresis
## over the senses), the seat bus, a restore, and a reset. Only the last three
## were ever about THIS store; the first was a second brain living in the core.
## Now the bits are a READOUT of the homeostat's six line fills, published by
## scripts/brain as a Body message, and this subscriber is the only way one
## reaches the store from outside it. `set_body` stays -- a restore and a reset
## and the seat bus still need it -- but it is INTERNAL to this file: nothing
## under scripts/ outside store.gd and scripts/brain may call it, and
## tests/test_gauge_wall.gd fails the moment something does.
var _bus: RefCounted = null
var _bus_sub: int = -1
var _seat_sub: int = -1

## THE DOOR A GESTURE ON THE GLASS ARRIVES THROUGH. W10c -- every page is a
## subscriber and none is a writer, so a dial no longer calls note_seat: it
## publishes a tarsi Sense at this door and the store, the one writer of seat
## state, applies it here.
const DOOR_SEAT: String = "earth_seat"


## Subscribe this store to a topic bus. From here the body follows the brain.
func attach_bus(topic: RefCounted) -> void:
	if topic == null:
		return
	detach_bus()
	_bus = topic
	_bus_sub = int(topic.subscribe("/body", Callable(self, "_on_body_msg")))
	_seat_sub = int(topic.subscribe("/sense/%s" % DOOR_SEAT,
		Callable(self, "_on_seat_sense")))
	## A LATCHED BODY IS STILL A BODY. The bus retains the last message on
	## every topic, so a store attached after the brain has already spoken
	## stands on the figure that is live rather than on an empty one.
	var latched: Dictionary = topic.last("/body")
	if not latched.is_empty():
		_on_body_msg(latched)


func detach_bus() -> void:
	if _bus != null and _bus_sub >= 0:
		_bus.unsubscribe(_bus_sub)
	if _bus != null and _seat_sub >= 0:
		_bus.unsubscribe(_seat_sub)
	_bus = null
	_bus_sub = -1
	_seat_sub = -1


## A GESTURE LANDED IN A SEAT, SAID AS A SENSE. The value is the figure the
## finger picked plus the seat it picked it in; "cast" in the value names the
## note_cast kind an altar throw also deserves, and is empty for a plain walk.
## The glass only says this; the applying is here, so a seat keeps one writer.
func _on_seat_sense(msg: Dictionary) -> void:
	if typeof(msg) != TYPE_DICTIONARY or String(msg.get("kind", "")) != "sense":
		return
	if String(msg.get("door", "")) != DOOR_SEAT:
		return
	var v: Variant = msg.get("value", null)
	if typeof(v) != TYPE_DICTIONARY:
		return
	var value: Dictionary = (v as Dictionary).duplicate(true)
	var seat: int = int(value.get("seat", Seat.BODY))
	var cast_kind: String = String(value.get("cast", ""))
	value.erase("seat")
	value.erase("cast")
	note_seat(seat, value)
	if cast_kind != "":
		## One arg on purpose: the reward only. The figure has already been
		## seated above and must not be announced on the BODY seat again.
		note_cast(cast_kind)


## THE ONE BODY-BITS WRITER FROM OUTSIDE THIS FILE. A Body message carries the
## whole organism; the store keeps the figure half of it, because that is the
## half it has always persisted.
func _on_body_msg(msg: Dictionary) -> void:
	if typeof(msg) != TYPE_DICTIONARY or String(msg.get("kind", "")) != "body":
		return
	var bits: int = int(msg.get("bits", 0)) & 63
	if bits == body_bits():
		return
	set_body({
		"bits": bits,
		"moving": bits ^ body_bits(),
		"when": int(msg.get("t_ns", 0)) / 1_000_000,
		"who": "",
		"source": "brain",
		"seq_index": seq_index_of(bits, false),
	})


# --- the two figures --------------------------------------------------------

## The body moved. Emits body_changed, then hexagram_changed, because the
## hexagram IS the body and the old signal must keep its old meaning.
##
## INTERNAL TO THIS FILE AND TO scripts/brain since W8c -- see attach_bus.
func set_body(b: Dictionary) -> bool:
	var next: Dictionary = _normalise_hexagram(b, false)
	if _same(next, body):
		return false
	body = next
	_note_path(int(body.get("bits", 0)) & 63)
	body_changed.emit(body)
	hexagram_changed.emit(body)
	return true


## ONE STEP OF THE WALK, remembered. A body set to where it already stands is
## not a step and is not recorded, so the path is figures actually visited.
func _note_path(bits: int) -> void:
	if not _path.is_empty() and _path[_path.size() - 1] == bits:
		return
	_path.append(bits)
	while _path.size() > PATH_MAX:
		_path.remove_at(0)


## THE WALK SO FAR, newest last, for [method Journey.stage_of_path].
func body_path() -> Array[int]:
	return _path.duplicate() as Array[int]


## The old name. It always meant the body; it still does -- and like every
## other spelling of "the body moved", it goes down the seat bus.
func set_hexagram(h: Dictionary) -> bool:
	note_seat(Seat.BODY, h)
	return true


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


## THE 64-CORNER Q6 MASS, AS THE STORE LAST HEARD IT. The app's own beat publishes
## `pacing.cube.state()` here every beat and Wmn reads it for the bio pulse.
##
## PUBLISH ONLY, in both directions that matter: nothing in the store writes
## the cube, and a peer's q6 arriving off the mesh is never poured in here --
## Pacing is the one writer of cube mass and a remote body is not this body.
func q6_mass() -> PackedFloat32Array:
	return _q6_mass


## Called by the app and nobody else. Widened to float32 on the way in, because
## that is what goes on the wire and a second precision would be a second copy.
func set_q6_mass(mass: Variant) -> void:
	var out := PackedFloat32Array()
	out.resize(Q6Core.STATES)
	var i: int = 0
	for v in mass:
		if i >= Q6Core.STATES:
			break
		out[i] = float(v)
		i += 1
	_q6_mass = out


func head_bits() -> int:
	return int(head.get("bits", 0)) & 63


func body_bits() -> int:
	return int(body.get("bits", 0)) & 63


func set_earth(e: Dictionary) -> bool:
	var next: Dictionary = _normalise_hexagram(e, false)
	if _same(next, earth):
		return false
	earth = next
	earth_changed.emit(earth)
	return true


func earth_bits() -> int:
	return int(earth.get("bits", 2)) & 63


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
	## "wheel" is a walk of a sequence by hand and "restore" is a figure put
	## back from a dump; neither is a tap, and coercing them to one would have
	## the journal lie about why the body moved.
	if not (src in ["tap", "senses", "room", "wheel", "restore"]):
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
		"earth": earth.duplicate(true),
		"last_flip": last_flip.duplicate(true),
		"machine": machine.duplicate(true),
		"human": human.duplicate(true),
		"room": room.duplicate(true),
		"answer": answer,
		"pacing_bits": _pacing_bits,
		"journal_tail": _journal_tail.duplicate(true),
		"path": _path.duplicate(),
	}


func load_dump(d: Dictionary) -> void:
	if d.has("head") and d["head"] is Dictionary:
		set_head(d["head"] as Dictionary)
	## A restore writes the body DIRECTLY, not down the bus: the figure is not
	## a gesture, and the app's own beat re-anchors the cube on `restored`
	## below, once, when every seat is back -- rather than once per seat on
	## the way in.
	if d.has("body") and d["body"] is Dictionary:
		set_body(d["body"] as Dictionary)
	elif d.has("hexagram") and d["hexagram"] is Dictionary:
		## The legacy name, and its own branch: hung off the earth's `elif` it
		## was dropped by any dump that had an earth, which is all of them.
		set_body(d["hexagram"] as Dictionary)
	if d.has("earth") and d["earth"] is Dictionary:
		set_earth(d["earth"] as Dictionary)
	if d.has("pacing_bits"):
		_pacing_bits = int(d["pacing_bits"]) & 63
	if d.has("journal_tail") and d["journal_tail"] is Dictionary:
		_journal_tail = (d["journal_tail"] as Dictionary).duplicate(true)
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
	## THE WALKED PATH IS PUT BACK BEFORE `restored` FIRES, because whatever
	## re-reads it off this store on that signal must not arrive one restore
	## too late.
	if d.has("path") and d["path"] is Array:
		var walked: Array[int] = ([] as Array[int])
		for b in (d["path"] as Array):
			walked.append(int(b) & 63)
		while walked.size() > PATH_MAX:
			walked.remove_at(0)
		_path = walked
	## A RESTORE MAKES A WARM CHAT STALE TOO: the figure the decode loop was
	## leaning on is not the one this store now stands on.
	Q6Core.bump_cast_version()
	restored.emit()


func reset() -> void:
	set_head(_empty_hexagram())
	set_body(_empty_hexagram())
	set_earth(_normalise_hexagram({"id": 2, "bits": 2}))
	set_last_flip(_empty_flip())
	set_machine(_empty_family())
	set_human(_empty_family())
	set_room(_empty_room())
	set_answer("")
	_pacing_bits = 0
	_journal_tail = {}
	_path = ([] as Array[int])
	Q6Core.bump_cast_version()
	restored.emit()


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
