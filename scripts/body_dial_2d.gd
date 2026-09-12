class_name BodyDial2D
extends Control

signal body_hexagram_changed(wen_id: int, hex_bits: int, hex_name: String, hex_char: String)
signal machine_station_clicked(trigram_idx: int)

# Body Mandala (Sun & Machine Substrate Cybernetics)
var active_machine_trigram: int = 7 # Default: Heaven (Solar Noon)
var current_hex_index: int = 0
var current_hex_id: int = 1

var dial_angle: float = 0.0
var target_dial_angle: float = 0.0
var is_dragging_dial: bool = false
var drag_start_angle: float = 0.0
var touch_down_pos: Vector2 = Vector2.ZERO
var touch_down_time: int = 0
var has_moved_significantly: bool = false

var dial_center: Vector2 = Vector2.ZERO
var dial_radius: float = 240.0

# 8 Machine Substrate Stations: Clockwise from top (matching Ba-Gua Cardinal physical layout)
# 7=Heaven(Top/Noon), 3=Lake(NE/Atmosphere), 5=Fire(East/Lux), 1=Thunder(SE/Surge),
# 0=Earth(South/Sanctuary), 4=Mountain(SW/Desk), 2=Water(West/Battery), 6=Wind(NW/Flux)
const MACHINE_STATIONS: Array[Dictionary] = [
	{"trigram": 7, "angle": -PI * 0.5, "name": "Solar Noon", "zh": "乾"},
	{"trigram": 3, "angle": -PI * 0.25, "name": "Atmosphere", "zh": "兌"},
	{"trigram": 5, "angle": 0.0, "name": "Photosphere", "zh": "離"},
	{"trigram": 1, "angle": PI * 0.25, "name": "Power Surge", "zh": "震"},
	{"trigram": 0, "angle": PI * 0.5, "name": "Sanctuary", "zh": "坤"},
	{"trigram": 4, "angle": PI * 0.75, "name": "Desk Rest", "zh": "艮"},
	{"trigram": 2, "angle": PI, "name": "Battery Chi", "zh": "坎"},
	{"trigram": 6, "angle": -PI * 0.75, "name": "Magnetic Flux", "zh": "巽"}
]

const TRIGRAM_BITS: Array[int] = [0b000, 0b001, 0b010, 0b011, 0b100, 0b101, 0b110, 0b111]

func _ready() -> void:
	current_hex_index = 0
	current_hex_id = HuohoutuData.BODY_SEQUENCE[0]
	target_dial_angle = 0.0
	dial_angle = 0.0
	_emit_current()

func _process(delta: float) -> void:
	if not is_dragging_dial:
		dial_angle = lerp_angle(dial_angle, target_dial_angle, delta * 12.0)
	queue_redraw()

func _draw() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.46
	
	# -------------------------------------------------------------
	# 1. OUTER SOLAR GLOWING RING (Sun/Macrocosm Theme)
	# -------------------------------------------------------------
	# Radiant outer rim
	draw_arc(dial_center, dial_radius, 0, TAU, 96, Color(1.0, 0.78, 0.22, 0.45), 3.0, true)
	# Inner electric track
	draw_arc(dial_center, dial_radius - 22.0, 0, TAU, 96, Color(0.18, 0.85, 1.0, 0.35), 1.5, true)
	# Subtle framing boundary
	draw_arc(dial_center, dial_radius * 0.62, 0, TAU, 64, Color(0.2, 0.65, 0.9, 0.18), 1.0, true)

	# -------------------------------------------------------------
	# 2. 64 HEXAGRAM GRADUATION TICKS (BODY_64 SEQUENCE)
	# -------------------------------------------------------------
	var num_ticks: int = 64
	for i in range(num_ticks):
		var ang: float = dial_angle + (float(i) / float(num_ticks)) * TAU
		var is_major: bool = (i % 8 == 0)
		var r1: float = dial_radius - (18.0 if is_major else 8.0)
		var r2: float = dial_radius
		var col: Color = Color(1.0, 0.85, 0.3, 0.95) if is_major else Color(0.25, 0.75, 0.95, 0.45)
		var p1 := dial_center + Vector2(cos(ang), sin(ang)) * r1
		var p2 := dial_center + Vector2(cos(ang), sin(ang)) * r2
		draw_line(p1, p2, col, 2.5 if is_major else 1.2)

	# -------------------------------------------------------------
	# 3. TOP SOLAR INDICATOR (SUN POINTER)
	# -------------------------------------------------------------
	var top_pt := dial_center + Vector2(0, -dial_radius - 6.0)
	var sun_arrow_p1 := top_pt + Vector2(-10, -15)
	var sun_arrow_p2 := top_pt + Vector2(10, -15)
	draw_colored_polygon(PackedVector2Array([top_pt, sun_arrow_p1, sun_arrow_p2]), Color(1.0, 0.82, 0.2, 0.95))
	# Glowing sun crest above pointer
	var sun_crest_pos := top_pt + Vector2(0, -22)
	draw_circle(sun_crest_pos, 5.0, Color(1.0, 0.9, 0.3, 0.95))
	draw_arc(sun_crest_pos, 8.0, 0, TAU, 16, Color(1.0, 0.75, 0.15, 0.6), 1.5, true)

	# -------------------------------------------------------------
	# 4. 8 MACHINE SUBSTRATE STATIONS ON THE DIAL RING
	# -------------------------------------------------------------
	var now: float = Time.get_ticks_msec() * 0.001
	for station in MACHINE_STATIONS:
		var st_tri: int = station["trigram"]
		var st_ang: float = station["angle"]
		var st_pos := dial_center + Vector2(cos(st_ang), sin(st_ang)) * (dial_radius * 0.78)
		var is_active: bool = (st_tri == active_machine_trigram)
		
		# Draw Diamond Node
		var d_sz: float = 11.0 if is_active else 6.5
		var pts := PackedVector2Array([
			st_pos + Vector2(0, -d_sz),
			st_pos + Vector2(d_sz, 0),
			st_pos + Vector2(0, d_sz),
			st_pos + Vector2(-d_sz, 0)
		])
		
		if is_active:
			# Pulsating outer halo
			var halo_sz: float = d_sz + 4.0 + sin(now * 6.0) * 2.0
			var halo_pts := PackedVector2Array([
				st_pos + Vector2(0, -halo_sz),
				st_pos + Vector2(halo_sz, 0),
				st_pos + Vector2(0, halo_sz),
				st_pos + Vector2(-halo_sz, 0)
			])
			draw_colored_polygon(halo_pts, Color(0.2, 0.95, 1.0, 0.28))
			draw_colored_polygon(pts, Color(0.2, 0.9, 1.0, 0.95))
			draw_circle(st_pos, 3.5, Color(1.0, 0.9, 0.3, 1.0))
		else:
			draw_colored_polygon(pts, Color(0.08, 0.18, 0.28, 0.8))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.2, 0.7, 0.9, 0.6), 1.5)

		# Draw 3-Line Trigram Glyph beside/radially outside the node
		var tri_bits: int = TRIGRAM_BITS[st_tri]
		var v_rad: Vector2 = (st_pos - dial_center).normalized()
		var v_tan: Vector2 = Vector2(-v_rad.y, v_rad.x)
		var glyph_center := st_pos - v_rad * 19.0
		var glyph_w: float = 8.0
		var line_spacing: float = 3.5
		var tri_col := Color(0.3, 0.95, 1.0, 0.95) if is_active else Color(0.25, 0.65, 0.85, 0.45)
		
		for l_idx in range(3):
			var is_yang: bool = bool((tri_bits >> l_idx) & 1)
			var l_c: Vector2 = glyph_center + v_rad * (float(l_idx - 1) * line_spacing)
			if is_yang:
				draw_line(l_c - v_tan * glyph_w, l_c + v_tan * glyph_w, tri_col, 1.5)
			else:
				var gap: float = glyph_w * 0.28
				draw_line(l_c - v_tan * glyph_w, l_c - v_tan * gap, tri_col, 1.5)
				draw_line(l_c + v_tan * gap, l_c + v_tan * glyph_w, tri_col, 1.5)

func _gui_input(event: InputEvent) -> void:
	var pos: Vector2 = Vector2.ZERO
	var is_press: bool = false
	var is_drag: bool = false
	var is_release: bool = false
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		is_press = event.pressed
		is_release = !event.pressed
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		pos = event.position
		is_drag = true
	elif event is InputEventScreenTouch:
		pos = event.position
		is_press = event.pressed
		is_release = !event.pressed
	elif event is InputEventScreenDrag:
		pos = event.position
		is_drag = true

	var dist_from_center: float = (pos - dial_center).length()

	if is_press:
		# Only intercept touches on the dial ring and stations area
		if dist_from_center >= dial_radius * 0.58 and dist_from_center <= dial_radius * 1.25:
			touch_down_pos = pos
			touch_down_time = int(Time.get_ticks_msec())
			drag_start_angle = (pos - dial_center).angle() - dial_angle
			is_dragging_dial = true
			has_moved_significantly = false
			accept_event()
	elif is_drag and is_dragging_dial:
		if (pos - touch_down_pos).length() > 8.0:
			has_moved_significantly = true
		var cur_angle: float = (pos - dial_center).angle()
		dial_angle = cur_angle - drag_start_angle
		target_dial_angle = dial_angle
		
		var step_rad: float = TAU / 64.0
		var raw_idx: int = posmod(int(round(-dial_angle / step_rad)), 64)
		if raw_idx != current_hex_index:
			current_hex_index = raw_idx
			_emit_current()
			Input.vibrate_handheld(12)
		accept_event()
	elif is_release and is_dragging_dial:
		is_dragging_dial = false
		var dur: int = int(Time.get_ticks_msec()) - touch_down_time
		if not has_moved_significantly and dur < 400:
			# Check if tap was on one of the 8 machine stations
			for station in MACHINE_STATIONS:
				var st_ang: float = station["angle"]
				var st_pos := dial_center + Vector2(cos(st_ang), sin(st_ang)) * (dial_radius * 0.78)
				if (pos - st_pos).length() < 34.0:
					var st_tri: int = station["trigram"]
					machine_station_clicked.emit(st_tri)
					Input.vibrate_handheld(25)
					accept_event()
					return
		_snap_to_closest()
		_emit_current()
		accept_event()

func _snap_to_closest() -> void:
	var step_rad: float = TAU / 64.0
	current_hex_index = posmod(int(round(-dial_angle / step_rad)), 64)
	target_dial_angle = -float(current_hex_index) * step_rad

func _emit_current() -> void:
	var cur_data: Dictionary = HuohoutuData.get_body_hex(current_hex_index)
	current_hex_id = cur_data["id"]
	body_hexagram_changed.emit(cur_data["id"], cur_data["bits"], cur_data["name"], cur_data.get("zh", "乾"))

func select_by_id(id: int) -> void:
	var idx: int = HuohoutuData.find_body_index_by_id(id)
	current_hex_index = idx
	var step_rad: float = TAU / 64.0
	target_dial_angle = -float(idx) * step_rad
	_emit_current()

func select_next() -> void:
	current_hex_index = posmod(current_hex_index + 1, 64)
	var step_rad: float = TAU / 64.0
	target_dial_angle = -float(current_hex_index) * step_rad
	_emit_current()
	Input.vibrate_handheld(15)

func select_prev() -> void:
	current_hex_index = posmod(current_hex_index - 1, 64)
	var step_rad: float = TAU / 64.0
	target_dial_angle = -float(current_hex_index) * step_rad
	_emit_current()
	Input.vibrate_handheld(15)

func set_active_machine_trigram(tri: int) -> void:
	active_machine_trigram = tri
	queue_redraw()
