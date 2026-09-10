extends Control

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")
const IChingData = preload("res://scripts/iching_data.gd")

@onready var lbl_status: Label = $TopBar/Margin/HBox/Status
@onready var lbl_fps: Label = $TopBar/Margin/HBox/FPS

# Hex Card
@onready var lbl_hex_char: Label = $Content/HexCard/Margin/VBox/HBox/HexChar
@onready var lbl_hex_title: Label = $Content/HexCard/Margin/VBox/HBox/VBox/HexTitle
@onready var lbl_hex_subtitle: Label = $Content/HexCard/Margin/VBox/HBox/VBox/HexSubtitle
@onready var lbl_moving: Label = $Content/HexCard/Margin/VBox/MovingLine

# Lines Container
@onready var lines_container: VBoxContainer = $Content/LinesCard/Margin/LinesVBox

# Qwen Card
@onready var lbl_qwen_output: Label = $Content/QwenCard/Margin/VBox/QwenOutput
@onready var btn_ask_qwen: Button = $Content/QwenCard/Margin/VBox/BtnAskQwen

# Action Controls
@onready var btn_cast: Button = $Content/Actions/BtnCast
@onready var btn_prev: Button = $Content/Actions/BtnPrev
@onready var btn_next: Button = $Content/Actions/BtnNext

# Bottom Navigation
@onready var tab_iching: Button = $BottomNav/HBox/TabIChing
@onready var tab_qwen: Button = $BottomNav/HBox/TabQwen
@onready var tab_mnn: Button = $BottomNav/HBox/TabMnn

var mnn: MnnRuntime
var current_hex_index: int = 0
var current_bits: int = 0b111111
var current_moving: Array = []
var current_cast_lines: Array = [7, 7, 7, 7, 7, 7]

func _ready() -> void:
	mnn = MnnRuntime.new()
	lbl_status.text = "MNN: %s" % (mnn.backend_name().to_upper())
	
	mnn.chat_token.connect(_on_qwen_token)
	mnn.chat_done.connect(_on_qwen_done)
	
	btn_cast.pressed.connect(_on_cast_pressed)
	btn_ask_qwen.pressed.connect(_on_ask_qwen_pressed)
	btn_prev.pressed.connect(_on_prev_pressed)
	btn_next.pressed.connect(_on_next_pressed)
	
	tab_iching.pressed.connect(func(): _switch_tab(0))
	tab_qwen.pressed.connect(func(): _switch_tab(1))
	tab_mnn.pressed.connect(func(): _switch_tab(2))
	
	_update_display()

func _process(_delta: float) -> void:
	lbl_fps.text = "%d FPS" % Engine.get_frames_per_second()

func _on_cast_pressed() -> void:
	var cast = IChingData.cast_coins()
	current_cast_lines = cast["lines"]
	current_bits = cast["bits"]
	current_moving = cast["moving"]
	
	for i in range(IChingData.HEXAGRAMS.size()):
		if IChingData.HEXAGRAMS[i]["bits"] == current_bits:
			current_hex_index = i
			break
	
	_update_display()
	lbl_qwen_output.text = "Oracle cast completed. Tap 'Ask Qwen' to interpret hexagram."

func _on_prev_pressed() -> void:
	current_hex_index = (current_hex_index - 1 + IChingData.HEXAGRAMS.size()) % IChingData.HEXAGRAMS.size()
	_load_current_index()

func _on_next_pressed() -> void:
	current_hex_index = (current_hex_index + 1) % IChingData.HEXAGRAMS.size()
	_load_current_index()

func _load_current_index() -> void:
	var h = IChingData.HEXAGRAMS[current_hex_index]
	current_bits = h["bits"]
	current_moving.clear()
	current_cast_lines.clear()
	for i in range(6):
		var is_yang = ((current_bits >> i) & 1) == 1
		current_cast_lines.append(7 if is_yang else 8)
	_update_display()

func _update_display() -> void:
	var h = IChingData.find_by_bits(current_bits)
	lbl_hex_char.text = h["zh"]
	lbl_hex_title.text = "#%d %s %s" % [h["num"], h["zh"], h["name"]]
	lbl_hex_subtitle.text = "Binary: 0b%s | %s" % [String.num_int64(current_bits, 2).pad_zeros(6), h["judgment"]]
	
	if current_moving.is_empty():
		lbl_moving.text = "Static Hexagram (No moving lines)"
	else:
		lbl_moving.text = "Moving Lines: %s -> Mutating" % [str(current_moving)]
	
	_render_hexagram_lines()

func _render_hexagram_lines() -> void:
	for child in lines_container.get_children():
		child.queue_free()
	
	for i in range(5, -1, -1):
		var line_val = current_cast_lines[i] if i < current_cast_lines.size() else (7 if ((current_bits >> i) & 1) == 1 else 8)
		var is_yang = (line_val == 7 or line_val == 9)
		var is_moving = (line_val == 6 or line_val == 9)
		
		var line_row := HBoxContainer.new()
		line_row.custom_minimum_size = Vector2(0, 24)
		line_row.alignment = BoxContainer.ALIGNMENT_CENTER
		line_row.add_theme_constant_override("separation", 16)
		
		var color = Color(0.95, 0.75, 0.2) if is_moving else (Color(0.2, 0.85, 1.0) if is_yang else Color(0.6, 0.7, 0.85))
		
		if is_yang:
			var bar := ColorRect.new()
			bar.custom_minimum_size = Vector2(240, 12)
			bar.color = color
			line_row.add_child(bar)
		else:
			var bar_left := ColorRect.new()
			bar_left.custom_minimum_size = Vector2(105, 12)
			bar_left.color = color
			line_row.add_child(bar_left)
			
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(30, 12)
			line_row.add_child(gap)
			
			var bar_right := ColorRect.new()
			bar_right.custom_minimum_size = Vector2(105, 12)
			bar_right.color = color
			line_row.add_child(bar_right)
		
		lines_container.add_child(line_row)

func _on_ask_qwen_pressed() -> void:
	var h = IChingData.find_by_bits(current_bits)
	lbl_qwen_output.text = "Thinking via Alibaba MNN Qwen..."
	var prompt = "Explain I-Ching Hexagram #%d (%s, %s): %s. Moving lines: %s. Give practical guidance." % [
		h["num"], h["zh"], h["name"], h["judgment"], str(current_moving)
	]
	
	mnn.chat_start()
	if not mnn.chat_stream(prompt):
		var reply = mnn.chat(prompt)
		lbl_qwen_output.text = reply

func _on_qwen_token(token: String) -> void:
	if lbl_qwen_output.text == "Thinking via Alibaba MNN Qwen...":
		lbl_qwen_output.text = ""
	lbl_qwen_output.text += token

func _on_qwen_done(full_reply: String) -> void:
	if lbl_qwen_output.text.is_empty():
		lbl_qwen_output.text = full_reply

func _switch_tab(tab_index: int) -> void:
	match tab_index:
		0:
			$Content/HexCard.visible = true
			$Content/LinesCard.visible = true
			$Content/QwenCard.visible = false
			$Content/MnnCard.visible = false
		1:
			$Content/HexCard.visible = true
			$Content/LinesCard.visible = false
			$Content/QwenCard.visible = true
			$Content/MnnCard.visible = false
		2:
			$Content/HexCard.visible = false
			$Content/LinesCard.visible = false
			$Content/QwenCard.visible = false
			$Content/MnnCard.visible = true
			_update_mnn_card()

func _update_mnn_card() -> void:
	var info: String = "Alibaba MNN Hardware Status:\n"
	info += "• Backend: %s\n" % mnn.backend_name().to_upper()
	info += "• Native JNI: %s\n" % ("ATTACHED" if mnn.available() else "OFFLINE")
	info += "• Qwen Model: %s\n" % mnn.chat_model()
	info += "• Embed Dimension: %d\n" % mnn.embed_dim()
	info += "• Engine FPS: %d FPS\n" % Engine.get_frames_per_second()
	$Content/MnnCard/Margin/VBox/MnnTelemetry.text = info
