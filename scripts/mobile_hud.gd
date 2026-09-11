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
var is_sensor_mode: bool = false
var sensor_oracle: SensorOracle

func _ready() -> void:
	mnn = MnnRuntime.new()
	mnn.chat_start()
	mnn.chat_token.connect(_on_mnn_chat_token)
	mnn.chat_done.connect(_on_mnn_chat_done)
	
	if mandala_dial.has_signal("hexagram_changed"):
		mandala_dial.connect("hexagram_changed", Callable(self, "_on_hexagram_changed"))
	
	sensor_oracle = SensorOracle.new()
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
	btn_prev.pressed.connect(mandala_dial.select_prev)
	btn_next.pressed.connect(mandala_dial.select_next)
	
	tab_companion.pressed.connect(func(): _switch_mode("companion"))
	tab_oracle.pressed.connect(func(): _switch_mode("oracle"))
	tab_brain.pressed.connect(func(): _switch_mode("brain"))
	tab_telemetry.pressed.connect(func(): _switch_mode("telemetry"))
	
	_update_mode_ui()
	_update_cast_mode_ui()
	_switch_mode("companion")

func setup_creature(creature: Node3D, mandala: Node3D = null) -> void:
	creature_node = creature
	mandala_3d_node = mandala
	if creature_node:
		if "sensor_mode_enabled" in creature_node:
			creature_node.sensor_mode_enabled = is_sensor_mode
		if creature_node.has_method("get_current_geometry_name"):
			btn_geo_toggle.text = creature_node.get_current_geometry_name()
	if mandala_dial:
		var cur_data: Dictionary = mandala_dial.KING_WEN_DATA[mandala_dial.current_hex_index]
		if creature_node.has_method("set_hexagram"):
			creature_node.set_hexagram(cur_data["bits"], 3)

func _process(_delta: float) -> void:
	lbl_fps.text = "%d FPS" % Engine.get_frames_per_second()

func _on_cast_mode_toggle_pressed() -> void:
	is_sensor_mode = !is_sensor_mode
	_update_cast_mode_ui()
	Input.vibrate_handheld(35)

func _update_cast_mode_ui() -> void:
	if is_sensor_mode:
		btn_cast_mode.text = "🪙 SENSOR CAST"
		btn_cast_mode.modulate = Color(1.0, 0.7, 0.2)
		btn_cast.text = "🎲 SHAKE / TOSS"
		btn_cast.modulate = Color(1.0, 0.75, 0.2)
		if creature_node and "sensor_mode_enabled" in creature_node:
			creature_node.sensor_mode_enabled = true
		lbl_thought.text = "🪙 Real-World Sensor Casting Active! Shake phone, tilt gravity vector, or orient heading to mutate 64 hexagrams."
	else:
		btn_cast_mode.text = "🖐️ MANUAL"
		btn_cast_mode.modulate = Color(0.7, 0.8, 1.0)
		btn_cast.text = "🎲 RANDOM CAST"
		btn_cast.modulate = Color(0.5, 0.9, 1.0)
		if creature_node and "sensor_mode_enabled" in creature_node:
			creature_node.sensor_mode_enabled = false
		lbl_thought.text = "🖐️ Manual Dial Mode. Rotate bottom wheel or tap Prev/Next to inspect all 64 King Wen archetypes."

func _on_shake_started() -> void:
	lbl_thought.text = "🪙 Divination vessel shaking... Rattling coins in sacred motion..."

func _on_shake_progress(p: float) -> void:
	var pct := int(p * 100.0)
	var filled := int(p * 10.0)
	var bar := "█".repeat(filled) + "░".repeat(10 - filled)
	lbl_thought.text = "🪙 Casting Energy: [%s] %d%%. Keep shaking to cast!" % [bar, pct]

func _on_shake_cast_completed(_wen: int, moving_line: int, hex_bits: int) -> void:
	var dial_idx: int = mandala_dial.find_index_by_bits(hex_bits)
	mandala_dial.select_by_index(dial_idx)
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[dial_idx]
	if creature_node and creature_node.has_method("set_hexagram"):
		creature_node.set_hexagram(hex_bits, moving_line)
		
	var move_desc := ("Line %d Mutating" % (moving_line + 1)) if moving_line >= 0 else "Stable Structure"
	lbl_thought.text = "🪙 Sensor Oracle Cast: #%d %s '%s' (0b%06s). %s!" % [
		cur["wen"], cur["zh"], cur["name"],
		String.num_int64(hex_bits, 2).pad_zeros(6),
		move_desc
	]

func _on_autonomous_mutation_stepped(new_bits: int, moving_line: int, reason: String) -> void:
	var dial_idx: int = mandala_dial.find_index_by_bits(new_bits)
	mandala_dial.select_by_index(dial_idx)
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[dial_idx]
	if creature_node and creature_node.has_method("set_hexagram"):
		creature_node.set_hexagram(new_bits, moving_line)
	lbl_thought.text = "🌊 Autonomous Mutation: #%d %s '%s'\n%s" % [
		cur["wen"], cur["zh"], cur["name"], reason
	]

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
	
	var low_idx: int = telem.get("lower_trigram", 7)
	var up_idx: int = telem.get("upper_trigram", 7)
	var lower_name: String = SensorOracle.TRIGRAM_NAMES[low_idx]
	var upper_name: String = SensorOracle.TRIGRAM_NAMES[up_idx]
	
	lbl_thought.text = """☸ MULTI-MODAL SENSOR MANDALA TELEMETRY:
• Light: %.1f lux | Proximity: %.1f cm | Battery: %.0f%%
• Gravity: (%.1f, %.1f, %.1f) m/s² | Heading: %.1f°
• Solar Time: %02d:%02d | Jerk: %.1f m/s²
• Lower Trigram: %s | Upper: %s
• Kinetic Excitation: %.0f%% (Homeostatic Stillness)
• Physical Strains: [L1:%.0f%%, L2:%.0f%%, L3:%.0f%%, L4:%.0f%%, L5:%.0f%%, L6:%.0f%%]
• 8 Orbital Sensor Nodes: Active on 3D Mandala HUD""" % [
		lux_val, prox_val, bat_val,
		g.x, g.y, g.z, heading,
		int(hr_val), int(fmod(hr_val * 60.0, 60.0)), telem.get("jerk", 0.0),
		lower_name, upper_name,
		exc_val * 100.0,
		strains[0] * 100.0, strains[1] * 100.0, strains[2] * 100.0,
		strains[3] * 100.0, strains[4] * 100.0, strains[5] * 100.0
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

func _on_hexagram_changed(wen: int, bits: int, hex_name: String, zh: String) -> void:
	lbl_hex_char.text = zh
	lbl_hex_title.text = "#%d %s %s" % [wen, zh, hex_name]
	
	if sensor_oracle:
		sensor_oracle.inject_manual_state(bits, (wen % 6))
	
	if is_enhanced_mode:
		lbl_hex_subtitle.text = "Binary: 0b%06s  (Lower: %d, Upper: %d)" % [
			String.num_int64(bits, 2).pad_zeros(6),
			bits & 7,
			(bits >> 3) & 7
		]
		var moving: int = (wen % 6)
		lbl_moving_line.text = "Moving Line: Line %d -> Mutating Structure" % (moving + 1)
		if creature_node and creature_node.has_method("set_hexagram"):
			creature_node.set_hexagram(bits, moving)
	else:
		lbl_hex_subtitle.text = "Traditional I-Ching Hexagram"
		lbl_moving_line.text = "Classical Reading (Persona Only)"

func _on_cast_pressed() -> void:
	if is_sensor_mode:
		sensor_oracle._execute_coin_toss_cast()
		return
	Input.vibrate_handheld(25)
	var rand_idx: int = randi() % mandala_dial.KING_WEN_DATA.size()
	mandala_dial.current_hex_index = rand_idx
	mandala_dial._snap_to_closest()
	mandala_dial._emit_current()
	
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[rand_idx]
	if sensor_oracle:
		sensor_oracle.inject_manual_state(cur["bits"], (cur["wen"] % 6))
	if is_enhanced_mode:
		lbl_thought.text = "🪙 Cast Hexagram #%d %s: '%s'. Sovereign equilibrium anchored." % [cur["wen"], cur["zh"], cur["name"]]
	else:
		lbl_thought.text = "🪙 Cast Hexagram #%d %s: '%s'. Pure I-Ching persona consultation ready." % [cur["wen"], cur["zh"], cur["name"]]

func _on_ask_pressed() -> void:
	Input.vibrate_handheld(20)
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[mandala_dial.current_hex_index]
	var moving: int = (cur["wen"] % 6) + 1
	var need_names := ["Body", "Food", "Breath", "Rest", "Focus", "Connection"]
	var changing_need: String = need_names[moving - 1]
	
	var prompt: String
	if is_enhanced_mode:
		lbl_thought.text = "🧠 Consulting Qwen %s [%s Tier]...\nHexagram #%d %s (0b%06s) • Moving Line %d (%s)" % [
			mnn.short_name(), mnn.tier_name(),
			cur["wen"], cur["name"],
			String.num_int64(cur["bits"], 2).pad_zeros(6),
			moving, changing_need
		]
		prompt = "You are Hexy, a worn cybernetic companion building discipline by sensing the body. Current King Wen Hexagram is #%d (%s '%s', bits 0b%06s). Changing line is Line %d (%s need). Give a concise 2-sentence reflection grounding discipline and embodied balance in this hexagram's archetype." % [
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
		if sensor_oracle:
			var g: Vector3 = Input.get_gravity()
			var mag: Vector3 = Input.get_magnetometer()
			var heading: float = posmod(rad_to_deg(atan2(-mag.x, -mag.y)), 360.0) if mag.length_squared() > 0.01 else 0.0
			var low: int = sensor_oracle._classify_lower_trigram_from_gravity(g)
			var up: int = sensor_oracle._classify_upper_trigram_from_heading(heading)
			last_telemetry_data = {"g": g, "heading": heading, "jerk": 0.0, "lower": low, "upper": up}
		_update_telemetry_view()
