class_name ReadingSheet
extends Control

## A THIN SHEET ABOUT ONE READING.
##
## `show_reading` is the one door: a hexagram's bits and the chapter
## chapter dictionary the front already computed. The sheet draws the glyph
## large, the name, the six lines bottom to top, and the chapter's own title
## and gloss. Nothing here recomputes a chapter or a name; it reads what it
## was handed and King Wen's own tables.
##
## NO BUTTONS, NO LONG PRESS. Swipe down more than eighty pixels, or the
## front's back bar, and the page says `closed`.

const SKIN := preload("res://scripts/glass/bubble.gd")
const KingWen := preload("res://scripts/core/iching/king_wen.gd")

const SWIPE_PX: float = 80.0
const GROUND: Color = Color(0.0588235, 0.0823529, 0.12549, 1.0)

const LINE_W: float = 120.0
const LINE_H: float = 10.0
const LINE_GAP_FRAC: float = 0.34 # the gap cut in the middle of a broken line

signal closed()

var panel: PanelContainer = null
var _glyph_label: Label = null
var _title_label: Label = null
var _lines_box: VBoxContainer = null
var _chapter_label: Label = null
var _gloss_label: Label = null

var _drag_from: float = INF


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)

	var ground := ColorRect.new()
	ground.name = "Ground"
	ground.color = GROUND
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 40.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", SKIN.skin())
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)

	_glyph_label = Label.new()
	_glyph_label.name = "Glyph"
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.add_theme_font_size_override("font_size", 64)
	_glyph_label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.70, 1.0))
	col.add_child(_glyph_label)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0, 1.0))
	col.add_child(_title_label)

	_lines_box = VBoxContainer.new()
	_lines_box.name = "Lines"
	_lines_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lines_box.add_theme_constant_override("separation", 6)
	_lines_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_lines_box)

	_chapter_label = Label.new()
	_chapter_label.name = "Chapter"
	_chapter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chapter_label.add_theme_font_size_override("font_size", 17)
	_chapter_label.add_theme_color_override("font_color", Color(0.82, 0.91, 1.0, 1.0))
	col.add_child(_chapter_label)

	_gloss_label = Label.new()
	_gloss_label.name = "Gloss"
	_gloss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gloss_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gloss_label.add_theme_font_size_override("font_size", 14)
	_gloss_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 0.9))
	col.add_child(_gloss_label)


## THE ONE DOOR IN. [param bits] the figure; [param chapter] whatever the
## front's own `current_chapter()` returned -- title, stage name and gloss,
## every one of them off the gauge -- or {} for a chapter that has never been
## walked, in which case stage 0's own words are shown.
func show_reading(bits: int, chapter: Dictionary) -> void:
	var b: int = bits & 63
	_glyph_label.text = KingWen.glyph(b)
	_title_label.text = "#%d %s · %s · %s" % [
		KingWen.number(b), KingWen.name(b), KingWen.zh(b), KingWen.pinyin(b)]

	for kid in _lines_box.get_children():
		kid.queue_free()
	var line_bits: Array[int] = KingWen.lines(b)
	line_bits.reverse() # top to bottom in the array; drawn bottom to top below
	for v in line_bits:
		_lines_box.add_child(_make_bar(v == 1))
	# `lines()` is bottom-first; VBoxContainer stacks top-first, so the
	# reversed array above puts line 6 (top) first in the box and line 1
	# (bottom) last -- which draws bottom to top on the screen.

	var ch: Dictionary = chapter if not chapter.is_empty() else _cold_chapter(b)
	_chapter_label.text = String(ch.get("title", "%s · %s" % [_stage_name(0), KingWen.name(b)]))
	_gloss_label.text = String(ch.get("gloss", _stage_gloss(0)))

	visible = true


## One line: a solid bar for yang, two bars with a gap for yin.
func _make_bar(yang: bool) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(LINE_W, LINE_H)
	if yang:
		var bar := ColorRect.new()
		bar.color = Color(0.90, 0.86, 0.70, 1.0)
		bar.custom_minimum_size = Vector2(LINE_W, LINE_H)
		row.add_child(bar)
	else:
		var gap: float = LINE_W * LINE_GAP_FRAC
		var seg: float = (LINE_W - gap) * 0.5
		var left := ColorRect.new()
		left.color = Color(0.90, 0.86, 0.70, 1.0)
		left.custom_minimum_size = Vector2(seg, LINE_H)
		row.add_child(left)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(gap, LINE_H)
		row.add_child(spacer)
		var right := ColorRect.new()
		right.color = Color(0.90, 0.86, 0.70, 1.0)
		right.custom_minimum_size = Vector2(seg, LINE_H)
		row.add_child(right)
	return row


func _on_input(event: InputEvent) -> void:
	var press: Variant = _press_at(event)
	if press != null:
		_drag_from = (press as Vector2).y
		return
	var at: Variant = _release_at(event)
	if at == null:
		return
	var travel: float = (at as Vector2).y - _drag_from
	_drag_from = INF
	if travel >= SWIPE_PX:
		accept_event()
		closed.emit()


static func _release_at(event: InputEvent) -> Variant:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			return mb.position
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if not st.pressed:
			return st.position
	return null


static func _press_at(event: InputEvent) -> Variant:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			return mb.position
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			return st.position
	return null


## W8e -- STAGE 0'S OWN WORDS, off the gauge when one is bound. A sheet with
## no gauge and no chapter handed in still names the figure, because a reading
## with an empty caption looks broken and a reading with a plain one does not.
var _gauge: RefCounted = null


func set_gauge(gauge: RefCounted) -> void:
	_gauge = gauge


func _stage_name(stage: int) -> String:
	if _gauge == null:
		return "Ordinary World"
	var name: String = String(_gauge.call("stage_name", stage))
	return name if name != "" else "Ordinary World"


func _stage_gloss(stage: int) -> String:
	if _gauge == null:
		return "Nothing moving. Life as usual."
	var g: String = String(_gauge.call("stage_gloss", stage))
	return g if g != "" else "Nothing moving. Life as usual."


func _cold_chapter(bits: int) -> Dictionary:
	return {
		"stage": 0,
		"stage_name": _stage_name(0),
		"gloss": _stage_gloss(0),
		"hexagram_no": KingWen.number(bits),
		"hexagram_name": KingWen.name(bits),
		"title": "%s · %s" % [_stage_name(0), KingWen.name(bits)],
	}
