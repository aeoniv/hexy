extends Node
class_name MeshFabric
## Store-and-forward event fabric over one or more MeshPeer transports.
##
## A MeshPeer only reaches the peers it can see directly. The fabric turns that
## into a multi-hop mesh: an envelope that arrives for the first time is
## delivered locally AND rebroadcast with ttl-1, so an event from A reaches C
## through B even when A and C never discover each other.
##
## Loop control is the seen-set of eids, not the transport's sequence numbers:
## a relayed event is a *new* transport message with the *same* eid, so every
## node forwards it at most once no matter how many cycles the topology has.
##
## Backend-agnostic by construction: it only ever touches MeshPeer's signals
## and broadcast(), which behave the same over LanMesh and Android IxMesh.

signal fabric_event(src: String, kind: String, body: Dictionary, prov: String)
## Whole envelope, for tests and introspection (ttl, eid). Apps want the above.
signal envelope_received(env: Dictionary)
signal peer_found(id: String, peer_name: String)
## THE NAME CORRECTION (field, m11). A transport beacon names a phone in the
## transport's own id space — Nearby advertises `hexy-` + the first four of
## ANDROID_ID, so the same visitor the door and the radar call `hexy-205c`
## arrived in the workshop's RADIO section as `hexy-1e59`. Two words, one
## person, and no way to tell from the glass that they were the same.
##
## The fabric already holds the only bridge between the two spaces: `_peer_src`,
## learned first-hand from a hops-0 envelope. So the moment that bridge exists
## the fabric re-names the link and says so here, and the name it says is minted
## by `Identity.short_name` off the FABRIC id — the same call presence, the
## radar and the PEERS door make. One source, one word.
signal peer_named(id: String, peer_name: String)
signal peer_lost(id: String)
## Proximity class for a peer, re-keyed from the transport's id to the FABRIC
## id the app knows them by — the only id presence and the radar ever see.
##
## The translation is the whole difficulty. A transport fact ("this link is
## Bluetooth-grade") describes the phone that handed us the bytes; the fabric id
## in an envelope names whoever originally spoke, and after a relay those are
## two different people. So the map is only ever learned from an envelope with
## `hops == 0`: heard first-hand, therefore the same phone. A peer reachable
## only through a relay gets no class at all rather than the relay's, and the
## radar falls back to its documented default for them.
signal peer_proximity(id: String, cls: String)
## Link facts, forwarded with their TRANSPORT id and deliberately not re-keyed.
## The re-keying above exists because a distance class is drawn on the radar
## next to a name; these two are not drawn anywhere. They describe the wire to
## the phone that handed us the bytes, the probe is aimed at that same wire by
## that same id, and translating them into fabric ids would only invite somebody
## to aim a probe at a peer three hops away that no transport can reach.
signal bandwidth_changed(id: String, quality: String)
signal probe_done(id: String, dir: String, bytes: float, seconds: float)

const Envelope := preload("res://scripts/net/event_envelope.gd")
const IdentityScript := preload("res://scripts/social/identity.gd")
const SEEN_CAP := 2048
const DEFAULT_TTL := 3

## Fabric identity: independent of any transport, because after one relay the
## transport id belongs to the relay and only this id still names the origin.
var fabric_id := "%08x%08x" % [randi(), randi()]

var _transports: Array[MeshPeer] = []
var _tokens: Array[String] = []
var _started := false
var _n := 0
var _seen := {}
var _seen_order: Array[String] = []
## transport peer id -> fabric id, learned only from first-hand envelopes.
var _peer_src := {}
## transport peer id -> last class it reported, held until we can name them.
var _peer_cls := {}
## transport peer id -> the ONE word shown for that link. See `peer_named`.
var _peer_names := {}


## Register an extra transport before start(). Each gets its own session token
## so a single node can straddle two otherwise disjoint meshes — that is what
## makes it a relay. Returns the MeshPeer for callers that want its backend.
func add_transport(session_token: String = "") -> MeshPeer:
	var p := MeshPeer.new()
	add_child(p)
	p.peer_found.connect(_on_transport_peer_found)
	p.peer_lost.connect(_on_transport_peer_lost)
	p.peer_proximity.connect(_on_transport_proximity)
	p.event_received.connect(_on_transport_event)
	p.bandwidth_changed.connect(func(id, q): bandwidth_changed.emit(id, q))
	p.probe_done.connect(func(id, d, b, s): probe_done.emit(id, d, b, s))
	_transports.append(p)
	_tokens.append(session_token)
	return p


## Starts every registered transport; registers a default one if none were
## added. Returns OK only if all transports came up.
func start(display_name: String, session_token: String = "") -> Error:
	if _transports.is_empty():
		add_transport(session_token)
	var result := OK
	for i in _transports.size():
		var err := _transports[i].start(display_name, _tokens[i])
		if err != OK:
			result = err
	_started = true
	return result


func stop() -> void:
	for p in _transports:
		p.stop()
	_started = false


func transport_count() -> int:
	return _transports.size()


func peer_count() -> int:
	var n := 0
	for p in _transports:
		n += maxi(0, p.peer_count())
	return n


func backend_name() -> String:
	return _transports[0].backend_name() if not _transports.is_empty() else "none"


## How far away a fabric id is, in hops, or -1 for "not known". Only 0 is ever
## returned as a positive answer, and that is the honest limit of what this node
## learns: `_peer_src` is built exclusively from `hops == 0` envelopes, so a
## fabric id in it is provably on the other end of a transport link we hold. A
## peer reached only through a relay is genuinely unplaced here — the envelope
## carries its own hop count, but nothing keeps a per-source tally, and inventing
## one would be a distance we cannot stand behind. Read-only, no traffic; the
## workshop panel is the only caller.
func hops_of_peer(fabric_peer_id: String) -> int:
	for tid in _peer_src:
		if String(_peer_src[tid]) == fabric_peer_id:
			return 0
	return -1


## Aim the payload probe at a transport peer id. Tries every transport, since
## only the one holding that link will accept it. False = nobody could.
func probe(peer_id: String, total_bytes: int) -> bool:
	for p in _transports:
		if p.probe(peer_id, total_bytes):
			return true
	return false


func probe_chunks(peer_id: String, total_bytes: int, chunk_bytes: int) -> bool:
	for p in _transports:
		if p.probe_chunks(peer_id, total_bytes, chunk_bytes):
			return true
	return false


## Speak in your own voice.
func emit_event(kind: String, body: Dictionary, ttl: int = DEFAULT_TTL) -> Dictionary:
	return _originate(kind, body, ttl, Envelope.PROV_SELF)


## Report what you saw someone else do. Provenance only: the fabric records
## that this node witnessed it and never turns that into a score.
func witness(kind: String, body: Dictionary, ttl: int = DEFAULT_TTL) -> Dictionary:
	return _originate(kind, body, ttl, Envelope.PROV_WITNESSED)


func _originate(kind: String, body: Dictionary, ttl: int, prov: String) -> Dictionary:
	_n += 1
	var eid := "%s:%d" % [fabric_id, _n]
	var env := Envelope.make(eid, fabric_id, kind, body, ttl, prov)
	# Mark our own event seen so a neighbour's relay of it bounces off us.
	_mark_seen(eid)
	_send(env)
	return env


func _send(env: Dictionary) -> void:
	for p in _transports:
		p.broadcast(env)


## A LINK CAME UP. Its beacon word is dropped on the floor on purpose: it was
## minted in the transport's id space and is not the name anything else in the
## app says. Until the first hops-0 envelope names the fabric id behind this
## link there is no name to give, and `short_name("")` — `hexy-?` — is the
## honest placeholder rather than a wrong word that reads as right.
func _on_transport_peer_found(id: String, _beacon_name: String) -> void:
	if not _peer_names.has(id):
		_peer_names[id] = peer_name_of(id)
	peer_found.emit(id, String(_peer_names[id]))


## The one word for a transport link: `Identity.short_name` of the fabric id
## behind it, or `hexy-?` while that is still unknown. Every screen that names a
## link reads through here.
func peer_name_of(transport_id: String) -> String:
	return IdentityScript.short_name(String(_peer_src.get(transport_id, "")))


## Files the fabric id behind a link and, if that changed the word a person
## reads, announces the correction. Called only from a hops-0 envelope.
func _learn_peer_src(peer_id: String, src_id: String) -> void:
	_peer_src[peer_id] = src_id
	if _peer_cls.has(peer_id):
		peer_proximity.emit(src_id, String(_peer_cls[peer_id]))
	var named := peer_name_of(peer_id)
	if String(_peer_names.get(peer_id, "")) != named:
		_peer_names[peer_id] = named
		peer_named.emit(peer_id, named)


func _on_transport_peer_lost(id: String) -> void:
	_peer_src.erase(id)
	_peer_cls.erase(id)
	_peer_names.erase(id)
	peer_lost.emit(id)


## The class lands before we know the peer's fabric id (a connection comes up
## before its first heartbeat), so it is held and re-emitted the moment the
## first-hand envelope names them. Nothing is dropped for arriving early.
func _on_transport_proximity(peer_id: String, cls: String) -> void:
	_peer_cls[peer_id] = cls
	if _peer_src.has(peer_id):
		peer_proximity.emit(String(_peer_src[peer_id]), cls)


func _on_transport_event(peer_id: String, data: Dictionary) -> void:
	if not Envelope.is_valid(data):
		return  # not ours (or malformed); the fabric shares the wire with nothing else yet
	# hops 0 means this envelope came straight from the phone that wrote it —
	# the only case in which a link-level fact about the sending phone may be
	# filed under this fabric id. See the peer_proximity signal above.
	if Envelope.hops_of(data) == 0 and String(data["src"]) != fabric_id:
		var src_id := String(data["src"])
		if String(_peer_src.get(peer_id, "")) != src_id:
			_learn_peer_src(peer_id, src_id)
	var eid: String = data["eid"]
	if _seen.has(eid):
		return
	_mark_seen(eid)
	envelope_received.emit(data)
	fabric_event.emit(data["src"], data["kind"], data["body"], data["prov"])
	# ttl counts hops the event may still travel, so an envelope that arrived
	# with ttl 1 has spent its last hop: deliver it, do not pass it on.
	if Envelope.ttl_of(data) > 1:
		# Rebroadcast on every transport, including the one it arrived on:
		# links are not one broadcast domain, and the receiver's seen-set
		# makes the redundant copy free.
		_send(Envelope.relayed(data))


func _mark_seen(eid: String) -> void:
	_seen[eid] = true
	_seen_order.append(eid)
	while _seen_order.size() > SEEN_CAP:
		_seen.erase(_seen_order.pop_front())


func seen_count() -> int:
	return _seen.size()
