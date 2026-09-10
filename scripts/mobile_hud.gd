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
@onready var tab_oracle: Button = $BottomNav/HBox/TabOracle
@onready var tab_qwen: Button = $BottomNav/HBox/TabQwen
@onready var tab_mnn: Button = $BottomNav/HBox/TabMnn

var mnn: MnnRuntime
var creature_node: Node3D
var active_mode: String = "oracle"

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
	
	tab_oracle.pressed.connect(func(): _switch_mode("oracle"))
	tab_qwen.pressed.connect(func(): _switch_mode("qwen"))
	tab_mnn.pressed.connect(func(): _switch_mode("mnn"))
	
	_switch_mode("oracle")

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
	lbl_thought.text = "🧠 Consulting Qwen via MNN...
Prompt: 'Counsel on Hexagram #%d %s'" % [cur["wen"], cur["name"]]
	
	var reply: String = mnn.chat("What is the counsel of Hexagram %d %s?" % [cur["wen"], cur["name"]])
	lbl_thought.text = "💬 Qwen (%s):
%s" % [mnn.backend_name(), reply]

func _switch_mode(mode: String) -> void:
	active_mode = mode
	tab_oracle.modulate = Color(1.0, 1.0, 1.0, 1.0 if mode == "oracle" else 0.5)
	tab_qwen.modulate = Color(1.0, 1.0, 1.0, 1.0 if mode == "qwen" else 0.5)
	tab_mnn.modulate = Color(1.0, 1.0, 1.0, 1.0 if mode == "mnn" else 0.5)
	
	if mode == "oracle":
		mandala_container.visible = true
		thought_bubble.visible = true
		hex_card.visible = true
	elif mode == "qwen":
		mandala_container.visible = false
		thought_bubble.visible = true
		hex_card.visible = true
		_on_ask_pressed()
	elif mode == "mnn":
		mandala_container.visible = false
		thought_bubble.visible = true
		hex_card.visible = false
		var v1: PackedFloat32Array = mnn.embed("I-Ching Hexagram Balance")
		var v2: PackedFloat32Array = mnn.embed("I-Ching Hexagram Balance")
		var sim: float = MnnRuntime.cosine(v1, v2)
		lbl_thought.text = "⚡ MNN Runtime Telemetry:
Backend: %s
Model: %s
Embedding Dim: %d
Self-Cosine Similarity: %.4f
JNI Attached: %s" % [
			mnn.backend_name(), mnn.chat_model(), mnn.embed_dim(), sim, str(mnn.available())
		]
