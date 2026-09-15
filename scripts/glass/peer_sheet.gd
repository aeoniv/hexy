class_name PeerSheet
extends Control

## A THIN SHEET ABOUT ONE PEER.
##
## Everything this sheet knows arrives in one call, `show_peer`, as the row
## `wmn.peers()` already keeps and the plot `radar.peer_plots()` already
## computed for that same peer. The sheet invents nothing: no distance, no
## bearing, no name it did not read off `Identity`.
##
## NO BUTTONS, NO LONG PRESS. The only thing a finger can do here besides
## swipe down is tap the trigram glyph, which toggles guidance the same way
## the radar's own tap does. Swipe down more than eighty pixels, or the
## front's back bar, and the page says `closed`.

const SKIN := preload("res://scripts/glass/bubble.gd")
const Identity := preload("res://scripts/social/identity.gd")
const KingWen := preload("res://scripts/core/iching/king_wen.gd")

## How far down a swipe has to travel to close the sheet.
const SWIPE_PX: float = 80.0

## "just now" below this many seconds.
const JUST_NOW_S: int = 5

const GROUND: Color = Color(0.0588235, 0.0823529, 0.12549, 1.0)

## Somebody tapped the trigram glyph and wants guidance to this peer.
signal guide_requested(who: String)
## The same tap, the second time: guidance is cancelled.
signal guide_cleared()
## Swipe down, or the back bar: the sheet is done.
signal closed()

var panel: PanelContainer = null
var _name_label: Label = null
var _swatch: ColorRect = null
var _band_label: Label = null
var _cls_label: Label = null
var _trigram_label: Label = null
var _phase_label: Label = null
var _stage_label: Label = null
var _seen_label: Label = null

var _who: String = ""
var _guiding: bool = false
var _drag_from: float = INF
## Whether the finger that is down landed on the ground around the panel
## rather than on the panel itself: a tap there is a dismissal.
var _pressed_outside: bool = false

const PHASE_WORDS: Array[String] = ["night", "dawn", "day", "dusk"]


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
	## THE PANEL HEARS THE SWIPE TOO. It covers the top of the glass and STOPs
	## input of its own, so a finger that starts a swipe DOWN -- which is where
	## a swipe down starts -- never reached the sheet underneath it, and the
	## sheet had no working way out at all.
	panel.gui_input.connect(_on_panel_input)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	col.add_child(head_row)

	_swatch = ColorRect.new()
	_swatch.name = "Swatch"
	_swatch.custom_minimum_size = Vector2(20.0, 20.0)
	head_row.add_child(_swatch)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0, 1.0))
	head_row.add_child(_name_label)

	var trigram_button := Control.new()
	trigram_button.name = "TrigramTap"
	trigram_button.mouse_filter = Control.MOUSE_FILTER_STOP
	trigram_button.custom_minimum_size = Vector2(48.0, 48.0)
	trigram_button.gui_input.connect(_on_trigram_input)
	col.add_child(trigram_button)

	_trigram_label = Label.new()
	_trigram_label.name = "Trigram"
	_trigram_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trigram_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_trigram_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_trigram_label.add_theme_font_size_override("font_size", 34)
	_trigram_label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.70, 1.0))
	_trigram_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trigram_button.add_child(_trigram_label)

	_band_label = Label.new()
	_band_label.name = "Band"
	_band_label.add_theme_font_size_override("font_size", 15)
	_band_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 0.9))
	col.add_child(_band_label)

	_cls_label = Label.new()
	_cls_label.name = "Cls"
	_cls_label.add_theme_font_size_override("font_size", 15)
	_cls_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 0.9))
	col.add_child(_cls_label)

	_phase_label = Label.new()
	_phase_label.name = "Phase"
	_phase_label.add_theme_font_size_override("font_size", 15)
	_phase_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 0.9))
	col.add_child(_phase_label)

	_stage_label = Label.new()
	_stage_label.name = "Stage"
	_stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage_label.add_theme_font_size_override("font_size", 15)
	_stage_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 0.9))
	col.add_child(_stage_label)

	_seen_label = Label.new()
	_seen_label.name = "Seen"
	_seen_label.add_theme_font_size_override("font_size", 13)
	_seen_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 0.8))
	col.add_child(_seen_label)

	## THE GLASS IS MEASURED ONCE THE SHEET IS IN IT, and again whenever it
	## changes shape -- see [method _fit_to_viewport].
	_fit_to_viewport()
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)


## THE ONE DOOR IN. [param row] is a `wmn.peers()` row; [param plot] is that
## same peer's entry out of `radar.peer_plots()`, or {} when the radar has
## not placed them yet.
func show_peer(row: Dictionary, plot: Dictionary) -> void:
	_who = String(row.get("who", ""))
	_guiding = false

	var hue: float = Identity.hue_from_id(_who)
	_swatch.color = Identity.body_color(hue)
	# `who` is the fabric id `wmn.peers()` keeps; short_name mints the same
	# "hexy-xxxx" a person reads everywhere else on the glass.
	_name_label.text = Identity.short_name(_who)

	_band_label.text = "band: %s" % String(row.get("band", "?"))
	_cls_label.text = "proximity: %s" % (String(row.get("cls", "")) if String(row.get("cls", "")) != "" else "unplaced")

	var heading_rad: Variant = row.get("heading_rad", null)
	_trigram_label.text = KingWen.heading_glyph(float(heading_rad)) if heading_rad != null else "?"

	var phase: Variant = row.get("phase", null)
	var phase_txt: String = _phase_word(float(phase)) if phase != null else "unknown"
	if bool(plot.get("in_phase", false)):
		phase_txt += " · in phase with you"
	_phase_label.text = "phase: %s" % phase_txt

	var stage: Variant = row.get("stage", null)
	var stage_txt: String = _stage_name(int(stage)) if stage != null else "unknown"
	if bool(plot.get("mentor", false)):
		stage_txt += " · one chapter ahead"
	_stage_label.text = "stage: %s" % stage_txt

	_seen_label.text = _last_seen_text(int(row.get("last_seen_ms", 0)))

	_fit_to_viewport()
	visible = true


static func _phase_word(phase: float) -> String:
	var idx: int = posmod(int(floor(phase * 4.0)), 4)
	return PHASE_WORDS[idx]


## [param now_ms], when given, replaces `Time.get_ticks_msec()` -- the door a
## test uses so a fake "last seen" timestamp need not race the real clock.
static func _last_seen_text(last_seen_ms: int, now_ms: int = -1) -> String:
	if last_seen_ms <= 0:
		return "last seen: unknown"
	var now: int = now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var age_ms: int = maxi(0, now - last_seen_ms)
	var age_s: int = age_ms / 1000
	if age_s < JUST_NOW_S:
		return "last seen: just now"
	if age_s < 60:
		return "last seen: %d s ago" % age_s
	return "last seen: %d min ago" % (age_s / 60)


func _on_trigram_input(event: InputEvent) -> void:
	if _release_at(event) == null:
		return
	get_viewport().set_input_as_handled()
	if _guiding:
		_guiding = false
		guide_cleared.emit()
	else:
		_guiding = true
		guide_requested.emit(_who)


## A finger on the ground around the panel.
func _on_input(event: InputEvent) -> void:
	_read_gesture(event, true)


## A finger on the panel itself: it can swipe the sheet away, but a tap on the
## panel is a tap on what the panel says and never a dismissal.
func _on_panel_input(event: InputEvent) -> void:
	_read_gesture(event, false)


## THE TWO WAYS OUT, read in one place. Swipe down anywhere -- the panel
## included -- and the sheet is done; tap the ground beside the panel and it
## is done as well. Both say `closed` and nothing else: the sheet does not
## know what is underneath it and must not pretend to.
func _read_gesture(event: InputEvent, outside: bool) -> void:
	var press: Variant = _press_at(event)
	if press != null:
		_drag_from = (press as Vector2).y
		_pressed_outside = outside
		return
	var at: Variant = _release_at(event)
	if at == null or is_inf(_drag_from):
		return
	var travel: float = (at as Vector2).y - _drag_from
	var began_outside: bool = _pressed_outside
	_drag_from = INF
	_pressed_outside = false
	if travel >= SWIPE_PX:
		accept_event()
		closed.emit()
		return
	if began_outside:
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


## W8e -- THE CHAPTER'S NAME COMES OFF THE GAUGE. The ten stage names used to
## be a const array in the core; they are a data table in gauge.json now, so a
## sheet that wants to name a peer's chapter asks the one gauge this app is
## reading. With no gauge bound it says "stage N", which is honest: the number
## is the peer's own, only the word for it is missing.
var _gauge: RefCounted = null


func set_gauge(gauge: RefCounted) -> void:
	_gauge = gauge


func _stage_name(stage: int) -> String:
	if _gauge == null:
		return "stage %d" % stage
	var name: String = String(_gauge.call("stage_name", stage))
	return name if name != "" else "stage %d" % stage
## THE SHEET IS THE WHOLE GLASS, MEASURED AND NOT ASSUMED.
##
## Anchored FULL_RECT under its own CanvasLayer this Control still measured
## 0 x 0 on the Fold4's 1812 x 2176 inner screen, which is what the device
## retest was really looking at: the transparent catcher behind the panel had
## no area at all, so a tap on the ground beside the panel fell straight
## through to the front underneath and the sheet never heard it -- and the
## panel, sized to its own content, sat in the top-left corner of a very tall
## screen looking like nothing had happened at all. The viewport's own visible
## rect is the one measurement never in doubt; it is asked for, written in,
## and asked again whenever the glass changes shape.
##
## TOP_LEFT ANCHORS ON PURPOSE: with all four anchors at zero, writing `size`
## IS the layout rather than a fight with it, and Godot has no opposite
## anchors to warn about overriding.
func _fit_to_viewport() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var r: Rect2 = vp.get_visible_rect()
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = r.size
