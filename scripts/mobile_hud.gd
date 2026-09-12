extends Control

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")
const MandalaDial2D = preload("res://scripts/mandala_dial_2d.gd")
const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")
const SensorOracle = preload("res://scripts/sensor_oracle.gd")

@onready var top_bar: PanelContainer = $TopBar
@onready var lbl_title: Label = $TopBar/Margin/HBox/Title
@onready var btn_geo_toggle: Button = $TopBar/Margin/HBox/BtnGeoToggle
@onready var btn_cast_mode: Button = $TopBar/Margin/HBox/BtnCastMode
@onready var btn_mode_toggle: Button = $TopBar/Margin/HBox/BtnModeToggle
@onready var lbl_fps: Label = $TopBar/Margin/HBox/FPS

@onready var hex_card: PanelContainer = $HexCard
@onready var lbl_hex_char: Label = $HexCard/Margin/VBox/HBox/HexChar
@onready var lbl_hex_title: Label = $HexCard/Margin/VBox/HBox/VBox/HexTitle
@onready var lbl_hex_subtitle: Label = $HexCard/Margin/VBox/HBox/VBox/HexSubtitle
@onready var lbl_moving_line: Label = $HexCard/Margin/VBox/MovingLine

@onready var thought_bubble: PanelContainer = $ThoughtBubble
@onready var lbl_thought: Label = $ThoughtBubble/Margin/ThoughtLabel

@onready var body_dial_container: Control = $BodyMandalaContainer
@onready var body_dial: Control = $BodyMandalaContainer/BodyDial
@onready var mandala_container: Control = $MandalaContainer
@onready var mandala_dial: Control = $MandalaContainer/Dial

@onready var btn_cast: Button = $Controls/HBox/BtnCast
@onready var btn_ask: Button = $Controls/HBox/BtnAsk
@onready var btn_prev: Button = $Controls/HBox/BtnPrev
@onready var btn_next: Button = $Controls/HBox/BtnNext

@onready var nav_bar: PanelContainer = $BottomNav
@onready var tab_companion: Button = $BottomNav/HBox/TabCompanion
@onready var tab_oracle: Button = $BottomNav/HBox/TabOracle
@onready var tab_brain: Button = $BottomNav/HBox/TabBrain
@onready var tab_telemetry: Button = $BottomNav/HBox/TabTelemetry

var mnn: MnnRuntime
var creature_node: Node3D
var mandala_3d_node: Node3D
var active_mode: String = "companion"
var is_enhanced_mode: bool = true
# Single Unified Huohoutu Architecture:
# HEAD (Manual Casting, RAVE_WHEEL_64, changes the very hexagram)
# BODY (Automatic Casting, BODY_64, changes the tensegrity structure)
var head_hex_id: int = 41
var body_hex_id: int = 1
var sensor_oracle: SensorOracle

func _ready() -> void:
	mnn = MnnRuntime.new()
	mnn.chat_start()
	mnn.chat_token.connect(_on_mnn_chat_token)
	mnn.chat_done.connect(_on_mnn_chat_done)
	
	if has_node("BodyMandalaContainer/BodyDial"):
		var b_dial: Control = get_node("BodyMandalaContainer/BodyDial")
		if b_dial.has_signal("body_hexagram_changed"):
			b_dial.connect("body_hexagram_changed", Callable(self, "_on_body_hexagram_changed"))
		if b_dial.has_signal("machine_station_clicked"):
			b_dial.connect("machine_station_clicked", Callable(self, "_on_machine_node_clicked"))
	
	if mandala_dial.has_signal("hexagram_changed"):
		mandala_dial.connect("hexagram_changed", Callable(self, "_on_hexagram_changed"))
	if mandala_dial.has_signal("human_station_clicked"):
		mandala_dial.human_station_clicked.connect(_on_human_station_clicked)
	if mandala_dial.has_signal("center_hub_clicked"):
		mandala_dial.center_hub_clicked.connect(_on_center_hub_clicked)
	
	sensor_oracle = SensorOracle.new()
	sensor_oracle.enabled = true
	add_child(sensor_oracle)
	sensor_oracle.shake_started.connect(_on_shake_started)
	sensor_oracle.shake_progress.connect(_on_shake_progress)
	sensor_oracle.shake_cast_completed.connect(_on_shake_cast_completed)
	sensor_oracle.autonomous_mutation_stepped.connect(_on_autonomous_mutation_stepped)
	sensor_oracle.autonomous_thought_requested.connect(_on_autonomous_thought_requested)
	sensor_oracle.sensor_telemetry_updated.connect(_on_sensor_telemetry_updated)
	
	btn_geo_toggle.pressed.connect(_on_geo_toggle_pressed)
	btn_cast_mode.pressed.connect(_on_cast_mode_toggle_pressed)
	btn_mode_toggle.pressed.connect(_on_mode_toggle_pressed)
	btn_cast.pressed.connect(_on_cast_pressed)
	btn_ask.pressed.connect(_on_ask_pressed)
	btn_prev.pressed.connect(_on_prev_pressed)
	btn_next.pressed.connect(_on_next_pressed)
	
	tab_companion.pressed.connect(func(): _switch_mode("companion"))
	tab_oracle.pressed.connect(func(): _switch_mode("oracle"))
	tab_brain.pressed.connect(func(): _switch_mode("brain"))
	tab_telemetry.pressed.connect(func(): _switch_mode("telemetry"))
	
	_update_mode_ui()
	btn_cast_mode.text = "🔥 HUOHOUTU"
	btn_cast_mode.modulate = Color(1.0, 0.75, 0.2)
	btn_cast.text = "🪙 CAST HEAD"
	btn_cast.modulate = Color(0.5, 0.9, 1.0)
	_switch_mode("companion")

func setup_creature(creature: Node3D, mandala: Node3D = null) -> void:
	creature_node = creature
	mandala_3d_node = mandala
	if creature_node:
		if "sensor_mode_enabled" in creature_node:
			creature_node.sensor_mode_enabled = true
		if creature_node.has_method("get_current_geometry_name"):
			btn_geo_toggle.text = creature_node.get_current_geometry_name()
		if creature_node.has_signal("machine_node_clicked"):
			creature_node.machine_node_clicked.connect(_on_machine_node_clicked)
		# Set initial Body Tensegrity Structure
		var body_data: Dictionary = HuohoutuData.get_hex(body_hex_id)
		if creature_node.has_method("set_hexagram"):
			creature_node.set_hexagram(body_data["bits"], 3)
	if mandala_3d_node and mandala_3d_node.has_method("set_body_hexagram"):
		mandala_3d_node.set_body_hexagram(body_hex_id, 0)
	if has_node("BodyMandalaContainer/BodyDial"):
		var b_dial: Control = get_node("BodyMandalaContainer/BodyDial")
		if b_dial.has_method("select_by_id"):
			b_dial.select_by_id(body_hex_id)
	if mandala_dial:
		mandala_dial.select_by_id(head_hex_id)
	_update_huohoutu_ui()

func _process(_delta: float) -> void:
	lbl_fps.text = "%d FPS" % Engine.get_frames_per_second()

func _on_cast_mode_toggle_pressed() -> void:
	# Single Unified Huohoutu Mode - Tap indicates alchemical resonance
	Input.vibrate_handheld(25)
	var moon: Dictionary = sensor_oracle.get_moon_phase() if sensor_oracle else {}
	var sun: Dictionary = sensor_oracle.get_sun_cycle() if sensor_oracle else {}
	lbl_thought.text = "🔥 Unified Huohoutu Mode:\n• 🌙 HEAD (Bottom Dial): Manual Oracle Casting (Changes Hexagram)\n• ☀️ BODY (3D Creature): Automatic Sensor Casting (Changes Tensegrity)\n• Moon: %s %s · Sun: %s" % [
		moon.get("emoji", "🌙"), moon.get("name", "Moon"), sun.get("period", "Sun")
	]

func _on_shake_started() -> void:
	lbl_thought.text = "🪙 Divination vessel shaking... Rattling coins in sacred motion..."

func _on_shake_progress(p: float) -> void:
	var pct := int(p * 100.0)
	var filled := int(p * 10.0)
	var bar := "█".repeat(filled) + "░".repeat(10 - filled)
	lbl_thought.text = "🪙 Casting Energy: [%s] %d%%. Keep shaking to cast!" % [bar, pct]

func _on_shake_cast_completed(_wen: int, moving_line: int, hex_bits: int) -> void:
	# Martial Fire shake cast directly updates the Body Tensegrity structure!
	var body_data: Dictionary = HuohoutuData.get_by_bits(hex_bits)
	body_hex_id = body_data["id"]
	var body_idx: int = HuohoutuData.find_body_index_by_id(body_hex_id)
	if creature_node and creature_node.has_method("set_hexagram"):
		creature_node.set_hexagram(hex_bits, moving_line)
	if mandala_3d_node and mandala_3d_node.has_method("set_body_hexagram"):
		mandala_3d_node.set_body_hexagram(body_hex_id, body_idx)
	if has_node("BodyMandalaContainer/BodyDial"):
		var b_dial: Control = get_node("BodyMandalaContainer/BodyDial")
		if b_dial.has_method("select_by_id"):
			b_dial.select_by_id(body_hex_id)
	_update_huohoutu_ui("Martial Fire Shake: Body Tensegrity Transmuted")

func _on_autonomous_mutation_stepped(new_bits: int, moving_line: int, reason: String) -> void:
	# SensorOracle autonomous mutation drives the BODY: updates tensegrity structure & 3D body dial!
	var body_data: Dictionary = HuohoutuData.get_by_bits(new_bits)
	body_hex_id = body_data["id"]
	var body_idx: int = HuohoutuData.find_body_index_by_id(body_hex_id)
	
	# 1. Morph the 3D Tensegrity Structure!
	if creature_node and creature_node.has_method("set_hexagram"):
		creature_node.set_hexagram(new_bits, moving_line)
	# 2. Rotate the 3D Body Dial Pointer & Big 2D Body Dial!
	if mandala_3d_node and mandala_3d_node.has_method("set_body_hexagram"):
		mandala_3d_node.set_body_hexagram(body_hex_id, body_idx)
	if has_node("BodyMandalaContainer/BodyDial"):
		var b_dial: Control = get_node("BodyMandalaContainer/BodyDial")
		if b_dial.has_method("select_by_id"):
			b_dial.select_by_id(body_hex_id)
	
	_update_huohoutu_ui(reason)

func _on_human_station_clicked(tri_idx: int) -> void:
	if not sensor_oracle:
		return
	var info: Dictionary = sensor_oracle.get_human_info(tri_idx)
	var name_str: String = info.get("name", "Habit")
	var zh_str: String = info.get("zh", "")
	var cue_str: String = info.get("cue", "")
	var act_str: String = info.get("action", "")
	var moon: Dictionary = sensor_oracle.get_moon_phase()
	var moon_str: String = "%s %s" % [moon.get("emoji", "🌙"), moon.get("name", "Moon")]
	
	lbl_thought.text = "🌙 HEAD · 神 SHEN (%s · Upper Trigram):\n• %s %s: %s\n• Guidance: %s" % [
		moon_str, zh_str, name_str, cue_str, act_str
	]

func _on_machine_node_clicked(tri_idx: int) -> void:
	if not sensor_oracle:
		return
	var info: Dictionary = sensor_oracle.get_machine_info(tri_idx)
	var name_str: String = info.get("name", "Substrate")
	var zh_str: String = info.get("zh", "")
	var hw_str: String = info.get("hardware", "")
	var stat_str: String = info.get("status", "")
	var sun: Dictionary = sensor_oracle.get_sun_cycle()
	var sun_str: String = sun.get("period", "Sun")
	var telem: Dictionary = sensor_oracle.get_telemetry_snapshot()
	
	lbl_thought.text = "☀️ BODY · 精 JING (%s · Lower Trigram):\n• %s %s: %s\n• Telemetry: %s (Lux: %.0f, Bat: %.0f%%)" % [
		sun_str, zh_str, name_str, hw_str, stat_str,
		telem.get("lux", 0.0), telem.get("battery", 100.0)
	]

func _on_center_hub_clicked() -> void:
	_on_ask_pressed()

func _on_mnn_chat_token(token: String) -> void:
	thought_bubble.visible = true
	lbl_thought.text += token

func _on_mnn_chat_done(full_text: String) -> void:
	if creature_node and creature_node.has_method("set_thinking"):
		creature_node.set_thinking(false)
	if mandala_3d_node and mandala_3d_node.has_method("set_thinking"):
		mandala_3d_node.set_thinking(false)
	lbl_thought.text = "💬 Qwen %s [%s Tier - %s]:\n%s" % [
		mnn.short_name(), mnn.tier_name(), mnn.backend_name(), full_text
	]

func _on_autonomous_thought_requested(prompt: String) -> void:
	if mnn and mnn.chat_ready():
		lbl_thought.text = "🧠 Autonomous Reflection (%s [%s Tier]):\n" % [mnn.short_name(), mnn.tier_name()]
		thought_bubble.visible = true
		if creature_node and creature_node.has_method("set_thinking"):
			creature_node.set_thinking(true)
		if mandala_3d_node and mandala_3d_node.has_method("set_thinking"):
			mandala_3d_node.set_thinking(true)
		mnn.chat_stream(prompt)

var last_telemetry_data: Dictionary = {}
func _on_sensor_telemetry_updated(g: Vector3, heading: float, jerk: float, lower_tri: int, upper_tri: int) -> void:
	if has_node("BodyMandalaContainer/BodyDial"):
		var b_dial: Control = get_node("BodyMandalaContainer/BodyDial")
		if b_dial.has_method("set_active_machine_trigram"):
			b_dial.set_active_machine_trigram(lower_tri)
	if mandala_dial:
		mandala_dial.active_human_trigram = upper_tri
		mandala_dial.queue_redraw()
	if sensor_oracle:
		var snap: Dictionary = sensor_oracle.get_telemetry_snapshot()
		if mandala_3d_node and mandala_3d_node.has_method("update_telemetry"):
			mandala_3d_node.update_telemetry(snap)
	last_telemetry_data = {
		"g": g, "heading": heading, "jerk": jerk,
		"lower": lower_tri, "upper": upper_tri
	}
	if active_mode == "telemetry":
		_update_telemetry_view()

func _update_telemetry_view() -> void:
	if not sensor_oracle:
		return
	var telem: Dictionary = sensor_oracle.get_telemetry_snapshot()
	var g: Vector3 = telem.get("gravity", Vector3.ZERO)
	var heading: float = telem.get("heading", 0.0)
	var lux_val: float = telem.get("lux", 0.0)
	var prox_val: float = telem.get("proximity", 0.0)
	var bat_val: float = telem.get("battery", 0.0)
	var hr_val: float = telem.get("solar_hour", 12.0)
	var exc_val: float = telem.get("kinetic_excitation", 0.0)
	var strains: Array = telem.get("line_strains", [0, 0, 0, 0, 0, 0])
	
	var mach_idx: int = telem.get("machine_trigram", 0)
	var hum_idx: int = telem.get("human_trigram", 0)
	var mach_name: String = telem.get("machine_name", "Sanctuary")
	var hum_name: String = telem.get("human_name", "Stillness")
	var mach_tri_name: String = SensorOracle.TRIGRAM_NAMES[mach_idx]
	var hum_tri_name: String = SensorOracle.TRIGRAM_NAMES[hum_idx]
	
	var hex_bits: int = (hum_idx << 3) | mach_idx
	var hex_idx: int = mandala_dial.find_index_by_bits(hex_bits) if mandala_dial else 0
	var hex_info: Dictionary = mandala_dial.KING_WEN_DATA[hex_idx] if mandala_dial and hex_idx < mandala_dial.KING_WEN_DATA.size() else {}
	var wen_num: int = hex_info.get("wen", 1)
	var hex_label: String = "#%d %s '%s'" % [wen_num, hex_info.get("zh", ""), hex_info.get("name", "")]
	
	lbl_thought.text = """☸ 8x8 SENSOR-HABIT SYNERGY TELEMETRY:
• MACHINE SUBSTRATE (Inner Trigram): %s
  ➔ Modality: %s (Lux: %.0f | Bat: %.0f%% | Hour: %02d:%02d)
• HUMAN DISCIPLINE (Outer Trigram): %s
  ➔ Habit: %s (G: (%.1f,%.1f,%.1f) | Jerk: %.1f)
• RESULTING KING WEN STATE: %s (0b%06s)
• Habit Strains: [Body:%.0f%%, Food:%.0f%%, Breath:%.0f%%, Rest:%.0f%%, Focus:%.0f%%, Conn:%.0f%%]
• Excitation: %.0f%% | Heading: %.1f° | Dual Orbit Mandala Active""" % [
		mach_tri_name, mach_name, lux_val, bat_val, int(hr_val), int(fmod(hr_val * 60.0, 60.0)),
		hum_tri_name, hum_name, g.x, g.y, g.z, telem.get("jerk", 0.0),
		hex_label, String.num_int64(hex_bits, 2).pad_zeros(6),
		strains[0] * 100.0, strains[1] * 100.0, strains[2] * 100.0,
		strains[3] * 100.0, strains[4] * 100.0, strains[5] * 100.0,
		exc_val * 100.0, heading
	]

func _on_geo_toggle_pressed() -> void:
	if creature_node and creature_node.has_method("cycle_geometry_mode"):
		var _next_mode: int = creature_node.cycle_geometry_mode()
		btn_geo_toggle.text = creature_node.get_current_geometry_name()
		Input.vibrate_handheld(25)
		var cur_name: String = creature_node.get_current_geometry_name()
		lbl_thought.text = "Geometry Switched: %s. Re-anchoring tensegrity equilibrium across 6-bit cybernetic lines." % cur_name

func _on_mode_toggle_pressed() -> void:
	is_enhanced_mode = !is_enhanced_mode
	_update_mode_ui()
	Input.vibrate_handheld(30)

func _update_mode_ui() -> void:
	if is_enhanced_mode:
		btn_mode_toggle.text = "⚡ ENHANCED"
		btn_mode_toggle.modulate = Color(0.3, 0.95, 1.0)
		btn_geo_toggle.visible = true
		if creature_node:
			creature_node.visible = true
			btn_geo_toggle.text = creature_node.get_current_geometry_name()
		lbl_thought.text = "⚡ Mode: ENHANCED (Structural Cybernetics). Hexagram 6-bit states, moving line mutations, and tensegrity equilibrium active."
	else:
		btn_mode_toggle.text = "☯ PURE"
		btn_mode_toggle.modulate = Color(0.95, 0.8, 0.3)
		btn_geo_toggle.visible = false
		if creature_node:
			creature_node.visible = false
		lbl_thought.text = "☯ Mode: PURE (I-Ching Character Persona). Qwen acts strictly as the Book of Changes oracle persona without structural tensegrity math."

func _on_body_hexagram_changed(wen: int, bits: int, _hex_name: String, _zh: String) -> void:
	body_hex_id = wen
	var moving_line: int = (wen % 6)
	if creature_node and creature_node.has_method("set_hexagram"):
		creature_node.set_hexagram(bits, moving_line)
	if mandala_3d_node and mandala_3d_node.has_method("set_body_hexagram"):
		var b_idx: int = HuohoutuData.find_body_index_by_id(body_hex_id)
		mandala_3d_node.set_body_hexagram(body_hex_id, b_idx)
	_update_huohoutu_ui("Body Dial Rotated: Tensegrity Transmuted")

func _on_hexagram_changed(wen: int, bits: int, _hex_name: String, _zh: String) -> void:
	# Manual Head Dial casting changes the very hexagram (Oracle reading & card)
	head_hex_id = wen
	if sensor_oracle:
		sensor_oracle.inject_manual_state(bits, (wen % 6))
	_update_huohoutu_ui()
	# Tensegrity structure is NOT touched here; it is driven by BODY automatic casting!

func _update_huohoutu_ui(mutation_reason: String = "") -> void:
	var head_data: Dictionary = HuohoutuData.get_hex(head_hex_id)
	var body_data: Dictionary = HuohoutuData.get_hex(body_hex_id)
	
	lbl_hex_char.text = head_data.get("zh", "乾")
	lbl_hex_title.text = "🌙 HEAD #%d %s · ☀️ BODY #%d %s" % [
		head_data["id"], head_data["name"], body_data["id"], body_data["name"]
	]
	lbl_hex_subtitle.text = "Oracle Bits: 0b%06s · Tensegrity Bits: 0b%06s" % [
		head_data["bin"], body_data["bin"]
	]
	lbl_moving_line.text = "Huohoutu Pacing: 文火 Civil Dwell (2.5s) · 武火 Martial Shake"
	
	var moon: Dictionary = sensor_oracle.get_moon_phase() if sensor_oracle else {}
	var sun: Dictionary = sensor_oracle.get_sun_cycle() if sensor_oracle else {}
	
	if mutation_reason != "":
		lbl_thought.text = "🔥 HUOHOUTU (火候圖) ALCHEMY MUTATION:\n• 🌙 HEAD [Oracle]: #%d %s '%s'\n• ☀️ BODY [Tensegrity]: #%d %s '%s'\n• %s" % [
			head_data["id"], head_data.get("zh", ""), head_data["name"],
			body_data["id"], body_data.get("zh", ""), body_data["name"],
			mutation_reason
		]
	else:
		lbl_thought.text = "🔥 HUOHOUTU (火候圖) REAL-TIME RESONANCE:\n• 🌙 HEAD (Manual Oracle): #%d %s '%s' (Moon %s)\n• ☀️ BODY (Auto Tensegrity): #%d %s '%s' (Sun %s)\n• Spin bottom dial to cast Head; hold still 2.5s for Civil Fire." % [
			head_data["id"], head_data.get("zh", ""), head_data["name"], moon.get("emoji", "🌙"),
			body_data["id"], body_data.get("zh", ""), body_data["name"], sun.get("period", "☀️")
		]


func _on_prev_pressed() -> void:
	if mandala_dial and mandala_dial.has_method("select_prev"):
		mandala_dial.select_prev()

func _on_next_pressed() -> void:
	if mandala_dial and mandala_dial.has_method("select_next"):
		mandala_dial.select_next()

func _on_cast_pressed() -> void:
	# Manual Head Cast: Randomly steps through Head sequence using oracle coin toss
	Input.vibrate_handheld(25)
	var rand_idx: int = randi() % HuohoutuData.HEAD_SEQUENCE.size()
	mandala_dial.current_hex_index = rand_idx
	mandala_dial._snap_to_closest()
	mandala_dial._emit_current()
	var head_data: Dictionary = HuohoutuData.get_head_hex(rand_idx)
	lbl_thought.text = "🪙 Cast Head Hexagram: #%d %s '%s'. Manual oracle cast anchored." % [head_data["id"], head_data.get("zh", ""), head_data["name"]]

func _on_ask_pressed() -> void:
	Input.vibrate_handheld(20)
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[mandala_dial.current_hex_index]
	var moving: int = (cur["wen"] % 6) + 1
	var need_names := ["Body", "Food", "Breath", "Rest", "Focus", "Connection"]
	var changing_need: String = need_names[moving - 1]
	
	var prompt: String
	if is_enhanced_mode:
		var telem: Dictionary = sensor_oracle.get_telemetry_snapshot() if sensor_oracle else {}
		var mach_desc: String = telem.get("machine_name", "Sanctuary Rest")
		var hum_desc: String = telem.get("human_name", "Calm Posture")
		lbl_thought.text = "🧠 Consulting Qwen %s [%s Tier]...\nHexagram #%d %s (0b%06s) • Moving Line %d (%s)" % [
			mnn.short_name(), mnn.tier_name(),
			cur["wen"], cur["name"],
			String.num_int64(cur["bits"], 2).pad_zeros(6),
			moving, changing_need
		]
		prompt = "You are Hexy, a worn cybernetic companion building discipline by sensing body and machine. Environment context: %s. Human habit discipline: %s. Current King Wen Hexagram is #%d (%s '%s', bits 0b%06s). Changing line is Line %d (%s need). Give a concise 2-sentence reflection grounding discipline, habit motivation, and embodied balance in this moment." % [
			mach_desc, hum_desc,
			cur["wen"], cur["zh"], cur["name"],
			String.num_int64(cur["bits"], 2).pad_zeros(6),
			moving, changing_need
		]
	else:
		lbl_thought.text = "☯ Consulting I-Ching Persona (%s)...\nHexagram #%d %s" % [mnn.short_name(), cur["wen"], cur["name"]]
		prompt = "You are the ancient Book of Changes oracle. Speak in brief poetic wisdom on Hexagram #%d %s (%s). Two sentences maximum." % [
			cur["wen"], cur["zh"], cur["name"]
		]
	
	thought_bubble.visible = true
	if creature_node and creature_node.has_method("set_thinking"):
		creature_node.set_thinking(true)
	if mandala_3d_node and mandala_3d_node.has_method("set_thinking"):
		mandala_3d_node.set_thinking(true)
	mnn.chat_stream(prompt)

func _switch_mode(mode: String) -> void:
	active_mode = mode
	tab_companion.modulate = Color(1.0, 1.0, 1.0, 1.0 if mode == "companion" else 0.5)
	tab_oracle.modulate = Color(1.0, 1.0, 1.0, 1.0 if mode == "oracle" else 0.5)
	tab_brain.modulate = Color(1.0, 1.0, 1.0, 1.0 if mode == "brain" else 0.5)
	tab_telemetry.modulate = Color(1.0, 1.0, 1.0, 1.0 if mode == "telemetry" else 0.5)
	
	if mode == "companion":
		mandala_container.visible = true
		thought_bubble.visible = true
		hex_card.visible = true
		if creature_node:
			creature_node.visible = is_enhanced_mode
	elif mode == "oracle":
		mandala_container.visible = true
		thought_bubble.visible = true
		hex_card.visible = true
	elif mode == "brain":
		mandala_container.visible = false
		thought_bubble.visible = true
		var v1: PackedFloat32Array = mnn.embed("hexy iching consultation")
		var v2: PackedFloat32Array = mnn.embed("hexy iching consultation")
		var sim: float = MnnRuntime.cosine(v1, v2)
		var lane: Dictionary = mnn.model_info()
		var skipped_text := ""
		if lane.has("skipped_higher") and lane["skipped_higher"].size() > 0:
			skipped_text = "\n• RAM Gate Guard: " + ", ".join(lane["skipped_higher"])
		lbl_thought.text = """🧠 MNN NEURAL BRAIN SPACE (RAM-GATED):
• Model Tier: %s [%s]
• Active Weights: %s
• Device RAM: %.2f GB (%s)
• Embedder: GTE Multilingual (%d-dim, cosine: %.4f)
• Backend: %s JNI Bridge%s
• Engine: Qwen3 / Qwen3.5 On-Device Core""" % [
			mnn.tier_name(), mnn.short_name(),
			mnn.chat_model(),
			mnn.detected_ram_gb(), "Gated" if mnn.is_gated() else "Direct",
			mnn.embed_dim(), sim,
			mnn.backend_name().to_upper(),
			skipped_text
		]
	elif mode == "telemetry":
		mandala_container.visible = false
		thought_bubble.visible = true
		_update_telemetry_view()
