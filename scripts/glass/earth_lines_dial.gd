class_name EarthLinesDial
extends Control

## THE EARTH BAND AS SIX LINES, not twelve buttons.
##
## The twelve stations were the app's own chrome wearing a dial's clothes: a
## person looking at them learned what the app could do, never what their own
## day was doing. This dial draws the ONE thing the earth band is actually for
## -- the six lines of the body, and for each of them whether the head is
## asking it to OPEN, to CLOSE, or to stay where it is.
##
## LINE 1 IS AT THE BOTTOM AND LINE 6 IS AT THE TOP, the way a hexagram is read
## and the way a body is built: "Body" under the feet, "Connection" over the
## head. The six climb the right of the ring in five even steps, so the stack a
## person knows from the hub of every other dial here is simply lifted onto a
## rim where a finger can reach one line at a time.
##
## THE DIAL DECIDES NOTHING. A tap says which line was touched and the glass
## announces it on the seat bus; the hub says a cast was asked for. Nothing here
## writes a figure, and nothing here reads a store.

## A line of the ring was touched, 0..5 with 0 the bottom line.
signal line_tapped(i: int)
## The middle was touched: throw the coins.
signal hub_tapped()

## The six names, in Pacing's own spelling. Carried rather than imported so the
## dial draws the same words headless as it does on a phone.
const LINE_NAMES: Array[String] = ["Body", "Food", "Breath", "Rest", "Focus", "Connection"]

## The three things a line can be doing, as words, so a test may read them.
const SAME: String = "same"
const OPENS: String = "opens"
const CLOSES: String = "closes"

## Where the six sit: line 0 at the bottom of the ring, line 5 at the top, five
## even steps up the right-hand side. Screen angles, so +y is down.
const ANGLE_BOTTOM: float = PI * 0.5
const ANGLE_STEP: float = PI / 5.0

## How near a finger has to land, in pixels, to have touched a line.
const LINE_REACH: float = 44.0

## The rim, the glyph and the hub, as shares of the dial's own radius.
const RING: float = 0.86
const HUB: float = 0.52
const GLYPH_W: float = 44.0
const GLYPH_H: float = 4.0
const CAPTION_PT: int = 9

const COL_RIM: Color = Color(1.0, 0.55, 0.15, 0.45)
const COL_INNER: Color = Color(0.25, 0.75, 0.95, 0.3)
const COL_DIM: Color = Color(0.32, 0.45, 0.58, 0.55)
const COL_OPENS: Color = Color(1.0, 0.82, 0.30, 0.98)
const COL_CLOSES: Color = Color(0.35, 0.80, 1.0, 0.98)
const COL_TEXT: Color = Color(0.72, 0.82, 0.92, 0.85)
const COL_TEXT_LIT: Color = Color(0.94, 0.97, 1.0, 0.98)

## The two figures this dial compares. The body is what stands; the head is what
## is being asked for.
var body_bits: int = 0
var head_bits: int = 0

## The line the finger last chose, or -1. Drawn a little larger, nothing more.
var active_line: int = -1

var dial_center: Vector2 = Vector2.ZERO
var dial_radius: float = 110.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## The pair, set together, because a line's state is only ever the difference
## between them.
func set_figures(body_in: int, head_in: int) -> void:
	var b: int = body_in & 63
	var h: int = head_in & 63
	if b == body_bits and h == head_bits:
		return
	body_bits = b
	head_bits = h
	queue_redraw()


## What line `i` is doing, as one of SAME, OPENS or CLOSES.
func line_state(i: int) -> String:
	var b: int = (body_bits >> clampi(i, 0, 5)) & 1
	var h: int = (head_bits >> clampi(i, 0, 5)) & 1
	if b == h:
		return SAME
	return OPENS if h == 1 else CLOSES


## The figure a tap on line `i` would land: the body with that one line turned.
func bits_if_tapped(i: int) -> int:
	return (body_bits ^ (1 << clampi(i, 0, 5))) & 63


func line_name(i: int) -> String:
	return LINE_NAMES[clampi(i, 0, 5)]


func _measure() -> void:
	dial_center = size * 0.5
	dial_radius = minf(size.x, size.y) * 0.46


## Where line `i` sits on the rim, in this dial's own pixels.
func line_position(i: int) -> Vector2:
	_measure()
	var ang: float = ANGLE_BOTTOM - float(clampi(i, 0, 5)) * ANGLE_STEP
	return dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * RING)


func hub_radius() -> float:
	_measure()
	return dial_radius * HUB


## The line nearest a point, or -1 when the finger was nowhere near one.
func line_at(point: Vector2) -> int:
	_measure()
	var best: int = -1
	var best_d: float = LINE_REACH
	for i in range(6):
		var d: float = (point - line_position(i)).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func _draw() -> void:
	_measure()
	draw_arc(dial_center, dial_radius, 0.0, TAU, 96, COL_RIM, 3.0, true)
	draw_arc(dial_center, dial_radius - 18.0, 0.0, TAU, 96, COL_INNER, 1.5, true)

	var font: Font = get_theme_default_font()
	for i in range(6):
		var at: Vector2 = line_position(i)
		var state: String = line_state(i)
		var lit: bool = state != SAME
		var col: Color = COL_DIM
		if state == OPENS:
			col = COL_OPENS
		elif state == CLOSES:
			col = COL_CLOSES
		var w: float = GLYPH_W * (1.15 if i == active_line else 1.0)
		var h: float = GLYPH_H * (1.4 if lit else 1.0)
		## THE GLYPH IS THE ANSWER: a line that opens is drawn whole, a line
		## that closes is drawn broken, and a line with nothing to say is drawn
		## as it already stands in the body.
		var whole: bool = state == OPENS or (state == SAME and ((body_bits >> i) & 1) == 1)
		if whole:
			draw_line(at - Vector2(w * 0.5, 0.0), at + Vector2(w * 0.5, 0.0), col, h)
		else:
			var gap: float = w * 0.24
			draw_line(at - Vector2(w * 0.5, 0.0), at - Vector2(gap * 0.5, 0.0), col, h)
			draw_line(at + Vector2(gap * 0.5, 0.0), at + Vector2(w * 0.5, 0.0), col, h)
		if font == null:
			continue
		var text: String = "%d %s" % [i + 1, LINE_NAMES[i]]
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT).x
		var inward: Vector2 = (dial_center - at).normalized()
		draw_string(font, at + inward * 16.0 + Vector2(-tw * 0.5, 4.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT,
			COL_TEXT_LIT if lit else COL_TEXT)

	var hub_r: float = hub_radius()
	draw_circle(dial_center, hub_r, Color(0.05, 0.08, 0.13, 0.96))
	draw_arc(dial_center, hub_r, 0.0, TAU, 48, Color(1.0, 0.65, 0.18, 0.95), 2.5, true)
	draw_arc(dial_center, hub_r - 3.0, 0.0, TAU, 48, Color(0.25, 0.75, 0.95, 0.35), 1.0, true)

	# 4096 HYPERGRAM (64 HEAD x 64 BODY)
	var hypergram_idx: int = ((head_bits & 63) << 6) | (body_bits & 63)

	if font != null:
		var hyp_hdr: String = "HYPERGRAM #%d / 4096" % (hypergram_idx + 1)
		var hw: float = font.get_string_size(hyp_hdr, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
		draw_string(font, dial_center + Vector2(-hw * 0.5, -hub_r * 0.54), hyp_hdr,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.78, 0.35, 0.95))

	# Draw the 6 Hypergram Lines in the Center Hub (line 0 at bottom to line 5 at top)
	var hlw: float = 38.0
	for i in range(6):
		var ly: float = dial_center.y + float(2.5 - float(i)) * 8.0 - 2.0
		var b_bit: int = (body_bits >> i) & 1
		var h_bit: int = (head_bits >> i) & 1
		
		if b_bit == 1 and h_bit == 1:
			# Young Yang (Firm Steady Yang)
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(1.0, 0.85, 0.35, 0.92), 2.2)
		elif b_bit == 0 and h_bit == 0:
			# Young Yin (Firm Steady Yin)
			var half: float = (hlw - 7.0) * 0.5
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x - hlw * 0.5 + half, ly), Color(0.28, 0.68, 0.88, 0.82), 2.2)
			draw_line(Vector2(dial_center.x + hlw * 0.5 - half, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(0.28, 0.68, 0.88, 0.82), 2.2)
		elif b_bit == 1 and h_bit == 0:
			# Old Yang (Moving Yang -> Yin)
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(1.0, 0.52, 0.18, 0.98), 2.4)
			draw_circle(Vector2(dial_center.x, ly), 2.8, Color(1.0, 0.92, 0.45, 0.98))
		else:
			# Old Yin (Moving Yin -> Yang)
			var half: float = (hlw - 7.0) * 0.5
			draw_line(Vector2(dial_center.x - hlw * 0.5, ly), Vector2(dial_center.x - hlw * 0.5 + half, ly), Color(0.35, 0.92, 1.0, 0.98), 2.4)
			draw_line(Vector2(dial_center.x + hlw * 0.5 - half, ly), Vector2(dial_center.x + hlw * 0.5, ly), Color(0.35, 0.92, 1.0, 0.98), 2.4)
			draw_circle(Vector2(dial_center.x, ly), 2.5, Color(1.0, 0.85, 0.25, 0.98))

	if font != null:
		var cast_txt: String = "[ CAST ]"
		var cw: float = font.get_string_size(cast_txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
		draw_string(font, dial_center + Vector2(-cw * 0.5, hub_r * 0.65), cast_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(1.0, 0.82, 0.32, 0.95))


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


## The tap, separated from the event so a headless test may reach it without
## building an InputEvent for a Control that is never in a viewport.
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
