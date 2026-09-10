extends Control

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")
const MandalaDial2D = preload("res://scripts/mandala_dial_2d.gd")
const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")

@onready var top_bar: PanelContainer = $TopBar
@onready var lbl_title: Label = $TopBar/Margin/HBox/Title
@onready var lbl_status: Label = $TopBar/Margin/HBox/Status
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

func _ready() -> void:
	mnn = MnnRuntime.new()
	var backend: String = mnn.backend_name()
	var is_avail: bool = mnn.available()
	lbl_status.text = "MNN: %s (%s)" % [backend.to_upper(), "JNI" if is_avail else "FALLBACK"]
	
	if mandala_dial.has_signal("hexagram_changed"):
		mandala_dial.connect("hexagram_changed", Callable(self, "_on_hexagram_changed"))
	
	btn_cast.pressed.connect(_on_cast_pressed)
	btn_ask.pressed.connect(_on_ask_pressed)
	btn_prev.pressed.connect(mandala_dial.select_prev)
	btn_next.pressed.connect(mandala_dial.select_next)
	
	tab_companion.pressed.connect(func(): _switch_mode("companion"))
	tab_oracle.pressed.connect(func(): _switch_mode("oracle"))
	tab_brain.pressed.connect(func(): _switch_mode("brain"))
	tab_telemetry.pressed.connect(func(): _switch_mode("telemetry"))
	
	_switch_mode("companion")

func setup_creature(creature: Node3D) -> void:
	creature_node = creature
	if mandala_dial:
		var cur_data: Dictionary = mandala_dial.KING_WEN_DATA[mandala_dial.current_hex_index]
		if creature_node.has_method("set_hexagram"):
			creature_node.set_hexagram(cur_data["bits"], 3)

func _process(_delta: float) -> void:
	lbl_fps.text = "%d FPS" % Engine.get_frames_per_second()

func _on_hexagram_changed(wen: int, bits: int, hex_name: String, zh: String) -> void:
	lbl_hex_char.text = zh
	lbl_hex_title.text = "#%d %s %s" % [wen, zh, hex_name]
	lbl_hex_subtitle.text = "Binary: 0b%06s  (Lower: %d, Upper: %d)" % [
		String.num_int64(bits, 2).pad_zeros(6),
		bits & 7,
		(bits >> 3) & 7
	]
	
	var moving: int = (wen % 6)
	lbl_moving_line.text = "Moving Line: Line %d -> Mutating Structure" % (moving + 1)
	
	if creature_node and creature_node.has_method("set_hexagram"):
		creature_node.set_hexagram(bits, moving)

func _on_cast_pressed() -> void:
	Input.vibrate_handheld(25)
	var rand_idx: int = randi() % mandala_dial.KING_WEN_DATA.size()
	mandala_dial.current_hex_index = rand_idx
	mandala_dial._snap_to_closest()
	mandala_dial._emit_current()
	
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[rand_idx]
	lbl_thought.text = "🪙 Cast Hexagram #%d %s: '%s'. Structure equilibrium adapting..." % [cur["wen"], cur["zh"], cur["name"]]

func _on_ask_pressed() -> void:
	Input.vibrate_handheld(20)
	var cur: Dictionary = mandala_dial.KING_WEN_DATA[mandala_dial.current_hex_index]
	lbl_thought.text = "🧠 Consulting MNN (%s)...\nPrompt: 'Guidance on Hexagram #%d %s'" % [mnn.chat_model(), cur["wen"], cur["name"]]
	
	var reply: String = mnn.chat("What is the counsel of Hexagram %d %s?" % [cur["wen"], cur["name"]])
	lbl_thought.text = "💬 Hexy (%s):\n%s" % [mnn.backend_name(), reply]

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
	elif mode == "oracle":
		mandala_container.visible = true
		thought_bubble.visible = true
		hex_card.visible = true
	elif mode == "brain":
		mandala_container.visible = false
		thought_bubble.visible = true
		var v1: PackedFloat32Array = mnn.embed("hexy creature tensegrity")
		var v2: PackedFloat32Array = mnn.embed("hexy creature tensegrity")
		var sim: float = MnnRuntime.cosine(v1, v2)
		lbl_thought.text = "🧠 MNN Neural Brain Space:\nEmbed Dimension: %d\nSelf-Cosine Similarity: %.4f\nBackend: %s\nModel: %s" % [
			mnn.embed_start(), sim, mnn.backend_name(), mnn.chat_model()
		]
	elif mode == "telemetry":
		mandala_container.visible = false
		thought_bubble.visible = true
		var grav: Vector3 = Input.get_gravity()
		lbl_thought.text = "⚡ Hardware & JNI Telemetry:\nDevice: Samsung Galaxy A22\nGPU: Mali-G57 MC2 (Vulkan 1.1)\nGravity Sensor: (%.2f, %.2f, %.2f)\nJNI Attached: %s\nStrut Count: 6 | Cord Count: 24" % [
			grav.x, grav.y, grav.z, str(mnn.available())
		]
