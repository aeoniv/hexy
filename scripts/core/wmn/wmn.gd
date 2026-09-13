class_name Wmn
extends Node

## The Wireless Mesh Network, whose wire word is a hexagram.
##
## This node owns nothing it could borrow. The transport is `MeshFabric`
## unchanged -- LAN UDP on the desktop, IxMesh Nearby the moment the Android
## singleton exists, a choice MeshPeer already makes and this node deliberately
## does not second-guess. What is new here is only what the fabric has no
## opinion about: that the payload is a figure, that the room has a clock, that
## the casts are kept, and that six lines is the whole of what a peer must
## understand to join in.
##
## Composition, layer by layer:
##   MeshFabric   store-and-forward envelopes, relays, dedup   (scripts/net)
##   Envelope6    one byte that IS the figure                  (this folder)
##   ChirpClock   the millisecond the room agrees on
##   Room         who is here and what they are all saying
##   Presence     the heartbeat that makes absence observable
##   Ledger       what was cast, and who says they saw it
##
## Nothing above emits a frame, a coordinate or a heading. The most a peer ever
## learns about another body is six bits and a timestamp.

signal peer_figure(who: String, h: Dictionary)
signal room_changed(room_dict: Dictionary)
signal clock_synced(offset_ms: int)
signal peer_gone(who: String)

const IdentityScript := preload("res://scripts/social/identity.gd")

## One kind on the fabric, because the kind that matters is in byte 0 of the
## payload. A fabric that had to learn a new `kind` string for every sort of
## figure would be a fabric this folder had forked rather than reused.
const WIRE_KIND := "wmn6"
const WIRE_KEY := "e6"
## A figure is for the room that can hear it, not the building. Two hops is one
## relay: far enough to cross a phone standing in a doorway, near enough that
## "the room" still means a room.
const FIGURE_TTL := 2
## A chirp is a measurement between two phones and is meaningless anywhere else
## -- the same ruling EventEnvelope makes for `chirp` in PRIVATE_BODY_KEYS.
const CHIRP_TTL := 1

var fabric: MeshFabric = null
var clock := ChirpClock.new()
var ledger := Ledger.new()
var room := Room.new()
var presence := Presence.new()
var identity: Object = null

## Isolates this mesh from other hexy instances on the same LAN. The test rig
## sets it; on a phone it stays empty, because a room is whoever is in it.
var session_token := ""
## Forces the desktop backend even where the Android plugin exists. Test knob.
var force_lan := false
## Keep a record of every figure that crosses this node, our own and the rooms.
var keep_ledger := true

var _who := ""
var _started := false
var _self_h: Dictionary = {}
## fabric src id -> {s: their last send (their clock), r: our recv (our clock)}
var _heard := {}
## fabric src id -> their BODY bits, the half of a peer the room does not vote
## with but a glass may still want to draw.
var _peer_body := {}
var _store: Node = null
var _binding := false


func fabric_id() -> String:
	return fabric.fabric_id if fabric != null else ""


func display_name() -> String:
	return _who


## The clock the whole room is on. Every `when` this node writes uses it.
func now_ms() -> int:
	return clock.now_ms()


func offset_ms() -> int:
	return clock.offset_ms()


func started() -> bool:
	return _started


## -- LIFE --------------------------------------------------------------------

func start(who: String) -> Error:
	if _started:
		return OK
	_who = who
	fabric = MeshFabric.new()
	fabric.fabric_id = _mint_fabric_id(who)
	add_child(fabric)
	var transport := fabric.add_transport(session_token)
	transport.force_lan = force_lan
	identity = IdentityScript.load_or_mint(fabric.fabric_id, who)
	ledger.identity = identity
	fabric.fabric_event.connect(_on_fabric_event)
	fabric.peer_lost.connect(_on_transport_lost)
	var err := fabric.start(who, session_token)
	_started = true
	set_process(true)
	return err


func stop() -> void:
	if not _started:
		return
	set_process(false)
	if fabric != null:
		fabric.stop()
	_started = false


## An install id outlives its launches (Identity.stable_fabric_id), but the
## desktop rig runs alpha and beta out of one user:// directory and they are not
## the same person. So a NAMED instance folds its name into the stable id -- the
## same bargain `load_or_mint` already strikes for the hue, one layer up.
static func _mint_fabric_id(who: String) -> String:
	var base := IdentityScript.stable_fabric_id()
	if who == "":
		return base
	return "%s%08x" % [base.substr(0, 8), absi(who.hash())]


## -- SPEAKING ----------------------------------------------------------------

## Send both figures. BYTE 0 OF THE WIRE IS THE HEAD -- the oracle a person
## threw is the one thing a room is entitled to read at a glance, and it is the
## head the room votes over. The body rides in the payload beside it.
func broadcast(head: Dictionary, body: Dictionary) -> Dictionary:
	if not _started:
		return {}
	var bits := int(head.get("bits", 0)) & 63
	var moving := int(head.get("moving", 0)) & 63
	var when := int(body.get("when", 0))
	if when <= 0:
		when = now_ms()
	var payload := {
		"moving": moving,
		"body": int(body.get("bits", 0)) & 63,
		"body_moving": int(body.get("moving", 0)) & 63,
		"throws": _throws_of(body, bits, moving),
		"when": when,
		"who": String(body.get("who", _who)),
		"source": String(body.get("source", "tap")),
		"sig": String(body.get("sig", "")),
	}
	_self_h = _figure_from(fabric.fabric_id, bits, payload)
	room.set_self(bits, moving, now_ms(), fabric.fabric_id)
	if keep_ledger:
		ledger.append(_self_h, [])
	presence.force_due()
	presence.due(now_ms())
	fabric.emit_event(WIRE_KIND,
		{WIRE_KEY: Envelope6.to_wire(Envelope6.KIND_FIGURE, bits, payload)},
		FIGURE_TTL)
	_publish_room()
	return _self_h


## The old name: "the body changed". The head is taken from the bound store,
## because the head is not this call's to invent.
func broadcast_figure(h: Dictionary) -> Dictionary:
	var head: Dictionary = {"bits": 0, "moving": 0}
	if _store != null:
		head = {"bits": _store.head_bits(), "moving": int(_store.head.get("moving", 0))}
	return broadcast(head, h)


## Vouch for a figure somebody else cast. Provenance, never a score.
func witness_figure(h: Dictionary) -> String:
	var id := Ledger.id_of(h)
	if keep_ledger:
		ledger.append(h, [fabric_id()])
	if _started:
		fabric.witness(WIRE_KIND,
			{WIRE_KEY: Envelope6.to_wire(Envelope6.KIND_WITNESS,
				int(h.get("bits", 0)) & 63, {"id": id, "who": fabric.fabric_id})},
			CHIRP_TTL)
	return id


func send_chirp() -> void:
	if not _started:
		return
	var echo := {}
	for src in _heard:
		echo[src] = [int(_heard[src]["s"]), int(_heard[src]["r"])]
	fabric.emit_event(WIRE_KIND,
		{WIRE_KEY: Envelope6.to_wire(Envelope6.KIND_CHIRP,
			int(_self_h.get("bits", 0)),
			{"s": Time.get_ticks_msec(), "e": echo})},
		CHIRP_TTL)


## -- HEARING -----------------------------------------------------------------

func _on_fabric_event(src: String, kind: String, body: Dictionary, _prov: String) -> void:
	if kind != WIRE_KIND or src == fabric.fabric_id:
		return
	ingest(src, body)


## The one door for an incoming body, network or not. Tests inject through it;
## so does the fabric. Same path, so a test proves the real one.
func ingest(src: String, body: Dictionary) -> void:
	if not body.has(WIRE_KEY):
		return
	var e := Envelope6.from_wire(String(body[WIRE_KEY]))
	var payload: Dictionary = e["payload"]
	match int(e["kind"]):
		Envelope6.KIND_FIGURE:
			_take_figure(src, int(e["bits"]), payload)
		Envelope6.KIND_CHIRP:
			_take_chirp(src, payload)
		Envelope6.KIND_WITNESS:
			var id := String(payload.get("id", ""))
			if id != "" and ledger.has(id):
				ledger.witness(id, String(payload.get("who", src)), "")
		_:
			pass


func _take_figure(src: String, bits: int, payload: Dictionary) -> void:
	var h := _figure_from(src, bits, payload)
	# The room is a room of HEADS: byte 0 is what everyone votes with.
	room.set_peer(src, bits, int(h["moving"]), now_ms())
	if keep_ledger:
		ledger.append(h, [fabric_id()])
	_peer_body[src] = int(h["body"])
	peer_figure.emit(src, h)
	_publish_room()


func _take_chirp(src: String, payload: Dictionary) -> void:
	var t3 := int(payload.get("s", 0))
	var t4 := Time.get_ticks_msec()
	var echo = payload.get("e", {})
	var before := clock.offset_ms()
	var did_pair := false
	if echo is Dictionary and (echo as Dictionary).has(fabric.fabric_id):
		var pair = (echo as Dictionary)[fabric.fabric_id]
		if pair is Array and (pair as Array).size() == 2:
			# pair[0] is the send stamp WE wrote (our clock, t1); pair[1] is
			# the instant they heard it (their clock, t2).
			clock.note(t3, t4, int((pair as Array)[1]), int((pair as Array)[0]))
			did_pair = true
	if not did_pair:
		clock.note(t3, t4)
	_heard[src] = {"s": t3, "r": t4}
	var after := clock.offset_ms()
	if after != before:
		clock_synced.emit(after)


func _on_transport_lost(_transport_id: String) -> void:
	# A lost LINK is not a lost PERSON -- they may still be two hops away
	# through somebody else. Only silence expires a peer, and that is
	# Presence job, in _process below.
	pass


## -- THE ROOM ----------------------------------------------------------------

func peers() -> Array:
	var now := now_ms()
	var out: Array = []
	for who in room.names():
		var p: Dictionary = room.peers[who]
		out.append({
			"who": who,
			"bits": int(p["bits"]),
			"moving": int(p["moving"]),
			"body": int(_peer_body.get(who, 0)) & 63,
			"last_seen_ms": int(p["seen"]),
			# The LAN backend has no radio and therefore no signal strength.
			# -1 is the honest answer; a made-up number would be worse than
			# none. See LanMesh.peer_proximity for the same ruling.
			"rssi": -1,
			"band": Presence.band(now - int(p["seen"]), -1),
		})
	return out


func peer_count() -> int:
	return room.peer_count()


func drifting() -> Array[String]:
	return room.drifting()


func room_figure() -> Dictionary:
	return room.figure()


func _publish_room() -> void:
	var r := room.as_store_room()
	if _store != null:
		_binding = true
		_store.set_room(r)
		_binding = false
	room_changed.emit(r)


## -- THE STORE ---------------------------------------------------------------

## Wire this mesh to the one piece of shared state the app has. Out: every
## local cast goes on the air. In: the room figure becomes store.room.
## The store own `room` is never fed back as a cast, so there is no loop --
## `set_room` emits `room_changed`, not `hexagram_changed`.
func bind(store: Node) -> void:
	_store = store
	if store == null:
		return
	if not store.hexagram_changed.is_connected(_on_store_hexagram):
		store.hexagram_changed.connect(_on_store_hexagram)
	if store.has_signal("head_changed") and not store.head_changed.is_connected(_on_store_head):
		store.head_changed.connect(_on_store_head)
	var h: Dictionary = store.hexagram
	if int(h.get("bits", 0)) != 0 or int(h.get("moving", 0)) != 0 or store.head_bits() != 0:
		broadcast_figure(h)


func unbind() -> void:
	if _store != null and _store.hexagram_changed.is_connected(_on_store_hexagram):
		_store.hexagram_changed.disconnect(_on_store_hexagram)
	if _store != null and _store.head_changed.is_connected(_on_store_head):
		_store.head_changed.disconnect(_on_store_head)
	_store = null


func _on_store_hexagram(h: Dictionary) -> void:
	if _binding:
		return
	broadcast_figure(h)


## The head moved, so the byte the room votes with moved. The body goes out
## beside it unchanged.
func _on_store_head(h: Dictionary) -> void:
	if _binding or _store == null:
		return
	broadcast(h, _store.body)


## -- THE BEAT ----------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _started:
		return
	var now := now_ms()
	var gone := room.expire(now)
	for who in gone:
		_heard.erase(who)
		_peer_body.erase(who)
		peer_gone.emit(who)
	if not gone.is_empty():
		_publish_room()
	if presence.due(now):
		send_chirp()
		if not _self_h.is_empty():
			fabric.emit_event(WIRE_KIND,
				{WIRE_KEY: Envelope6.to_wire(Envelope6.KIND_FIGURE,
					int(_self_h["bits"]), _payload_of(_self_h))},
				FIGURE_TTL)


## -- SHAPES ------------------------------------------------------------------

static func _throws_of(h: Dictionary, bits: int, moving: int) -> Array:
	var raw = h.get("throws", [])
	if raw is Array and (raw as Array).size() == 6:
		var out: Array = []
		for v in (raw as Array):
			out.append(int(v))
		return out
	var derived: Array = []
	for v in Cast.throws_of(bits, moving):
		derived.append(int(v))
	return derived


## A wire figure as a HexyStore.hexagram.
static func _figure_from(who_src: String, bits: int, payload: Dictionary) -> Dictionary:
	var moving := int(payload.get("moving", 0)) & 63
	var throws: Array = []
	var raw = payload.get("throws", [])
	if raw is Array and (raw as Array).size() == 6:
		for v in (raw as Array):
			throws.append(int(v))
	else:
		for v in Cast.throws_of(bits, moving):
			throws.append(int(v))
	var src := String(payload.get("source", "tap"))
	if not (src in ["tap", "senses", "room"]):
		src = "tap"
	return {
		"bits": bits & 63,
		"moving": moving,
		"body": int(payload.get("body", 0)) & 63,
		"body_moving": int(payload.get("body_moving", 0)) & 63,
		"throws": throws,
		"when": int(payload.get("when", 0)),
		"who": String(payload.get("who", who_src)),
		"source": src,
		"sig": String(payload.get("sig", "")),
	}


static func _payload_of(h: Dictionary) -> Dictionary:
	return {
		"moving": int(h.get("moving", 0)) & 63,
		"body": int(h.get("body", 0)) & 63,
		"body_moving": int(h.get("body_moving", 0)) & 63,
		"throws": h.get("throws", []),
		"when": int(h.get("when", 0)),
		"who": String(h.get("who", "")),
		"source": String(h.get("source", "tap")),
		"sig": String(h.get("sig", "")),
	}
