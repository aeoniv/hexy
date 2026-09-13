class_name GlassBubble
extends PanelContainer

## THE ONE PLACE THE GLASS SPEAKS.
##
## Every sentence this app has -- a sense speaking, a model answering, the
## telemetry, the brain -- arrives in this one bubble, and the bubble arrives
## NEXT TO WHATEVER SAID IT. A fixed panel at the bottom of the screen makes
## every voice sound the same and steals the room the dials need; a bubble with
## a tail says which dot, which diamond, which station spoke, and then gets out
## of the way.
##
## IT FADES ON ITS OWN. Six seconds, or one tap. Nothing here waits to be
## dismissed, because a surface that accumulates panels is a surface a person
## has to tidy.
##
## TWO SIZES, ONE SKIN. Small is at most four lines and wraps; large is the
## same bubble grown and scrollable, which is what the telemetry and the brain
## open into. There is no second panel class, so there is no second look.

## How long a bubble stands before it fades, in milliseconds. The test reads
## this, and may lower it; nothing else should.
const FADE_MS: int = 6000

## The widest a small bubble is allowed to be, in pixels.
const MAX_WIDTH: float = 420.0

## How much of the glass a large bubble takes.
const LARGE_FRACTION: Vector2 = Vector2(0.92, 0.6)

## The tail, in pixels: how far it reaches and how wide its base is.
const TAIL_REACH: float = 11.0
const TAIL_BASE: float = 9.0

var fade_ms: int = FADE_MS

var label: Label = null

var _margin: MarginContainer = null
var _scroll: ScrollContainer = null
var _until_ms: int = 0
var _large: bool = false
var _tail_at: Vector2 = Vector2.ZERO


## The glass skin, built in code and shared by every panel on this surface.
## The numbers are scenes/main.tscn's StyleBoxFlat_glass, verbatim.
static func skin() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0784314, 0.117647, 0.180392, 0.8)
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = Color(0.2, 0.5, 0.8, 0.35)
	box.corner_radius_top_left = 12
	box.corner_radius_top_right = 12
	box.corner_radius_bottom_right = 12
	box.corner_radius_bottom_left = 12
	return box


func _ready() -> void:
	name = "Bubble"
	add_theme_stylebox_override("panel", skin())
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	visible = false

	_margin = MarginContainer.new()
	_margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 10)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_scroll)

	label = Label.new()
	label.name = "Says"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 4
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.82, 0.9, 0.97, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(label)
	set_process(true)


## A short sentence, pointing at the thing that said it. [param at] is a point
## in this bubble's parent's coordinates.
func say(text: String, at: Vector2) -> void:
	_large = false
	label.max_lines_visible = 4
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	label.text = text
	_place(at)
	visible = true
	_until_ms = Time.get_ticks_msec() + maxi(1, fade_ms)


## More words than four lines hold: the same bubble, grown and scrollable.
func open_large(text: String, at: Vector2) -> void:
	_large = true
	label.max_lines_visible = 0
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	label.text = text
	_place(at)
	visible = true
	_until_ms = 0


## A token from the model, appended to whatever is already standing. A stream
## keeps the bubble alive; it does not start a new one.
func stream(text: String) -> void:
	if not visible:
		return
	label.text = text
	if not _large:
		_until_ms = Time.get_ticks_msec() + maxi(1, fade_ms)


func close() -> void:
	visible = false
	_until_ms = 0


func says() -> String:
	return label.text


func large() -> bool:
	return _large and visible


func _process(_delta: float) -> void:
	if not visible or _until_ms <= 0:
		return
	if Time.get_ticks_msec() >= _until_ms:
		close()


## Where the bubble stands: beside the point that spoke, nudged back inside the
## glass, with the tail left pointing at the point whatever the nudge did.
func _place(at: Vector2) -> void:
	var box: Vector2 = _room()
	var want: Vector2 = Vector2.ZERO
	if _large:
		want = box * LARGE_FRACTION
	else:
		var w: float = minf(MAX_WIDTH, maxf(160.0, box.x - 24.0))
		want = Vector2(w, _height_for(w))
	size = want

	var p: Vector2 = at + Vector2(-want.x * 0.5, TAIL_REACH + 8.0)
	if at.y > box.y * 0.6:
		p.y = at.y - want.y - TAIL_REACH - 8.0
	if _large:
		p = (box - want) * 0.5
	p.x = clampf(p.x, 8.0, maxf(8.0, box.x - want.x - 8.0))
	p.y = clampf(p.y, 8.0, maxf(8.0, box.y - want.y - 8.0))
	position = p
	_tail_at = at - p
	queue_redraw()


## The height four wrapped lines of this text need, plus the margins.
func _height_for(w: float) -> float:
	var inner: float = maxf(40.0, w - 20.0)
	var font: Font = label.get_theme_font("font")
	var fs: int = label.get_theme_font_size("font_size")
	if font == null:
		return 64.0
	var lines: float = ceilf(font.get_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x / inner)
	lines = clampf(lines, 1.0, 4.0)
	return lines * float(font.get_height(fs)) + 24.0


func _room() -> Vector2:
	var p: Control = get_parent() as Control
	return p.size if p != null else Vector2(720.0, 1280.0)


## The tail: one small triangle on the edge nearest what spoke.
func _draw() -> void:
	if _large:
		return
	var mid: Vector2 = size * 0.5
	var up: bool = _tail_at.y < mid.y
	var y: float = 0.0 if up else size.y
	var x: float = clampf(_tail_at.x, TAIL_BASE + 6.0, maxf(TAIL_BASE + 6.0, size.x - TAIL_BASE - 6.0))
	var tip := Vector2(x, y + (-TAIL_REACH if up else TAIL_REACH))
	var pts := PackedVector2Array([
		Vector2(x - TAIL_BASE, y), Vector2(x + TAIL_BASE, y), tip,
	])
	draw_colored_polygon(pts, Color(0.0784314, 0.117647, 0.180392, 0.8))


func _on_input(event: InputEvent) -> void:
	if _is_release(event):
		close()
		accept_event()


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false
