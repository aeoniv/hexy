class_name EarthDial2D
extends Control

## THE EARTH REALM: MANUAL CONTROLS & THE EXCLUSIVE HOME OF THE HEXAGRAM.
##
## The head dial is the Moon (human consciousness, focus, and thought).
## The body dial is the Sun (machine physical sensors, 3D creature tensegrity).
## The Earth dial is the Manual Interference: the 12 app controls on the ring,
## and the CENTRAL CASTING ALTAR which exclusively holds and displays the Hexagram.
##
## FULL INTERACTIVITY:
## 1. Dragging spins the 64-hexagram wheel smoothly, snapping on release.
## 2. Tapping the outer rim directly selects that hexagram slot.
## 3. Tapping the center hub triggers the Master Casting Altar.
## 4. Tapping any of the 12 peripheral stations triggers that app control.

signal station_tapped(index: int)
signal hub_tapped()
signal ring_slot_tapped(slot: int)
signal dial_dragged(delta_ang: float)

const STATIONS: Array[Dictionary] = [
	{"index": 0, "angle": -PI * 0.5, "label": "CAST ALTAR"},
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

const STATION_REACH: float = 46.0
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
var dial_angle: float = 0.0
var target_dial_angle: float = 0.0
var current_hex_index: int = 0

var _is_dragging: bool = false
var _touch_down_pos: Vector2 = Vector2.ZERO
var _touch_down_time: int = 0
var _drag_start_angle: float = 0.0
var _has_moved: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_hexagram(2)


func set_hexagram(bits: int) -> void:
	hex_bits = bits & 63
	hex_num = KingWen.number(hex_bits)
	hex_name = KingWen.name(hex_bits)
	hex_zh = KingWen.zh(hex_bits)
	current_hex_index = HuohoutuData.find_head_index_by_id(hex_num)
	target_dial_angle = -float(current_hex_index) * (TAU / 64.0)
	dial_angle = target_dial_angle
	queue_redraw()


func earth_slot() -> int:
	return current_hex_index


func set_earth_slot(slot: int) -> void:
	current_hex_index = posmod(slot, 64)
	dial_angle = -float(current_hex_index) * (TAU / 64.0)
	target_dial_angle = dial_angle
	var id: int = HuohoutuData.HEAD_SEQUENCE[current_hex_index] if current_hex_index < HuohoutuData.HEAD_SEQUENCE.size() else 2
	var h: Dictionary = HuohoutuData.get_head_hex(current_hex_index)
	set_hexagram(int(h.get("bits", 2)))


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
	return dial_radius * 0.44


func station_label(index: int) -> String:
	return String(STATIONS[clampi(index, 0, STATIONS.size() - 1)]["label"])


func slot_at(point: Vector2) -> int:
	var ang: float = (point - dial_center).angle()
	var step: float = TAU / 64.0
	return posmod(int(round((ang - dial_angle) / step)), 64)


func _draw() -> void:
	_measure()

	# 1. Outer rim
	draw_arc(dial_center, dial_radius, 0.0, TAU, 96, Color(1.0, 0.55, 0.15, 0.45), 3.0, true)
	draw_arc(dial_center, dial_radius - 18.0, 0.0, TAU, 96, Color(0.25, 0.75, 0.95, 0.3), 1.5, true)

	# 2. 64 graduations with dial_angle rotation
	for i in range(64):
		var ang: float = dial_angle + (float(i) / 64.0) * TAU
		var is_major: bool = (i % 8 == 0)
		var r1: float = dial_radius * TICK_INNER + (0.0 if is_major else 6.0)
		var col: Color = Color(1.0, 0.75, 0.25, 0.95) if is_major else Color(0.3, 0.65, 0.85, 0.45)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dial_center + dir * r1, dial_center + dir * dial_radius, col, 2.0 if is_major else 1.0)

	# Top cursor pointer (12 o'clock)
	var ptr_top := dial_center + Vector2(0.0, -dial_radius - 8.0)
	var ptr_pts := PackedVector2Array([
		ptr_top,
		ptr_top + Vector2(-6.0, -10.0),
		ptr_top + Vector2(6.0, -10.0)
	])
	draw_colored_polygon(ptr_pts, Color(1.0, 0.75, 0.25, 0.95))

	# 3. 12 Peripheral Stations (arranged around the ring)
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
			draw_colored_polygon(pts, Color(1.0, 0.75, 0.22, 0.98))
		else:
			draw_colored_polygon(pts, Color(0.08, 0.18, 0.28, 0.85))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.25, 0.75, 0.95, 0.65), 1.5)
		if font == null:
			continue
		var text: String = String(station["label"])
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT).x
		var inward: Vector2 = (dial_center - pos).normalized()
		var at: Vector2 = pos + inward * 13.0 + Vector2(-w * 0.5, 3.5)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT,
			Color(0.92, 0.96, 1.0, 0.98) if lit else Color(0.6, 0.72, 0.84, 0.78))

	# 4. Central Hub: EXCLUSIVE HOME OF THE HEXAGRAM (MAXIMIZED SYMBOL ONLY)
	var hub_r: float = hub_radius()
	draw_circle(dial_center, hub_r, Color(0.05, 0.08, 0.13, 0.96))
	draw_arc(dial_center, hub_r, 0.0, TAU, 48, Color(1.0, 0.65, 0.18, 0.95), 2.5, true)
	draw_arc(dial_center, hub_r - 4.0, 0.0, TAU, 48, Color(1.0, 0.82, 0.3, 0.35), 1.0, true)

	# 6 Hexagram Lines Maximized
	var line_w: float = hub_r * 1.30
	var line_h: float = 4.5
	var line_gap: float = 6.5
	var start_y: float = dial_center.y + (2.5 * (line_h + line_gap))

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

func _gui_input(event: InputEvent) -> void:
	_measure()
	var is_press: bool = false
	var is_release: bool = false
	var is_move: bool = false
	var ev_pos: Vector2 = Vector2.ZERO

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		ev_pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenTouch:
		ev_pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		ev_pos = event.position
		is_move = true

	if is_press:
		_is_dragging = true
		_touch_down_pos = ev_pos
		_touch_down_time = int(Time.get_ticks_msec())
		_has_moved = false
		var dir: Vector2 = ev_pos - dial_center
		_drag_start_angle = dir.angle() - dial_angle
		accept_event()
		return

	if is_move and _is_dragging:
		if (ev_pos - _touch_down_pos).length() > 12.0:
			_has_moved = true
		var dir: Vector2 = ev_pos - dial_center
		var cur_angle: float = dir.angle() - _drag_start_angle
		var delta_ang: float = wrapf(cur_angle - dial_angle, -PI, PI)
		dial_angle = cur_angle
		target_dial_angle = dial_angle
		dial_dragged.emit(delta_ang)
		var step_rad := TAU / 64.0
		var new_idx: int = posmod(int(round(-dial_angle / step_rad)), 64)
		if new_idx != current_hex_index:
			current_hex_index = new_idx
			var id: int = HuohoutuData.HEAD_SEQUENCE[current_hex_index] if current_hex_index < HuohoutuData.HEAD_SEQUENCE.size() else 2
			var h = HuohoutuData.get_head_hex(current_hex_index); set_hexagram(int(h.get("bits", 2)))
			ring_slot_tapped.emit(new_idx)
		queue_redraw()
		accept_event()
		return

	if is_release:
		var was_drag: bool = _is_dragging and _has_moved
		_is_dragging = false
		_has_moved = false
		if was_drag:
			var step_rad := TAU / 64.0
			current_hex_index = posmod(int(round(-dial_angle / step_rad)), 64)
			target_dial_angle = -float(current_hex_index) * step_rad
			dial_angle = target_dial_angle
			var id: int = HuohoutuData.HEAD_SEQUENCE[current_hex_index] if current_hex_index < HuohoutuData.HEAD_SEQUENCE.size() else 2
			var h = HuohoutuData.get_head_hex(current_hex_index); set_hexagram(int(h.get("bits", 2)))
			ring_slot_tapped.emit(current_hex_index)
			queue_redraw()
			accept_event()
			return

		# Tap detection
		var dist: float = (ev_pos - dial_center).length()

		# A. Center Hub tap: Cast Altar
		if dist < hub_radius():
			hub_tapped.emit()
			Input.vibrate_handheld(30)
			accept_event()
			return

		# B. Station Tap: check 12 stations
		var closest_idx: int = -1
		var closest_dist: float = 9999.0
		for station in STATIONS:
			var idx: int = int(station["index"])
			var ang: float = float(station["angle"])
			var pos: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * STATION_RING)
			var d: float = (ev_pos - pos).length()
			if d < closest_dist:
				closest_dist = d
				closest_idx = idx

		if closest_idx != -1 and closest_dist < STATION_REACH:
			active_station = closest_idx
			queue_redraw()
			station_tapped.emit(closest_idx)
			Input.vibrate_handheld(25)
			accept_event()
			return

		# C. Outer rim tap
		if dist >= dial_radius * 0.78 and dist <= dial_radius * 1.35:
			var slot: int = slot_at(ev_pos)
			set_earth_slot(slot)
			ring_slot_tapped.emit(slot)
			Input.vibrate_handheld(20)
			accept_event()
			return
