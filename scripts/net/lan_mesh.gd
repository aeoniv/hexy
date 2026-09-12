extends Node
class_name LanMesh
## Desktop mesh backend: UDP LAN discovery + JSON event datagrams.
## Same wire shape the Android IxMesh plugin will speak (see android_plugin/),
## so callers never know which backend carried the event.

signal peer_found(id: String, peer_name: String)
signal peer_lost(id: String)
signal event_received(id: String, data: Dictionary)
## How near a peer is, as a class rather than metres — see scripts/social/radar.gd.
## THE RIG'S HONEST ANSWER: a LAN has no proximity at all, so this backend
## reports the one spatial fact it genuinely holds — a peer whose datagrams come
## from this machine's own loopback IS in the same place we are, because it is
## the same machine. That is "touch". Everything else on the LAN is somewhere in
## the building and gets "room". No RSSI is invented.
signal peer_proximity(id: String, cls: String)

const PORTS := [46464, 46465, 46466, 46467]
const BEACON_INTERVAL := 1.0
const PEER_TIMEOUT := 4.0

var my_id := "%08x" % (randi() | 1)
var my_name := "hexy"
var _sock := PacketPeerUDP.new()
var _port := 0
var _seq := 0
var _beacon_t := 0.0
var _peers := {}
var _seen := {}
## Optional per-run session token. Defaults to "" which accepts any peer,
## matching prior behavior. Callers that need to isolate a mesh from other
## hexy instances on the same LAN (e.g. automated tests) can pass a unique
## token here; only peers advertising the same token are discovered, and
## only discovered peers' events are accepted.
var _token := ""


func start(display_name: String, session_token: String = "") -> Error:
	my_name = display_name
	_token = session_token
	for p in PORTS:
		if _sock.bind(p) == OK:
			_port = p
			break
	if _port == 0:
		return ERR_CANT_CREATE
	_sock.set_broadcast_enabled(true)
	set_process(true)
	return OK


func stop() -> void:
	set_process(false)
	_sock.close()
	_peers.clear()


func broadcast(data: Dictionary) -> void:
	_seq += 1
	var msg := JSON.stringify({"k": "ev", "id": my_id, "seq": _seq, "data": data})
	for pid in _peers:
		_send(msg, _peers[pid].ip, _peers[pid].port)


func peer_count() -> int:
	return _peers.size()


func _process(delta: float) -> void:
	_beacon_t -= delta
	if _beacon_t <= 0.0:
		_beacon_t = BEACON_INTERVAL
		var hello := JSON.stringify({"k": "hi", "id": my_id, "name": my_name, "port": _port, "tok": _token})
		for p in PORTS:
			_send(hello, "255.255.255.255", p)
			_send(hello, "127.0.0.1", p)
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var from_ip := _sock.get_packet_ip()
		var parsed = JSON.parse_string(pkt.get_string_from_utf8())
		if parsed is Dictionary:
			_handle(parsed, from_ip)
	var now := Time.get_ticks_msec() / 1000.0
	for pid in _peers.keys():
		if now - _peers[pid].last_seen > PEER_TIMEOUT:
			_peers.erase(pid)
			peer_lost.emit(pid)


func _handle(m: Dictionary, from_ip: String) -> void:
	var pid: String = m.get("id", "")
	if pid == "" or pid == my_id:
		return
	match m.get("k", ""):
		"hi":
			if m.get("tok", "") != _token:
				return
			var fresh := not _peers.has(pid)
			_peers[pid] = {"ip": from_ip, "port": int(m.get("port", 0)),
				"name": m.get("name", "?"), "last_seen": Time.get_ticks_msec() / 1000.0}
			if fresh:
				peer_found.emit(pid, m.get("name", "?"))
				peer_proximity.emit(pid, "touch" if _same_host(from_ip) else "room")
		"ev":
			# Only accept events from peers we've already discovered via a
			# matching "hi" beacon. This keeps unassociated LAN traffic
			# (other hexy instances, stray broadcasts) from injecting
			# events into a mesh it never joined.
			if not _peers.has(pid):
				return
			_peers[pid].last_seen = Time.get_ticks_msec() / 1000.0
			var key := "%s:%d" % [pid, int(m.get("seq", 0))]
			if _seen.has(key):
				return
			_seen[key] = true
			var data = m.get("data", {})
			if data is Dictionary:
				event_received.emit(pid, data)


## True when a peer's datagrams came from this very machine. The desktop rig
## runs two instances side by side, and they are not near each other — they are
## in the same place. Loopback first, then our own interface addresses, because
## a broadcast to 255.255.255.255 comes back stamped with the LAN address.
func _same_host(ip: String) -> bool:
	if ip.begins_with("127.") or ip == "::1":
		return true
	return IP.get_local_addresses().has(ip)


func _send(msg: String, ip: String, port: int) -> void:
	_sock.set_dest_address(ip, port)
	_sock.put_packet(msg.to_utf8_buffer())
