extends Node
## Hexy RF Sense — Ingests contactless WiFi CSI vitals from the Hexy ESP32 Radar Node.
##
## Listens on UDP port 8124 (bench simulation & local Wi-Fi) or binds to the
## native Android BLE singleton `IxRf` if available on device.
##
## Emits telemetry signals for Hexy's body state, breathing rhythm, and room radar.

signal vitals_updated(presence: int, bpm: int, motion: int, flags: int)
signal presence_changed(is_present: bool)
signal breathing_changed(bpm: int)
signal fall_detected()

const MAGIC := 0x4858 # "HX"
const VERSION := 1
const DEFAULT_PORT := 8124

var _udp_server: PacketPeerUDP
var _is_listening: bool = false
var _last_presence: bool = false
var _last_bpm: int = 0
var _node_seq: int = 0
var _node_uptime_s: int = 0

func _ready() -> void:
	start_listening()

func start_listening(port: int = DEFAULT_PORT) -> void:
	# 1. Check if native Android BLE singleton exists
	if Engine.has_singleton("IxRf"):
		var ix_rf = Engine.get_singleton("IxRf")
		if ix_rf.has_signal("vitals_received"):
			ix_rf.connect("vitals_received", Callable(self, "_on_ble_vitals_received"))
		ix_rf.start_scan()
		print("[RFSense] Bound to native Android BLE IxRf singleton")

	# 2. Also start UDP receiver for bench testing / simulator
	_udp_server = PacketPeerUDP.new()
	var err = _udp_server.bind(port)
	if err == OK:
		_is_listening = true
		print("[RFSense] UDP listener bound on port %d" % port)
	else:
		push_warning("[RFSense] Could not bind UDP port %d: %s" % [port, error_string(err)])

func _process(_delta: float) -> void:
	if not _is_listening or _udp_server == null:
		return

	while _udp_server.get_available_packet_count() > 0:
		var pkt = _udp_server.get_packet()
		if pkt.size() >= 16:
			_parse_binary_packet(pkt)

func _parse_binary_packet(data: PackedByteArray) -> void:
	var sp = StreamPeerBuffer.new()
	sp.data_array = data
	sp.big_endian = false # Little-endian matching struct

	var magic = sp.get_u16()
	if magic != MAGIC:
		return

	var version = sp.get_u8()
	if version != VERSION:
		return

	var presence = sp.get_u8()
	var bpm = sp.get_u8()
	var motion = sp.get_u8()
	var flags = sp.get_u8()
	var _battery = sp.get_u8()
	var _variance = sp.get_u16()
	var seq = sp.get_u16()
	var uptime_ms = sp.get_u32()

	_node_seq = seq
	_node_uptime_s = int(uptime_ms / 1000)

	_dispatch_vitals(presence, bpm, motion, flags)

func _on_ble_vitals_received(presence: int, bpm: int, motion: int, flags: int) -> void:
	_dispatch_vitals(presence, bpm, motion, flags)

func _dispatch_vitals(presence: int, bpm: int, motion: int, flags: int) -> void:
	emit_signal("vitals_updated", presence, bpm, motion, flags)

	var is_present = presence >= 40
	if is_present != _last_presence:
		_last_presence = is_present
		emit_signal("presence_changed", is_present)

	if bpm > 0 and bpm != _last_bpm:
		_last_bpm = bpm
		emit_signal("breathing_changed", bpm)

	if (flags & 0x01) != 0:
		emit_signal("fall_detected")

func stop_listening() -> void:
	if _udp_server:
		_udp_server.close()
	_is_listening = false
	if Engine.has_singleton("IxRf"):
		Engine.get_singleton("IxRf").stop_scan()
