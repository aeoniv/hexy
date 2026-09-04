extends Control
## Real-Time Interactive Pipeline Visualizer for Hexy's Native C++ & MNN Stack.
## Connects live to MnnRuntime, visualizes every token, byte, and filter decision.

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")

var _runtime: MnnRuntime
var _tokens_queue: Array[String] = []
var _current_token_idx := 0
var _is_playing := false
var _step_delay := 0.25
var _timer := 0.0

# Simulated C++ internal state
var _cpp_accumulator: PackedByteArray = PackedByteArray()
var _cpp_stream_buffer := ""
var _in_think_block := false
var _held_prefix := ""
var _output_text := ""

# UI node references
var _status_lbl: Label
var _layer_boxes: Array[PanelContainer] = []
var _layer_labels: Array[Label] = []
var _input_edit: LineEdit
var _output_lbl: RichTextLabel
var _hex_lbl: Label
var _binary_lbl: Label
var _filter_status_lbl: Label
var _speed_slider: HSlider
var _speed_val_lbl: Label
var _play_btn: Button
var _step_btn: Button


func _ready() -> void:
	_runtime = MnnRuntime.new()
	_build_ui()
	_load_preset(0)


func _process(delta: float) -> void:
	if not _is_playing:
		return
	_timer += delta
	if _timer >= _step_delay:
		_timer = 0.0
		if not _step_next():
			_is_playing = false
			_play_btn.text = "Play Stream"


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var main_margin := MarginContainer.new()
	main_margin.set_anchors_preset(PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 24)
	main_margin.add_theme_constant_override("margin_right", 24)
	main_margin.add_theme_constant_override("margin_top", 20)
	main_margin.add_theme_constant_override("margin_bottom", 20)
	add_child(main_margin)

	var v_box := VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 16)
	main_margin.add_child(v_box)

	# --- Header ---
	var header := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = "HEXY NATIVE C++ & MNN PIPELINE INSPECTOR"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0))
	header.add_child(title_lbl)

	header.add_spacer(false)

	_status_lbl = Label.new()
	_status_lbl.text = "Backend: %s | State: Ready" % _runtime.backend_name()
	_status_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	header.add_child(_status_lbl)
	v_box.add_child(header)

	# --- Presets & Input Bar ---
	var preset_bar := HBoxContainer.new()
	preset_bar.add_theme_constant_override("separation", 8)
	var p_lbl := Label.new()
	p_lbl.text = "Load Scenario:"
	preset_bar.add_child(p_lbl)

	var p1 := Button.new(); p1.text = "1. Standard Dialogue"; p1.pressed.connect(func(): _load_preset(0))
	var p2 := Button.new(); p2.text = "2. Split Multi-Byte Emoji"; p2.pressed.connect(func(): _load_preset(1))
	var p3 := Button.new(); p3.text = "3. <think> Qwen Filter"; p3.pressed.connect(func(): _load_preset(2))
	var p4 := Button.new(); p4.text = "4. CJK Multilingual"; p4.pressed.connect(func(): _load_preset(3))
	preset_bar.add_child(p1)
	preset_bar.add_child(p2)
	preset_bar.add_child(p3)
	preset_bar.add_child(p4)
	v_box.add_child(preset_bar)

	# --- Custom Input Box ---
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	var in_lbl := Label.new()
	in_lbl.text = "Prompt Sequence:"
	input_row.add_child(in_lbl)

	_input_edit = LineEdit.new()
	_input_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_input_edit.text = "Your keys are waiting on the counter by the door."
	_input_edit.text_submitted.connect(func(_t): _reload_from_input())
	input_row.add_child(_input_edit)

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_reload_from_input)
	input_row.add_child(apply_btn)
	v_box.add_child(input_row)

	# --- Main Content: 2 Columns ---
	var content_h := HBoxContainer.new()
	content_h.size_flags_vertical = SIZE_EXPAND_FILL
	content_h.add_theme_constant_override("separation", 24)
	v_box.add_child(content_h)

	# Left Column: 4-Layer Interactive Diagram
	var layers_panel := VBoxContainer.new()
	layers_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	layers_panel.size_flags_stretch_ratio = 1.1
	layers_panel.add_theme_constant_override("separation", 10)
	content_h.add_child(layers_panel)

	var layer_titles := [
		"LAYER 1: GDScript Seam (mnn_runtime.gd)",
		"LAYER 2: Kotlin Worker Queue (IxMnn.kt)",
		"LAYER 3: C++ JNI TokenStream (ixmnn_jni.cpp)",
		"LAYER 4: Alibaba MNN Transformer (libllm.so)"
	]
	var layer_descs := [
		"Receives chat_token / chat_done signals. Updates creature voice & UI without frame drops.",
		"Serializes calls on a single dedicated background thread. Dispatches token byte arrays to Godot.",
		"Custom std::streambuf hooks xsputn(). Executes danglingUtf8 guard & tagPrefixLen filter in C++.",
		"Autoregressive KV-cached token generation. Emits raw bytes directly into the C++ ostream."
	]

	for i in range(4):
		var panel := PanelContainer.new()
		panel.size_flags_vertical = SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.14, 0.18)
		style.border_width_left = 4
		style.border_color = Color(0.25, 0.3, 0.4)
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_right = 6
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)

		var card_v := VBoxContainer.new()
		var t_label := Label.new()
		t_label.text = layer_titles[i]
		t_label.add_theme_font_size_override("font_size", 14)
		t_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		card_v.add_child(t_label)

		var d_label := Label.new()
		d_label.text = layer_descs[i]
		d_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d_label.add_theme_font_size_override("font_size", 11)
		d_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		card_v.add_child(d_label)

		var state_lbl := Label.new()
		state_lbl.text = "Status: IDLE"
		state_lbl.add_theme_font_size_override("font_size", 12)
		state_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		card_v.add_child(state_lbl)

		panel.add_child(card_v)
		layers_panel.add_child(panel)

		_layer_boxes.append(panel)
		_layer_labels.append(state_lbl)

	# Right Column: Live Inspector & Terminal View
	var inspect_panel := VBoxContainer.new()
	inspect_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	inspect_panel.size_flags_stretch_ratio = 1.3
	inspect_panel.add_theme_constant_override("separation", 12)
	content_h.add_child(inspect_panel)

	var byte_card := PanelContainer.new()
	byte_card.size_flags_vertical = SIZE_EXPAND_FILL
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.1, 0.12, 0.16)
	b_style.corner_radius_top_left = 6
	b_style.corner_radius_top_right = 6
	b_style.corner_radius_bottom_left = 6
	b_style.corner_radius_bottom_right = 6
	b_style.content_margin_left = 14
	b_style.content_margin_right = 14
	b_style.content_margin_top = 12
	b_style.content_margin_bottom = 12
	byte_card.add_theme_stylebox_override("panel", b_style)

	var b_vbox := VBoxContainer.new()
	b_vbox.add_theme_constant_override("separation", 8)

	var insp_title := Label.new()
	insp_title.text = "C++ NATIVE BYTE & FILTER DECISION ENGINE"
	insp_title.add_theme_font_size_override("font_size", 13)
	insp_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	b_vbox.add_child(insp_title)

	_hex_lbl = Label.new()
	_hex_lbl.text = "Incoming Hex Bytes: [waiting...]"
	_hex_lbl.add_theme_font_size_override("font_size", 12)
	_hex_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	b_vbox.add_child(_hex_lbl)

	_binary_lbl = Label.new()
	_binary_lbl.text = "UTF-8 Binary Breakdown: [waiting...]"
	_binary_lbl.add_theme_font_size_override("font_size", 11)
	_binary_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	b_vbox.add_child(_binary_lbl)

	_filter_status_lbl = Label.new()
	_filter_status_lbl.text = "Active C++ Filter Checks: None (Standby)"
	_filter_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_filter_status_lbl.add_theme_font_size_override("font_size", 12)
	_filter_status_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	b_vbox.add_child(_filter_status_lbl)

	var div := HSeparator.new()
	b_vbox.add_child(div)

	var out_header := Label.new()
	out_header.text = "LIVE ASSEMBLED SPEECH OUTPUT (Godot Signal Receiver):"
	out_header.add_theme_font_size_override("font_size", 12)
	out_header.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	b_vbox.add_child(out_header)

	_output_lbl = RichTextLabel.new()
	_output_lbl.size_flags_vertical = SIZE_EXPAND_FILL
	_output_lbl.bbcode_enabled = true
	_output_lbl.text = "[color=#778899][Waiting for playback...][/color]"
	b_vbox.add_child(_output_lbl)

	byte_card.add_child(b_vbox)
	inspect_panel.add_child(byte_card)

	# --- Bottom Control Strip ---
	var ctrl_strip := HBoxContainer.new()
	ctrl_strip.add_theme_constant_override("separation", 12)

	_play_btn = Button.new()
	_play_btn.text = "Play Stream"
	_play_btn.pressed.connect(_toggle_play)
	ctrl_strip.add_child(_play_btn)

	_step_btn = Button.new()
	_step_btn.text = "Step Token"
	_step_btn.pressed.connect(func(): _step_next())
	ctrl_strip.add_child(_step_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.pressed.connect(_reset_simulation)
	ctrl_strip.add_child(reset_btn)

	var spd_lbl := Label.new()
	spd_lbl.text = "Speed:"
	ctrl_strip.add_child(spd_lbl)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.05
	_speed_slider.max_value = 0.8
	_speed_slider.step = 0.05
	_speed_slider.value = 0.25
	_speed_slider.custom_minimum_size = Vector2(120, 0)
	_speed_slider.value_changed.connect(func(v):
		_step_delay = v
		_speed_val_lbl.text = "%.2fs / token" % v
	)
	ctrl_strip.add_child(_speed_slider)

	_speed_val_lbl = Label.new()
	_speed_val_lbl.text = "0.25s / token"
	ctrl_strip.add_child(_speed_val_lbl)

	v_box.add_child(ctrl_strip)


func _load_preset(index: int) -> void:
	match index:
		0:
			_input_edit.text = "Your keys are waiting on the counter by the door."
		1:
			_input_edit.text = "Great job today! <split_emoji> See you tomorrow!"
		2:
			_input_edit.text = "<think>Calculating distance to keys... 1.2m at 45 deg.</think>They are right in front of you."
		3:
			_input_edit.text = "Hello! Today everything is running smoothly."
	_reload_from_input()


func _reload_from_input() -> void:
	_reset_simulation()
	var raw_text := _input_edit.text

	if "<split_emoji>" in raw_text:
		_tokens_queue = [
			"Great ", "job ", "today! ",
			"__RAW_HEX_EMOJI_PART_1__",
			"__RAW_HEX_EMOJI_PART_2__",
			"See ", "you ", "tomorrow!"
		]
	else:
		var raw_chunks := MnnRuntime.stream_chunks(raw_text)
		_tokens_queue = []
		for c in raw_chunks:
			_tokens_queue.append(String(c))

	_status_lbl.text = "Loaded %d tokens. Ready to step or play." % _tokens_queue.size()


func _reset_simulation() -> void:
	_is_playing = false
	_play_btn.text = "Play Stream"
	_current_token_idx = 0
	_timer = 0.0
	_cpp_accumulator.clear()
	_cpp_stream_buffer = ""
	_in_think_block = false
	_held_prefix = ""
	_output_text = ""
	_output_lbl.text = "[color=#778899][Waiting for playback...][/color]"
	_hex_lbl.text = "Incoming Hex Bytes: [waiting...]"
	_binary_lbl.text = "UTF-8 Binary Breakdown: [waiting...]"
	_filter_status_lbl.text = "Active C++ Filter Checks: Standby"
	_set_layer_state(0, "IDLE", Color(0.5, 0.5, 0.6))
	_set_layer_state(1, "IDLE", Color(0.5, 0.5, 0.6))
	_set_layer_state(2, "IDLE", Color(0.5, 0.5, 0.6))
	_set_layer_state(3, "IDLE", Color(0.5, 0.5, 0.6))


func _toggle_play() -> void:
	if _current_token_idx >= _tokens_queue.size():
		_reset_simulation()
		_reload_from_input()
	_is_playing = not _is_playing
	_play_btn.text = "Pause" if _is_playing else "Play Stream"


func _step_next() -> bool:
	if _current_token_idx >= _tokens_queue.size():
		_set_layer_state(0, "DONE (Completed)", Color(0.3, 0.9, 0.4))
		_set_layer_state(1, "DONE (Queue Idle)", Color(0.3, 0.9, 0.4))
		_set_layer_state(2, "DONE (Buffer Flushed)", Color(0.3, 0.9, 0.4))
		_set_layer_state(3, "DONE (EOS Reached)", Color(0.3, 0.9, 0.4))
		_filter_status_lbl.text = "Inference complete. Total speech emitted: %d characters." % _output_text.length()
		return false

	var raw_token := _tokens_queue[_current_token_idx]
	_current_token_idx += 1

	_set_layer_state(3, "EMITTING (Token %d/%d)" % [_current_token_idx, _tokens_queue.size()], Color(0.9, 0.6, 0.2))

	var token_bytes := PackedByteArray()
	if raw_token == "__RAW_HEX_EMOJI_PART_1__":
		token_bytes.append(0xF0); token_bytes.append(0x9F); token_bytes.append(0x98)
	elif raw_token == "__RAW_HEX_EMOJI_PART_2__":
		token_bytes.append(0x80); token_bytes.append(0x20)
	else:
		token_bytes = raw_token.to_utf8_buffer()

	var hex_str := ""
	var bin_str := ""
	for b in token_bytes:
		hex_str += "0x%02X " % b
		bin_str += _to_bin_8(b) + " "
	_hex_lbl.text = "Incoming Hex Bytes: [ %s]" % hex_str
	_binary_lbl.text = "UTF-8 Binary Breakdown: [ %s]" % bin_str

	_set_layer_state(2, "PROCESSING (xsputn: %d bytes)" % token_bytes.size(), Color(0.4, 0.8, 1.0))
	_cpp_accumulator.append_array(token_bytes)

	var dangling_count := _calc_dangling_utf8(_cpp_accumulator)
	var filter_log := ""

	if dangling_count > 0:
		filter_log += "[danglingUtf8] Incomplete %d-byte sequence detected at tail! Holding in C++ buffer.\n" % dangling_count
		_set_layer_state(2, "HOLDING (danglingUtf8: %d bytes)" % dangling_count, Color(1.0, 0.7, 0.2))
	else:
		filter_log += "[danglingUtf8] Clean character boundary confirmed.\n"

	var emit_bytes_len := _cpp_accumulator.size() - dangling_count
	var bytes_to_emit := _cpp_accumulator.slice(0, emit_bytes_len)
	_cpp_accumulator = _cpp_accumulator.slice(emit_bytes_len)

	var text_chunk := bytes_to_emit.get_string_from_utf8()

	var speech_to_send := ""
	if text_chunk.length() > 0:
		if "<think>" in text_chunk:
			_in_think_block = true
			filter_log += "[stripThink] Entered <think> reasoning block. Muting output.\n"
		if "</think>" in text_chunk:
			_in_think_block = false
			var parts := text_chunk.split("</think>")
			if parts.size() > 1:
				speech_to_send = parts[1]
			filter_log += "[stripThink] Exited </think> reasoning block. Unmuting speech.\n"
		elif _in_think_block:
			filter_log += "[stripThink] Internal thought suppressed (not spoken).\n"
		else:
			var p_len := _tag_prefix_len(text_chunk, "<think>")
			if p_len > 0:
				filter_log += "[tagPrefixLen] Suffix matches tag prefix (%d chars). Holding back.\n" % p_len
				speech_to_send = text_chunk.substr(0, text_chunk.length() - p_len)
			else:
				speech_to_send = text_chunk

	_filter_status_lbl.text = filter_log

	if speech_to_send.length() > 0:
		_set_layer_state(1, "DISPATCH (onChatToken -> JVM)", Color(0.6, 0.4, 0.9))
		_set_layer_state(0, "SPEAKING (chat_token: \"%s\")" % speech_to_send, Color(0.3, 0.9, 0.4))
		_output_text += speech_to_send
		_output_lbl.text = "[color=#ffffff]%s[/color][color=#38bdf8]|[/color]" % _output_text
	else:
		_set_layer_state(1, "BUFFERING (No speech emitted)", Color(0.5, 0.5, 0.6))
		_set_layer_state(0, "LISTENING (Awaiting clean token)", Color(0.5, 0.5, 0.6))

	return true


func _set_layer_state(idx: int, text: String, color: Color) -> void:
	_layer_labels[idx].text = "Status: " + text
	_layer_labels[idx].add_theme_color_override("font_color", color)
	var style: StyleBoxFlat = _layer_boxes[idx].get_theme_stylebox("panel")
	style.border_color = color


func _calc_dangling_utf8(bytes: PackedByteArray) -> int:
	var n := bytes.size()
	for back in range(1, mini(5, n + 1)):
		var b := bytes[n - back]
		if (b & 0x80) == 0:
			return 0
		if (b & 0xC0) == 0xC0:
			var need := 1
			if (b & 0xE0) == 0xC0: need = 2
			elif (b & 0xF0) == 0xE0: need = 3
			elif (b & 0xF8) == 0xF0: need = 4
			return back if back < need else 0
	return 0


func _tag_prefix_len(s: String, tag: String) -> int:
	var max_len := mini(s.length(), tag.length() - 1)
	for n in range(max_len, 0, -1):
		if s.ends_with(tag.substr(0, n)):
			return n
	return 0


func _to_bin_8(byte_val: int) -> String:
	var s := ""
	for i in range(7, -1, -1):
		s += "1" if (byte_val & (1 << i)) != 0 else "0"
	return s
