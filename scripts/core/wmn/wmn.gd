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
const HexyMsgScript := preload("res://scripts/core/msg.gd")
const HexyTopicScript := preload("res://scripts/core/topic.gd")

## HOW CLOSE TWO CIRCADIAN PHASES HAVE TO BE to be called the same hour: a
## tenth of the day, which is a bit under two and a half hours.
const PHASE_WINDOW: float = 0.1

## Throttle for the pheromone Sense a received figure turns into: one per
## peer per second, so a room full of hexys does not flood the brain bus at
## figure-cast rate. (see _take_figure / _publish_pheromone)
const PHEROMONE_PERIOD_MS := 1000

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
## THE ORGANISM'S OWN BEAT, and it is not the room's. A figure is news and goes
## out when it changes; a heading is a continuous fact and goes out on a clock,
## twice a second, which is fast enough for a swarm to turn together and slow
## enough that a pocketful of phones is not a radio.
const BIO_PERIOD_MS := 500

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
## The brain-bus topic, when a caller has one to attach. Out: broadcast() reads
## the latched "/body" msg (HexyMsg.KIND_BODY) to put on the wire instead of
## inventing one from store bits alone. In: each received figure becomes a
## "pheromone" Sense published on this bus, throttled per peer. Optional --
## a wmn with no bus attached still works exactly as before (store-only).
var _bus: Object = null
## fabric src id -> the wire's whole word: a HexyMsg Body reconstructed from
## payload["bw"] (body_from_wire), the fields peers() also exposes.
var _peer_body_msg := {}
## fabric src id -> next ms this node is allowed to publish a pheromone
## Sense for them. See PHEROMONE_PERIOD_MS.
var _pheromone_next_ms := {}
## Whether the bio pulse goes out at all. A test that only wants figures on the
## wire turns it off; the app leaves it on.
var bio_pulse := true
var _bio_next_ms := 0
## WHERE THIS BODY IS IN ITS OWN DAY AND ITS OWN STORY, as somebody else worked
## it out. Wmn computes neither: the phase comes from the entrainment estimator
## and the stage from the journey map, and this node's whole job is to put what
## they say on the wire beside the heading. -1/-1 until a caller speaks, which
## is the wire's word for "this phone does not know".
var _own_phase := -1.0
var _own_stage := -1


## The one door for the two facts above. A caller that knows only the phase
## passes the stage it already set, so nothing is blanked by half an answer.
func set_own_phase(phase: float = -1.0, stage: int = -1) -> void:
	_own_phase = phase
	_own_stage = stage


func own_phase() -> float:
	return _own_phase


func own_stage() -> int:
	return _own_stage


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
## THE ROOM VOTES ON HEADS, and on heads only: byte 0 of the wire word is this
## hexy's HEAD and nothing else may be put there. `earth` is the altar, an
## optional passenger -- it rides in the payload under its own name so a peer
## that cares can read it and the vote never sees it.
func broadcast(head: Dictionary, body: Dictionary, earth: Dictionary = {}) -> Dictionary:
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
	if not earth.is_empty():
		payload["earth"] = int(earth.get("bits", 0)) & 63
		payload["earth_moving"] = int(earth.get("moving", 0)) & 63
	## THE ONE BODY SHAPE ON THE WIRE, ALONGSIDE THE LEGACY ENVELOPE.
	## "bw" (body-wire) is HexyMsg.body_to_wire() of the organism's own Body:
	## the latched "/body" topic message when a bus is attached, or -- no
	## bus, or nothing latched yet -- a Body minted from the store bits this
	## same payload already carries under "body" (the legacy trigram byte).
	## See the class doc comment for the legacy-vs-Body key table.
	var msg_body: Dictionary = {}
	if _bus != null and _bus.has_method("last"):
		msg_body = _bus.last(HexyTopicScript.TOPIC_BODY)
	if msg_body.is_empty():
		msg_body = HexyMsgScript.body_from_bits(int(body.get("bits", 0)) & 63)
	payload["bw"] = HexyMsgScript.body_to_wire(msg_body)
	_self_h = _figure_from(fabric.fabric_id, bits, payload)
	room.set_self(bits, moving, now_ms(), fabric.fabric_id)
	if keep_ledger:
		ledger.append(_self_h, [])
	presence.force_due()
	presence.due(now_ms())
	## ONE LINE PER PULSE ON THE WIRE, for a device pass to grep out of logcat.
	print("hexy.wire tx head=%d body=%d" % [bits, int(payload.get("body", 0))])
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
			{"s": Clock.now_ms(), "e": echo})},
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
	var msg_body: Dictionary = {}
	if payload.has("bw") and typeof(payload["bw"]) == TYPE_DICTIONARY:
		msg_body = HexyMsgScript.body_from_wire(payload["bw"], now_ms() * 1000000)
		_peer_body_msg[src] = msg_body
	## ONE LINE PER FIGURE HEARD, same grep, the other direction.
	print("hexy.wire rx %s bits=%d" % [src, bits & 63])
	peer_figure.emit(src, h)
	_publish_room()
	if not msg_body.is_empty():
		_publish_pheromone(src, msg_body)


## "wmn shows the body to peers, and brings peers in as a sense": every
## received Body becomes a "pheromone" Sense on the brain bus, throttled to
## once a second per peer -- see PHEROMONE_PERIOD_MS. value is the peer's
## Body as heard; meta names who it was, how close (band), and whether their
## circadian phase agrees with ours closely enough to call it "in phase".
func _publish_pheromone(src: String, msg_body: Dictionary) -> void:
	if _bus == null or not _bus.has_method("publish"):
		return
	var now := now_ms()
	if now < int(_pheromone_next_ms.get(src, 0)):
		return
	_pheromone_next_ms[src] = now + PHEROMONE_PERIOD_MS
	var their_phase: Variant = peer_phase().get(src, null)
	var in_phase := false
	if their_phase != null and _own_phase >= 0.0:
		in_phase = phase_gap(float(their_phase), _own_phase) < PHASE_WINDOW
	print("hexy.pheromone %s in_phase=%s" % [src, str(in_phase)])
	var meta := {
		"who": src,
		"band": String(peer_proximity().get(src, "")),
		"in_phase": in_phase,
		"phase": their_phase,
		"stage": peer_stage().get(src, null),
	}
	_bus.publish(HexyTopicScript.TOPIC_SENSE,
		HexyMsgScript.sense("pheromone", "radio", now * 1000000, msg_body, meta))


## HOW FAR APART TWO PHASES ARE, ROUND THE DAY. A phase is a point on a CIRCLE
## and 0.0 and 1.0 are the same midnight, so the distance between them is the
## short way round -- never the straight subtraction, which said two phones a
## few minutes either side of midnight (0.99 and 0.01) were nearly a whole day
## apart and refused to call them in phase. Always in 0..0.5.
static func phase_gap(a: float, b: float) -> float:
	var d: float = fposmod(a - b, 1.0)
	return minf(d, 1.0 - d)


func _take_chirp(src: String, payload: Dictionary) -> void:
	var t3 := int(payload.get("s", 0))
	var t4 := Clock.now_ms()
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
	var cls_by_who: Dictionary = peer_proximity()
	var headings: Dictionary = peer_headings()
	var phases: Dictionary = peer_phase()
	var stages: Dictionary = peer_stage()
	var out: Array = []
	for who in room.names():
		var p: Dictionary = room.peers[who]
		# The Body last heard on a wmn6 figure's "bw" key (see broadcast()),
		# when this peer has ever sent one. Falls back to {} -- the bio-pulse
		# fields below (headings/phases/stages) still carry heading/phase/
		# stage even for a peer whose figures never included a Body.
		var bm: Dictionary = _peer_body_msg.get(who, {})
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
			# touch/room/far, or "" when the fabric has not placed this peer
			# yet -- see MeshFabric.peer_proximity_by_src.
			"cls": String(cls_by_who.get(who, "")),
			# radians: the Body's heading when one arrived, else the bio
			# pulse's, else null when neither has ever been heard.
			"heading_rad": bm.get("heading_rad", headings.get(who, null)),
			# 0..1 of their internal day, or null when that phone runs no
			# estimator yet -- never a guessed midnight.
			"phase": phases.get(who, null),
			# Which chapter of the journey they are in, or null when unsaid.
			"stage": stages.get(who, null),
			# The Body's six needs, as last received, or [] when this peer
			# has never sent one -- see HexyMsg.body_to_wire/body_from_wire.
			"lines": bm.get("lines", []),
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
	## W10c REMOVED hud3's OWN BROADCAST OF THE ALTAR: the store is the one
	## writer of `earth` now, so the mesh must hear it directly or a peer
	## never learns a station changed.
	if store.has_signal("earth_changed") and not store.earth_changed.is_connected(_on_store_earth):
		store.earth_changed.connect(_on_store_earth)
	var h: Dictionary = store.hexagram
	if int(h.get("bits", 0)) != 0 or int(h.get("moving", 0)) != 0 or store.head_bits() != 0:
		broadcast_figure(h)


## Wire this mesh to the brain-bus topic (HexyTopic), if the caller has one.
## Optional and separate from bind(store): a wmn with a store but no bus still
## broadcasts and receives, just without the Body wire shape or pheromone
## Senses. Pass null to detach.
func attach_bus(topic: Object) -> void:
	_bus = topic


## Whether a bus has been latched via attach_bus(). Lets a boot-wiring test
## assert the wire actually happened without reaching into _bus directly.
func has_bus() -> bool:
	return _bus != null


func unbind() -> void:
	if _store != null and _store.hexagram_changed.is_connected(_on_store_hexagram):
		_store.hexagram_changed.disconnect(_on_store_hexagram)
	if _store != null and _store.head_changed.is_connected(_on_store_head):
		_store.head_changed.disconnect(_on_store_head)
	if _store != null and _store.has_signal("earth_changed") \
			and _store.earth_changed.is_connected(_on_store_earth):
		_store.earth_changed.disconnect(_on_store_earth)
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


## THE ALTAR MOVED. The head and body go out unchanged beside it; W10c made
## the store the earth's one writer, so this is the only path a peer's copy
## of the earth can move on.
func _on_store_earth(e: Dictionary) -> void:
	if _binding or _store == null:
		return
	broadcast(_store.head, _store.body, e)


## -- THE BEAT ----------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _started:
		return
	var now := now_ms()
	var gone := room.expire(now)
	for who in gone:
		_heard.erase(who)
		_peer_body.erase(who)
		_peer_body_msg.erase(who)
		_pheromone_next_ms.erase(who)
		peer_gone.emit(who)
	if not gone.is_empty():
		_publish_room()
	_bio_beat(now)
	if presence.due(now):
		send_chirp()
		if not _self_h.is_empty():
			fabric.emit_event(WIRE_KIND,
				{WIRE_KEY: Envelope6.to_wire(Envelope6.KIND_FIGURE,
					int(_self_h["bits"]), _payload_of(_self_h))},
				FIGURE_TTL)


## -- THE ORGANISM ON THE WIRE ------------------------------------------------

## Twice a second: the body's heading and breath and the six-line habit go out
## to the room, and the room's answer comes back as one number -- the Kuramoto
## coupling, written into the store as `swarm_yaw`. That is the whole feedback
## loop, and it is the reason the coupling exists: the sensor oracle adds
## `store.swarm_yaw` to the gyro yaw rate it samples, so a phone standing in a
## room of hexys is turned, a little, by the ones around it.
func _bio_beat(now: int) -> void:
	if not bio_pulse or fabric == null or _store == null:
		return
	if now < _bio_next_ms:
		return
	_bio_next_ms = now + BIO_PERIOD_MS
	var fly: Dictionary = _fly_state()
	if fly.is_empty():
		return
	var heading := float(fly.get("heading_rad", 0.0))
	# THE DRAWER DECIDES WHAT THE CUBE COSTS ON THE WIRE: whether it rides at
	# all, and how many corners of it. No config, no change from before.
	var mass: PackedFloat32Array = _q6_mass()
	var topk: int = 0
	var cfg: HexyConfig = HexyConfig.peek()
	if cfg != null:
		if not bool(cfg.get_value("mesh.q6_on_wire")):
			mass = PackedFloat32Array()
		topk = int(cfg.get_value("mesh.q6_topk"))
	fabric.broadcast_bio_state(
		heading,
		float(fly.get("octopamine", 0.5)),
		(fly.get("habit_bias", []) as Array),
		mass, topk, _own_phase, _own_stage)
	if _store.has_method("set_swarm_yaw"):
		_store.set_swarm_yaw(fabric.compute_kuramoto_coupling(heading))


## The character's state, duck-typed. A store too old to have one is silent.
func _fly_state() -> Dictionary:
	if _store == null or not _store.has_method("get_character"):
		return {}
	var ch: Variant = _store.get_character()
	if ch == null or not ch.has_method("get_fly_state"):
		return {}
	return ch.get_fly_state() as Dictionary


## The 64-corner Q6 mass, IF the store has learned to publish one. It does not
## today -- the cloud lives in Alchemy's Pacing, not in the store -- so this is
## the seam rather than the feature, and the payload simply carries no `q6`.
func _q6_mass() -> PackedFloat32Array:
	if _store != null and _store.has_method("q6_mass"):
		var raw: Variant = _store.q6_mass()
		if raw is PackedFloat32Array:
			return raw
		if raw is Array or raw is PackedFloat64Array:
			var out := PackedFloat32Array()
			for v in raw:
				out.append(float(v))
			return out
	return PackedFloat32Array()


## What the swarm is saying, for a glass that wants to draw it: peer id ->
## heading in radians, and peer id -> their last whole bio payload.
func peer_headings() -> Dictionary:
	return fabric.peer_headings if fabric != null else {}


func peer_bio() -> Dictionary:
	return fabric.peer_bio if fabric != null else {}


## peer id -> 0..1 of their own day, and peer id -> their journey chapter. Only
## peers who actually said; see MeshFabric.peer_phase_by_src.
func peer_phase() -> Dictionary:
	return fabric.peer_phase_by_src() if fabric != null else {}


func peer_stage() -> Dictionary:
	return fabric.peer_stage_by_src() if fabric != null else {}


## peer id -> "touch" / "room" / "far", the radar's ring for each blip.
func peer_proximity() -> Dictionary:
	return fabric.peer_proximity_by_src() if fabric != null else {}


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
