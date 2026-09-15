class_name EarthLinesDial
extends Control

## THE EARTH DIAL: Six Yin/Yang lines arranged in divisions around the central Hypergram.
##
## Surrounds the central 4096-state Hypergram with a circle divided into six
## equal sectors (divisions), each displaying that line's Yin/Yang state
## (solid arc for Yang, broken arc for Yin), its change status (opens/closes/same),
## and responsive touch targets for line flipping.

signal line_tapped(line: int)
signal hub_tapped()

const LINE_NAMES: Array[String] = ["Body", "Food", "Breath", "Rest", "Focus", "Connection"]

const SAME: String = "same"
const OPENS: String = "opens"
const CLOSES: String = "closes"

## Division geometry: 6 sectors spanning TAU (60 degrees each).
## Line 0 sits at the bottom (PI * 0.5), lines 1..5 rise up the right and descend the left.
const SECTOR_SPAN: float = TAU / 6.0
const ANGLE_BASE: float = PI * 0.5

const RING: float = 0.84
const HUB: float = 0.48

const COL_RIM: Color = Color(1.0, 0.55, 0.15, 0.40)
const COL_DIVIDER: Color = Color(0.28, 0.65, 0.85, 0.35)
const COL_DIM_YANG: Color = Color(1.0, 0.82, 0.35, 0.70)
const COL_DIM_YIN: Color = Color(0.35, 0.75, 0.95, 0.65)
const COL_OPENS: Color = Color(1.0, 0.85, 0.30, 0.98)
const COL_CLOSES: Color = Color(0.35, 0.85, 1.0, 0.98)

var body_bits: int = 0
var head_bits: int = 0
var active_line: int = -1

var dial_center: Vector2 = Vector2.ZERO
var dial_radius: float = 110.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_figures(body_in: int, head_in: int) -> void:
	var b: int = body_in & 63
	var h: int = head_in & 63
	if b == body_bits and h == head_bits:
		return
	body_bits = b
	head_bits = h
	queue_redraw()


func line_state(i: int) -> String:
	var b: int = (body_bits >> clampi(i, 0, 5)) & 1
	var h: int = (head_bits >> clampi(i, 0, 5)) & 1
	if b == h:
		return SAME
	return OPENS if h == 1 else CLOSES


func bits_if_tapped(i: int) -> int:
	return (body_bits ^ (1 << clampi(i, 0, 5))) & 63


func line_name(i: int) -> String:
	return LINE_NAMES[clampi(i, 0, 5)]


func _measure() -> void:
	dial_center = size * 0.5
	dial_radius = minf(size.x, size.y) * 0.46


func hub_radius() -> float:
	_measure()
	return dial_radius * HUB


## Center angle of division `i` (0 at bottom, 1..5 wrapping around).
func line_angle(i: int) -> float:
	return ANGLE_BASE - float(clampi(i, 0, 5)) * SECTOR_SPAN


## Where line `i` sits on the rim, in this dial's own pixels.
func line_position(i: int) -> Vector2:
	_measure()
	var ang: float = line_angle(i)
	return dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * RING)


## The line division nearest a point, or -1 when inside the hub or outside the dial.
func line_at(point: Vector2) -> int:
	_measure()
	var offset: Vector2 = point - dial_center
	var dist: float = offset.length()
	if dist < hub_radius() or dist > dial_radius * 1.18:
		return -1
	# Map angle to division index 0..5
	var raw_ang: float = offset.angle()
	# Relative to bottom (PI * 0.5), rotated counter-clockwise:
	var diff: float = fposmod(ANGLE_BASE + (SECTOR_SPAN * 0.5) - raw_ang, TAU)
	var idx: int = int(diff / SECTOR_SPAN) % 6
	return clampi(idx, 0, 5)


func _draw() -> void:
	_measure()
	var hub_r: float = hub_radius()
	var arc_r: float = dial_radius * RING

	# Outer decorative rim
	draw_arc(dial_center, dial_radius, 0.0, TAU, 96, COL_RIM, 2.5, true)
	draw_arc(dial_center, dial_radius - 6.0, 0.0, TAU, 96, Color(0.20, 0.60, 0.85, 0.25), 1.0, true)

	# Radial division tick marks between the 6 sectors
	for s in range(6):
		var div_ang: float = ANGLE_BASE + (SECTOR_SPAN * 0.5) - float(s) * SECTOR_SPAN
		var dir := Vector2(cos(div_ang), sin(div_ang))
		draw_line(dial_center + dir * (hub_r + 4.0), dial_center + dir * (dial_radius - 2.0), COL_DIVIDER, 1.5)

	# Draw the 6 Yin/Yang Lines in their respective divisions around the circle
	var sector_arc_span: float = SECTOR_SPAN * 0.76
	var half_span: float = sector_arc_span * 0.5
	var gap_span: float = sector_arc_span * 0.24

	for i in range(6):
		var ang: float = line_angle(i)
		var state: String = line_state(i)
		var lit: bool = (state != SAME) or (i == active_line)
		var b_bit: int = (body_bits >> i) & 1
		var h_bit: int = (head_bits >> i) & 1
		var whole: bool = state == OPENS or (state == SAME and b_bit == 1)

		var col: Color = COL_DIM_YIN
		if state == OPENS:
			col = COL_OPENS
		elif state == CLOSES:
			col = COL_CLOSES
		elif whole:
			col = COL_DIM_YANG

		var stroke_w: float = 6.0 if not lit else 8.0

		if whole:
			# Yang: Solid curved arc across division
			if lit:
				draw_arc(dial_center, arc_r, ang - half_span, ang + half_span, 20, Color(col.r, col.g, col.b, 0.30), stroke_w + 5.0, true)
			draw_arc(dial_center, arc_r, ang - half_span, ang + half_span, 20, col, stroke_w, true)
		else:
			# Yin: Broken curved arc with central angular gap in the division
			var seg_half_gap: float = gap_span * 0.5
			if lit:
				draw_arc(dial_center, arc_r, ang - half_span, ang - seg_half_gap, 10, Color(col.r, col.g, col.b, 0.30), stroke_w + 5.0, true)
				draw_arc(dial_center, arc_r, ang + seg_half_gap, ang + half_span, 10, Color(col.r, col.g, col.b, 0.30), stroke_w + 5.0, true)
			draw_arc(dial_center, arc_r, ang - half_span, ang - seg_half_gap, 10, col, stroke_w, true)
			draw_arc(dial_center, arc_r, ang + seg_half_gap, ang + half_span, 10, col, stroke_w, true)

		# Moving Line Radiant Center Indicator
		if b_bit != h_bit:
			var pip_pos: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * arc_r
			var pip_col: Color = Color(1.0, 0.95, 0.45, 1.0) if b_bit == 1 else Color(0.35, 0.95, 1.0, 1.0)
			draw_circle(pip_pos, 4.0, pip_col)
			draw_circle(pip_pos, 7.0, Color(pip_col.r, pip_col.g, pip_col.b, 0.35))

	# Center Hub: MAXIMIZED HYPERGRAM SYMBOL ONLY (No small unreadable titles)
	draw_circle(dial_center, hub_r, Color(0.05, 0.08, 0.13, 0.96))
	draw_arc(dial_center, hub_r, 0.0, TAU, 48, Color(1.0, 0.65, 0.18, 0.95), 2.5, true)
	draw_arc(dial_center, hub_r - 3.5, 0.0, TAU, 48, Color(0.25, 0.75, 0.95, 0.35), 1.0, true)

	# 6 Hypergram Lines in Hub (Maximized, line 0 bottom to line 5 top)
	var hlw: float = hub_r * 1.30
	var line_thickness: float = 4.2
	var line_spacing: float = 8.0
	for i in range(6):
		var ly: float = dial_center.y + float(2.5 - float(i)) * line_spacing
		var b_bit: int = (body_bits >> i) & 1
		var h_bit: int = (head_bits >> i) & 1

		if b_bit == 1 and h_bit == 1:
			# Young Yang (Firm Steady Yang)
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(1.0, 0.85, 0.35, 0.95), line_thickness)
		elif b_bit == 0 and h_bit == 0:
			# Young Yin (Firm Steady Yin)
			var half: float = (hlw - 9.0) * 0.5
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x - hlw * 0.5 + half, ly), Color(0.30, 0.75, 0.95, 0.88), line_thickness)
			draw_line(Vector2(dial_center.x + hlw * 0.5 - half, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(0.30, 0.75, 0.95, 0.88), line_thickness)
		elif b_bit == 1 and h_bit == 0:
			# Old Yang (Moving Yang -> Yin)
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(1.0, 0.55, 0.20, 0.98), line_thickness)
			draw_circle(Vector2(dial_center.x, ly), 3.2, Color(1.0, 0.92, 0.45, 0.98))
		else:
			# Old Yin (Moving Yin -> Yang)
			var half: float = (hlw - 9.0) * 0.5
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x - hlw * 0.5 + half, ly), Color(0.35, 0.92, 1.0, 0.98), line_thickness)
			draw_line(Vector2(dial_center.x + hlw * 0.5 - half, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(0.35, 0.92, 1.0, 0.98), line_thickness)
			draw_circle(Vector2(dial_center.x, ly), 3.0, Color(1.0, 0.85, 0.25, 0.98))


func _gui_input(event: InputEvent) -> void:
	if not GlassBubble._is_release(event):
		return
	_measure()
	var at: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		at = (event as InputEventScreenTouch).position
	else:
		return
	tap_at(at)
	accept_event()


func tap_at(at: Vector2) -> void:
	_measure()
	if (at - dial_center).length() < hub_radius():
		hub_tapped.emit()
		Input.vibrate_handheld(30)
		return
	var i: int = line_at(at)
	if i < 0:
		return
	active_line = i
	queue_redraw()
	line_tapped.emit(i)
	Input.vibrate_handheld(20)
