class_name EarthDial2D
extends Control

## THE EARTH REALM: MANUAL CONTROLS & THE EXCLUSIVE HOME OF THE HEXAGRAM.
##
## The head dial is the Moon (human consciousness, breath, and focus).
## The body dial is the Sun (machine sensors, 3D creature tensegrity).
## The Earth dial is the Manual Interference: the 12 app controls on the ring,
## and the CENTRAL CASTING ALTAR which exclusively holds and displays the Hexagram.

signal station_tapped(index: int)
signal hub_tapped()

const STATIONS: Array[Dictionary] = [
	{"index": 0, "angle": -PI * 0.5, "label": "CAST HEAD"},
	{"index": 1, "angle": -PI * 0.5 + TAU * (1.0 / 12.0), "label": "PREV"},
	{"index": 2, "angle": -PI * 0.5 + TAU * (2.0 / 12.0), "label": "NEXT"},
	{"index": 3, "angle": -PI * 0.5 + TAU * (3.0 / 12.0), "label": "MODE"},
	{"index": 4, "angle": -PI * 0.5 + TAU * (4.0 / 12.0), "label": "GEOMETRY"},
	{"index": 5, "angle": -PI * 0.5 + TAU * (5.0 / 12.0), "label": "TELEMETRY"},
	{"index": 6, "angle": -PI * 0.5 + TAU * (6.0 / 12.0), "label": "BRAIN"},
	{"index": 7, "angle": -PI * 0.5 + TAU * (7.0 / 12.0), "label": "PERIOD"},
	{"index": 8, "angle": -PI * 0.5 + TAU * (8.0 / 12.0), "label": "BROADCAST"},
	{"index": 9, "angle": -PI * 0.5 + TAU * (9.0 / 12.0), "label": "CAMERA"},
	{"index": 10, "angle": -PI * 0.5 + TAU * (10.0 / 12.0), "label": "FREEZE"},
	{"index": 11, "angle": -PI * 0.5 + TAU * (11.0 / 12.0), "label": "CONFIG"},
]

const STATION_REACH: float = 24.0
const STATION_RING: float = 0.74
const TICK_INNER: float = 0.88
const CAPTION_PT: int = 9

var hex_bits: int = 2
var hex_num: int = 2
var hex_name: String = "Field"
var hex_zh: String = "坤"
var peers: int = 0
var active_station: int = -1

var dial_center: Vector2 = Vector2.ZERO
var dial_radius: float = 110.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_hexagram(2)


func set_hexagram(bits: int) -> void:
	hex_bits = bits & 63
	hex_num = KingWen.number(hex_bits)
	hex_name = KingWen.name(hex_bits)
	hex_zh = KingWen.zh(hex_bits)
	queue_redraw()


func set_room(bits: int, peer_count: int) -> void:
	var p: int = maxi(0, peer_count)
	if p != peers:
		peers = p
		queue_redraw()


func _measure() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.46


func station_position(index: int) -> Vector2:
	_measure()
	var st: Dictionary = STATIONS[clampi(index, 0, STATIONS.size() - 1)]
	var ang: float = float(st["angle"])
	return dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * STATION_RING)


func hub_radius() -> float:
	_measure()
	return dial_radius * 0.40


func station_label(index: int) -> String:
	return String(STATIONS[clampi(index, 0, STATIONS.size() - 1)]["label"])


func _draw() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.46

	# 1. Outer rim
	draw_arc(dial_center, dial_radius, 0.0, TAU, 96, Color(1.0, 0.55, 0.15, 0.42), 3.0, true)
	draw_arc(dial_center, dial_radius - 18.0, 0.0, TAU, 96, Color(0.25, 0.75, 0.95, 0.3), 1.5, true)

	# 2. 64 graduations
	for i in range(64):
		var ang: float = (float(i) / 64.0) * TAU
		var is_major: bool = (i % 8 == 0)
		var r1: float = dial_radius * TICK_INNER + (0.0 if is_major else 6.0)
		var col: Color = Color(1.0, 0.7, 0.22, 0.9) if is_major else Color(0.3, 0.6, 0.8, 0.45)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dial_center + dir * r1, dial_center + dir * dial_radius, col, 2.0 if is_major else 1.0)

	# 3. 12 Peripheral Stations
	var font: Font = get_theme_default_font()
	for station in STATIONS:
		var idx: int = int(station["index"])
		var ang: float = float(station["angle"])
		var pos: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * STATION_RING)
		var lit: bool = (idx == active_station)
		var d: float = 9.0 if lit else 5.5
		var pts := PackedVector2Array([
			pos + Vector2(0.0, -d), pos + Vector2(d, 0.0),
			pos + Vector2(0.0, d), pos + Vector2(-d, 0.0),
		])
		if lit:
			draw_colored_polygon(pts, Color(1.0, 0.7, 0.22, 0.95))
		else:
			draw_colored_polygon(pts, Color(0.08, 0.18, 0.28, 0.8))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.2, 0.7, 0.9, 0.6), 1.5)
		if font == null:
			continue
		var text: String = String(station["label"])
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT).x
		var inward: Vector2 = (dial_center - pos).normalized()
		var at: Vector2 = pos + inward * 13.0 + Vector2(-w * 0.5, 3.5)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT,
			Color(0.85, 0.92, 0.98, 0.95) if lit else Color(0.55, 0.68, 0.8, 0.7))

	# 4. Central Hub: EXCLUSIVE HOME OF THE HEXAGRAM
	var hub_r: float = hub_radius()
	draw_circle(dial_center, hub_r, Color(0.05, 0.08, 0.13, 0.95))
	draw_arc(dial_center, hub_r, 0.0, TAU, 32, Color(1.0, 0.65, 0.18, 0.9), 2.5, true)
	draw_arc(dial_center, hub_r - 4.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.3, 0.35), 1.0, true)

	# 6 Hexagram Lines
	var line_w: float = hub_r * 1.05
	var line_h: float = 3.5
	var line_gap: float = 4.8
	var start_y: float = dial_center.y - 4.0 + (line_gap * 2.5)

	for line_idx in range(6):
		var y: float = start_y - float(line_idx) * (line_h + line_gap)
		var is_yang: bool = ((hex_bits >> line_idx) & 1) == 1
		var is_upper: bool = line_idx >= 3
		var col: Color = Color(1.0, 0.85, 0.28) if is_upper else Color(1.0, 0.58, 0.18)
		if not is_yang:
			col = col.darkened(0.2)

		if is_yang:
			draw_line(Vector2(dial_center.x - line_w * 0.5, y),
				Vector2(dial_center.x + line_w * 0.5, y), col, line_h)
		else:
			var half: float = line_w * 0.5
			var gap: float = line_w * 0.22
			draw_line(Vector2(dial_center.x - half, y),
				Vector2(dial_center.x - gap * 0.5, y), col, line_h)
			draw_line(Vector2(dial_center.x + gap * 0.5, y),
				Vector2(dial_center.x + half, y), col, line_h)

	# Hexagram Title & Peer Status
	if font != null:
		var hex_title: String = "#%d %s %s" % [hex_num, hex_zh, hex_name]
		var tw: float = font.get_string_size(hex_title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
		draw_string(font, dial_center + Vector2(-tw * 0.5, hub_r * 0.64), hex_title,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(0.9, 0.94, 0.98, 0.95))

		var alt_txt: String = "CAST ALTAR · %dp" % peers
		var cw: float = font.get_string_size(alt_txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
		draw_string(font, dial_center + Vector2(-cw * 0.5, hub_r * 0.84), alt_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.78, 0.3, 0.85))


func _gui_input(event: InputEvent) -> void:
	if not _is_release(event):
		return
	_measure()
	var pos: Vector2 = event.position
	if (pos - dial_center).length() < hub_radius():
		hub_tapped.emit()
		accept_event()
		return
	for station in STATIONS:
		var idx: int = int(station["index"])
		if (pos - station_position(idx)).length() < STATION_REACH:
			active_station = idx
			queue_redraw()
			station_tapped.emit(idx)
			accept_event()
			return


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false
