extends Control

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")
const MandalaDial2D = preload("res://scripts/mandala_dial_2d.gd")
const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")

@onready var top_bar: PanelContainer = $TopBar
@onready var lbl_title: Label = $TopBar/Margin/HBox/Title
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
var active_mode: String = "companion"
var is_enhanced_mode: bool = true

func _ready() -> void:
	mnn = MnnRuntime.new()
	
	if mandala_dial.has_signal("hexagram_changed"):
		mandala_dial.connect("hexagram_changed", Callable(self, "_on_hexagram_changed"))
	
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
	_switch_mode("companion")

func setup_creature(creature: Node3D) -> void:
	creature_node = creature
	if mandala_dial:
		var cur_data: Dictionary = mandala_dial.KING_WEN_DATA[mandala_dial.current_hex_index]
		if creature_node.has_method("set_hexagram"):
			creature_node.set_hexagram(cur_data["bits"], 3)

func _process(_delta: float) -> void:
	lbl_fps.text = "%d FPS" % Engine.get_frames_per_second()

func _on_mode_toggle_pressed() -> void:
	is_enhanced_mode = !is_enhanced_mode
	_update_mode_ui()
	Input.vibrate_handheld(30)

func _update_mode_ui() -> void:
	if is_enhanced_mode:
		btn_mode_toggle.text = "⚡ ENHANCED"
		btn_mode_toggle.modulate = Color(0.3, 0.95, 1.0)
		if creature_node:
			creature_node.visible = true
		lbl_thought.text = "⚡ Mode: ENHANCED (Structural Cybernetics). Hexagram 6-bit states, moving line mutations, and tensegrity equilibrium active."
	else:
		btn_mode_toggle.text = "☯ PURE"
		btn_mode_toggle.modulate = Color(0.95, 0.8, 0.3)
		if creature_node:
			creature_node.visible = false
		lbl_thought.text = "☯ Mode: PURE (I-Ching Character Persona). Qwen acts strictly as the Book of Changes oracle persona without structural tensegrity math."

func _on_hexagram_changed(wen: int, bits: int, hex_name: String, zh: String) -> void:
	lbl_hex_char.text = zh
	lbl_hex_title.text = "#%d %s %s" % [wen, zh, hex_name]
	
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
	Input.vibrate_handheld(25)
	var rand_idx: int = randi() % mandala_dial.KING_WEN_DATA.size()
	mandala_dial.current_hex_index = rand_idx
	mandala_dial._snap_to_closest()
	mandala_dial._emit_current()
	
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[rand_idx]
	if is_enhanced_mode:
		lbl_thought.text = "🪙 Cast Hexagram #%d %s: '%s'. Structural equilibrium adapting..." % [cur["wen"], cur["zh"], cur["name"]]
	else:
		lbl_thought.text = "🪙 Cast Hexagram #%d %s: '%s'. Pure I-Ching persona consultation ready." % [cur["wen"], cur["zh"], cur["name"]]

func _on_ask_pressed() -> void:
	Input.vibrate_handheld(20)
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[mandala_dial.current_hex_index]
	
	var prompt: String
	if is_enhanced_mode:
		lbl_thought.text = "🧠 Consulting MNN Enhanced (Structural)...
Hexagram #%d %s (0b%06s)" % [cur["wen"], cur["name"], String.num_int64(cur["bits"], 2).pad_zeros(6)]
		prompt = "Explain I-Ching Hexagram #%d (%s, %s): Binary 0b%06s. Moving line %d mutating structure. Analyze polarity balance and structural guidance." % [
			cur["wen"], cur["zh"], cur["name"],
			String.num_int64(cur["bits"], 2).pad_zeros(6),
			(cur["wen"] % 6) + 1
		]
	else:
		lbl_thought.text = "☯ Consulting MNN Pure (I-Ching Persona)...
Hexagram #%d %s" % [cur["wen"], cur["name"]]
		prompt = "You are the ancient I-Ching oracle. In character as the Book of Changes, speak poetically and provide concise wisdom on Hexagram #%d %s (%s)." % [
			cur["wen"], cur["zh"], cur["name"]
		]
	
	var reply: String = mnn.chat(prompt)
	lbl_thought.text = "💬 Qwen (%s - %s):
%s" % [mnn.backend_name(), "ENHANCED" if is_enhanced_mode else "PURE", reply]

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
		lbl_thought.text = "🧠 MNN Neural Brain Space:
Mode: %s
Embed Dimension: %d
Self-Cosine Similarity: %.4f
Backend: %s
Model: %s" % [
			"ENHANCED" if is_enhanced_mode else "PURE",
			mnn.embed_start(), sim, mnn.backend_name(), mnn.chat_model()
		]
	elif mode == "telemetry":
		mandala_container.visible = false
		thought_bubble.visible = true
		var grav: Vector3 = Input.get_gravity()
		lbl_thought.text = "⚡ Hardware & JNI Telemetry:
Mode: %s
Device: Samsung Galaxy A22
GPU: Mali-G57 MC2 (Vulkan 1.1)
Gravity: (%.2f, %.2f, %.2f)
JNI Attached: %s
Creature Struts: 6 | Cords: 24" % [
			"ENHANCED" if is_enhanced_mode else "PURE",
			grav.x, grav.y, grav.z, str(mnn.available())
		]
