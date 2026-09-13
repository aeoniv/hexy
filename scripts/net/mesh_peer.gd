extends Node
class_name MeshPeer
## The mesh seam. Callers use this node only; the backend is chosen at start():
## the Android IxMesh singleton (Nearby Connections) when present, else the
## desktop LAN backend. Events are Dictionaries; frames never cross the mesh.

signal peer_found(id: String, peer_name: String)
signal peer_lost(id: String)
signal event_received(id: String, data: Dictionary)
## A rough near/far class for a transport peer — "touch" / "room" / "far", never
## metres. ROADMAP Phase 3 ladder 1b. Both backends emit it; neither invents a
## number. See IxMesh.kt (Nearby bandwidth quality) and LanMesh (same host).
signal peer_proximity(id: String, cls: String)
## The raw Nearby bandwidth class name — "UNKNOWN" / "LOW" / "MEDIUM" / "HIGH".
## `peer_proximity` above is this same fact spent on a distance word; the probe
## needs the fact itself, because HIGH is the whole question. Android only: the
## desktop LAN backend has no medium to negotiate and says nothing.
signal bandwidth_changed(id: String, quality: String)
## A finished payload probe: direction is "sent", "received" or "failed".
signal probe_done(id: String, dir: String, bytes: float, seconds: float)

## THE HANDSHAKE IS NO LONGER SPELLED HERE. `scripts/seam.gd` is still what
## runs it; the adapter below is what calls it, with the NEEDS on the next line.
## THE AAR THIS SCRIPT WAS WRITTEN AGAINST. Compared with the plugin's own
## `plugin_version()` at attach; see `scripts/seam.gd` for why a mismatch is
## worth a loud line and a degrade rather than a shrug.
const NEEDS := "ixmesh/1"
## THE ONE DOOR TO IxMesh. Refactor R5.
const MeshAdapterScript = preload("res://scripts/adapters/mesh_adapter.gd")

var _android: Object = null
var _door := MeshAdapterScript.new(NEEDS, "mesh", "nearby", "lan")
var force_lan: bool = false
var _lan: LanMesh = null


## session_token isolates this peer from other hexy instances sharing the LAN
## (used by the test rig to build deliberate topologies). The Android backend
## has no equivalent knob today, so it ignores the token — honest, not silent:
## on device every peer in range is a candidate, as Nearby intends.
func start(display_name: String, session_token: String = "") -> Error:
	if _door.present() and not force_lan:
		# THE VERSION HANDSHAKE happens inside the adapter. A stale ixmesh under a
		# fresh script is the silent failure `scripts/seam.gd` exists for; on a
		# mismatch this peer refuses rather than half-speaking Nearby.
		_android = _door.attach()
		if _android == null:
			return ERR_UNAVAILABLE
		_android.connect("peer_found", func(id, n): peer_found.emit(id, n))
		_android.connect("peer_lost", func(id): peer_lost.emit(id))
		_android.connect("event_received", func(id, json):
			var d = JSON.parse_string(json)
			if d is Dictionary:
				event_received.emit(id, d))
		# Optional on the plugin side: an older AAR on the phone has no such
		# signal, and connecting to one that does not exist is an error, not a
		# no-op. Without it the radar simply falls back to its honest default.
		if _android.has_signal("peer_proximity"):
			_android.connect("peer_proximity", func(id, cls): peer_proximity.emit(id, cls))
		else:
			push_warning("IxMesh has no peer_proximity signal — rebuild the AAR")
		# Same optionality, same reason: an older AAR on the phone has neither.
		if _android.has_signal("bandwidth_changed"):
			_android.connect("bandwidth_changed", func(id, q): bandwidth_changed.emit(id, q))
		if _android.has_signal("probe_done"):
			_android.connect("probe_done", func(id, dir, b, s): probe_done.emit(id, dir, b, s))
		# start() re-announces what it already knows, so it is called LAST, after
		# every connect above — that ordering is the whole point of the handshake.
		_android.call("start", display_name)
		return OK
	_lan = LanMesh.new()
	add_child(_lan)
	_lan.peer_found.connect(func(id, n): peer_found.emit(id, n))
	_lan.peer_lost.connect(func(id): peer_lost.emit(id))
	_lan.event_received.connect(func(id, d): event_received.emit(id, d))
	_lan.peer_proximity.connect(func(id, cls): peer_proximity.emit(id, cls))
	return _lan.start(display_name, session_token)


func stop() -> void:
	if _android:
		_android.call("stop")
	elif _lan:
		_lan.stop()


func broadcast(data: Dictionary) -> void:
	if _android:
		_android.call("broadcast", JSON.stringify(data))
	elif _lan:
		_lan.broadcast(data)


## Directly reachable peers. The Android backend keeps its own roster and
## exposes no count yet, so this reports -1 there rather than lying with 0.
func peer_count() -> int:
	if _android:
		return -1
	return _lan.peer_count() if _lan else 0


func backend_name() -> String:
	return "nearby" if _android else "lan"


## Fire a bulk payload at one transport peer and time it — ROADMAP Phase 4's
## Wi-Fi-upgrade probe. Returns false off Android, where there is no medium to
## upgrade and therefore nothing this could honestly measure.
##
## `has_method()` is deliberately NOT used to guard the call: a JNISingleton
## answers false for every @UsedByGodot method, so the guard would swallow the
## probe on exactly the device it exists for.
func probe(id: String, total_bytes: int) -> bool:
	if _android == null:
		return false
	return bool(_android.call("probe_send", id, total_bytes))


## The same probe sent as a run of capped BYTES payloads instead of one stream.
## Slower by its own framing and honest about delivery, where the stream is fast
## and only honest about the hand-off. See the comment on `ChunkRun` in
## IxMesh.kt for why both exist.
func probe_chunks(id: String, total_bytes: int, chunk_bytes: int) -> bool:
	if _android == null:
		return false
	return bool(_android.call("probe_send_chunks", id, total_bytes, chunk_bytes))


## Endpoint ids Nearby has us connected to right now. Empty off Android.
func connected_peers() -> PackedStringArray:
	if _android == null:
		return PackedStringArray()
	var s := String(_android.call("connected_peers"))
	return PackedStringArray() if s.is_empty() else s.split(",")
