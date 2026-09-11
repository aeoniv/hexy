class_name MandalaDial2D
extends Control

signal hexagram_changed(wen_index: int, hex_bits: int, hex_name: String, hex_char: String)
signal human_station_clicked(trigram_idx: int)
signal center_hub_clicked()

# Head Mandala (Moon & Human Habit Consciousness)
var active_human_trigram: int = 0
var touch_down_pos: Vector2 = Vector2.ZERO
var touch_down_time: int = 0
var has_moved_significantly: bool = false

const HUMAN_STATION_TRIGRAMS: Array[int] = [7, 3, 5, 1, 0, 4, 2, 6] # Clockwise from top: 7=Heaven, 3=Lake, 5=Fire, 1=Thunder, 0=Earth, 4=Mountain, 2=Water, 6=Wind

# King Wen Hexagrams Lookup (Bits: lower 3 bits = lower trigram, upper 3 bits = upper trigram)
# Trigram mapping: 0=Earth (坤), 1=Thunder (震), 2=Water (坎), 3=Lake (兌), 4=Mountain (艮), 5=Fire (離), 6=Wind (巽), 7=Heaven (乾)
const KING_WEN_DATA: Array = [
	{"wen": 1, "bits": 0b111111, "zh": "乾", "name": "The Creative", "py": "qián"},
	{"wen": 2, "bits": 0b000000, "zh": "坤", "name": "The Receptive", "py": "kūn"},
	{"wen": 3, "bits": 0b010001, "zh": "屯", "name": "Difficulty at the Beginning", "py": "zhūn"},
	{"wen": 4, "bits": 0b100010, "zh": "蒙", "name": "Youthful Folly", "py": "méng"},
	{"wen": 5, "bits": 0b111010, "zh": "需", "name": "Waiting", "py": "xū"},
	{"wen": 6, "bits": 0b010111, "zh": "訟", "name": "Conflict", "py": "sòng"},
	{"wen": 7, "bits": 0b000010, "zh": "師", "name": "The Army", "py": "shī"},
	{"wen": 8, "bits": 0b010000, "zh": "比", "name": "Holding Together", "py": "bǐ"},
	{"wen": 9, "bits": 0b111110, "zh": "小畜", "name": "Small Taming", "py": "xiǎo chù"},
	{"wen": 10, "bits": 0b011111, "zh": "履", "name": "Treading", "py": "lǚ"},
	{"wen": 11, "bits": 0b111000, "zh": "泰", "name": "Peace", "py": "tài"},
	{"wen": 12, "bits": 0b000111, "zh": "否", "name": "Standstill", "py": "pǐ"},
	{"wen": 13, "bits": 0b111101, "zh": "同人", "name": "Fellowship", "py": "tóng rén"},
	{"wen": 14, "bits": 0b101111, "zh": "大有", "name": "Great Possession", "py": "dà yǒu"},
	{"wen": 15, "bits": 0b000100, "zh": "謙", "name": "Modesty", "py": "qiān"},
	{"wen": 16, "bits": 0b001000, "zh": "豫", "name": "Enthusiasm", "py": "yù"},
	{"wen": 17, "bits": 0b011001, "zh": "隨", "name": "Following", "py": "suí"},
	{"wen": 18, "bits": 0b100110, "zh": "蠱", "name": "Work on Corruption", "py": "gǔ"},
	{"wen": 19, "bits": 0b110000, "zh": "臨", "name": "Approach", "py": "lín"},
	{"wen": 20, "bits": 0b000011, "zh": "觀", "name": "Contemplation", "py": "guān"},
	{"wen": 21, "bits": 0b101001, "zh": "噬嗑", "name": "Biting Through", "py": "shì kè"},
	{"wen": 22, "bits": 0b100101, "zh": "賁", "name": "Grace", "py": "bì"},
	{"wen": 23, "bits": 0b000001, "zh": "剝", "name": "Splitting Apart", "py": "bō"},
	{"wen": 24, "bits": 0b100000, "zh": "復", "name": "Return", "py": "fù"},
	{"wen": 25, "bits": 0b111001, "zh": "無妄", "name": "Innocence", "py": "wú wàng"},
	{"wen": 26, "bits": 0b100111, "zh": "大畜", "name": "Great Taming", "py": "dà chù"},
	{"wen": 27, "bits": 0b100001, "zh": "頤", "name": "Nourishment", "py": "yí"},
	{"wen": 28, "bits": 0b011110, "zh": "大過", "name": "Preponderance of Great", "py": "dà guò"},
	{"wen": 29, "bits": 0b010010, "zh": "坎", "name": "The Abysmal Water", "py": "kǎn"},
	{"wen": 30, "bits": 0b101101, "zh": "離", "name": "The Clinging Fire", "py": "lí"},
	{"wen": 53, "bits": 0b110100, "zh": "漸", "name": "Development", "py": "jiàn"},
	{"wen": 63, "bits": 0b101010, "zh": "既濟", "name": "After Completion", "py": "jì jì"},
	{"wen": 64, "bits": 0b010101, "zh": "未濟", "name": "Before Completion", "py": "wèi jì"}
]

var current_hex_index: int = 0
var dial_angle: float = 0.0
var target_dial_angle: float = 0.0
var is_dragging_dial: bool = false
var drag_start_angle: float = 0.0
var dial_center: Vector2 = Vector2.ZERO
var dial_radius: float = 140.0

func _ready() -> void:
	# Default to Hexagram 53 (Development) or 1 (The Creative)
	current_hex_index = 0
	_emit_current()

func _draw() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.44
	
	# Outer glowing ring
	draw_arc(dial_center, dial_radius, 0, TAU, 64, Color(0.12, 0.5, 0.7, 0.4), 3.0, true)
	draw_arc(dial_center, dial_radius - 20, 0, TAU, 64, Color(0.1, 0.3, 0.5, 0.25), 1.5, true)
	
	# Draw 64 radial ticks
	var num_ticks := 64
	for i in range(num_ticks):
		var ang: float = dial_angle + (float(i) / num_ticks) * TAU
		var is_major: bool = (i % 8 == 0)
		var r1: float = dial_radius - (14.0 if is_major else 6.0)
		var r2: float = dial_radius
		var col: Color = Color(0.9, 0.7, 0.2, 0.9) if is_major else Color(0.3, 0.6, 0.8, 0.5)
		var p1 := dial_center + Vector2(cos(ang), sin(ang)) * r1
		var p2 := dial_center + Vector2(cos(ang), sin(ang)) * r2
		draw_line(p1, p2, col, 2.0 if is_major else 1.0)
		
	# Top Indicator Arrow (Pointer)
	var top_pt := dial_center + Vector2(0, -dial_radius - 6.0)
	var arrow_p1 := top_pt + Vector2(-8, -12)
	var arrow_p2 := top_pt + Vector2(8, -12)
	draw_colored_polygon(PackedVector2Array([top_pt, arrow_p1, arrow_p2]), Color(0.95, 0.75, 0.2, 0.95))
	
	# 8 Human Habit Stations on the dial perimeter
	for s in range(8):
		var st_tri: int = HUMAN_STATION_TRIGRAMS[s]
		var st_ang: float = -TAU * 0.25 + float(s) * (TAU / 8.0)
		var st_pos := dial_center + Vector2(cos(st_ang), sin(st_ang)) * (dial_radius * 0.72)
		var is_active: bool = (st_tri == active_human_trigram)
		var node_r: float = 8.0 if is_active else 5.0
		var node_col: Color = Color(1.0, 0.85, 0.25, 0.95) if is_active else Color(0.3, 0.6, 0.8, 0.6)
		if is_active:
			draw_circle(st_pos, node_r + 4.0, Color(1.0, 0.85, 0.25, 0.35))
		draw_circle(st_pos, node_r, node_col)
	
	# Center Hub (Circle)
	var hub_r := dial_radius * 0.48
	draw_circle(dial_center, hub_r, Color(0.06, 0.09, 0.14, 0.92))
	draw_arc(dial_center, hub_r, 0, TAU, 32, Color(0.2, 0.7, 0.9, 0.8), 2.0, true)
	
	# Draw Hexagram Lines inside Center Hub (Head=Gold over Body=Cyan)
	var cur_data: Dictionary = KING_WEN_DATA[current_hex_index]
	var bits: int = cur_data["bits"]
	var line_w: float = hub_r * 1.1
	var line_h: float = 4.0
	var line_gap: float = 7.0
	var start_y: float = dial_center.y + (line_gap * 2.5)
	
	for line_idx in range(6):
		var y: float = start_y - float(line_idx) * (line_h + line_gap)
		var is_yang: bool = ((bits >> line_idx) & 1) == 1
		var is_upper: bool = line_idx >= 3
		var col: Color = (Color(1.0, 0.82, 0.25) if is_yang else Color(0.75, 0.58, 0.2)) if is_upper else (Color(0.25, 0.85, 1.0) if is_yang else Color(0.18, 0.55, 0.85))
		
		if is_yang:
			# Solid Line
			draw_line(Vector2(dial_center.x - line_w * 0.5, y), Vector2(dial_center.x + line_w * 0.5, y), col, line_h)
		else:
			# Split Line (Yin)
			var half_span: float = line_w * 0.5
			var gap: float = line_w * 0.2
			draw_line(Vector2(dial_center.x - half_span, y), Vector2(dial_center.x - gap * 0.5, y), col, line_h)
			draw_line(Vector2(dial_center.x + gap * 0.5, y), Vector2(dial_center.x + half_span, y), col, line_h)

func _gui_input(event: InputEvent) -> void:
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
		is_dragging_dial = true
		touch_down_pos = ev_pos
		touch_down_time = int(Time.get_ticks_msec())
		has_moved_significantly = false
		var dir: Vector2 = ev_pos - dial_center
		drag_start_angle = dir.angle() - dial_angle
	elif is_release:
		is_dragging_dial = false
		var move_dist: float = (ev_pos - touch_down_pos).length()
		var tap_duration: int = int(Time.get_ticks_msec()) - touch_down_time
		if move_dist < 18.0 and tap_duration < 380:
			# Detected a tap!
			var v: Vector2 = ev_pos - dial_center
			var dist: float = v.length()
			var hub_r: float = dial_radius * 0.48
			if dist < hub_r:
				center_hub_clicked.emit()
				Input.vibrate_handheld(25)
			elif dist <= dial_radius * 1.25:
				# Map tap angle to one of the 8 Human Habit Stations
				var ang: float = fposmod(v.angle() + (TAU * 0.25) + (TAU / 16.0), TAU)
				var st_idx: int = int(ang / (TAU / 8.0)) % 8
				var tri_idx: int = HUMAN_STATION_TRIGRAMS[st_idx]
				active_human_trigram = tri_idx
				queue_redraw()
				human_station_clicked.emit(tri_idx)
				Input.vibrate_handheld(20)
		else:
			_snap_to_closest()
	elif is_move and is_dragging_dial:
		if (ev_pos - touch_down_pos).length() > 18.0:
			has_moved_significantly = true
		var dir: Vector2 = ev_pos - dial_center
		var new_ang: float = dir.angle() - drag_start_angle
		dial_angle = new_ang
		queue_redraw()
		
		# Step hexagram when rotated enough
		var step_rad := TAU / 32.0
		var new_idx = posmod(int(round(-dial_angle / step_rad)), KING_WEN_DATA.size())
		if new_idx != current_hex_index:
			current_hex_index = new_idx
			_emit_current()
			Input.vibrate_handheld(12)

func _snap_to_closest() -> void:
	var step_rad := TAU / 32.0
	target_dial_angle = -float(current_hex_index) * step_rad
	dial_angle = target_dial_angle
	queue_redraw()

func _emit_current() -> void:
	var data: Dictionary = KING_WEN_DATA[current_hex_index]
	hexagram_changed.emit(data["wen"], data["bits"], data["name"], data["zh"])

func select_next() -> void:
	current_hex_index = (current_hex_index + 1) % KING_WEN_DATA.size()
	_snap_to_closest()
	_emit_current()
	Input.vibrate_handheld(15)

func select_prev() -> void:
	current_hex_index = (current_hex_index - 1 + KING_WEN_DATA.size()) % KING_WEN_DATA.size()
	_snap_to_closest()
	_emit_current()
	Input.vibrate_handheld(15)
func find_index_by_bits(bits: int) -> int:
	for i in range(KING_WEN_DATA.size()):
		if KING_WEN_DATA[i]["bits"] == bits:
			return i
	var best_idx: int = 0
	var min_diff: int = 7
	for i in range(KING_WEN_DATA.size()):
		var xor_bits: int = KING_WEN_DATA[i]["bits"] ^ bits
		var diff: int = 0
		for b in range(6):
			diff += (xor_bits >> b) & 1
		if diff < min_diff:
			min_diff = diff
			best_idx = i
	return best_idx

func select_by_index(idx: int) -> void:
	current_hex_index = clamp(idx, 0, KING_WEN_DATA.size() - 1)
	_snap_to_closest()
	_emit_current()
