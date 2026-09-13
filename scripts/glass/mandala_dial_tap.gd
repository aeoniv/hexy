class_name MandalaDialTap
extends MandalaDial2D

## THE OWNER'S HUMAN RING AND ITS CENTRE HUB, WITH THE DRAG TAKEN OUT.
##
## Same bargain as BodyDialTap: the base's drawing is kept whole, the eight
## human scores are drawn on top of it, and the wheel-under-the-finger is gone.
## The hub is the one target that casts, and the two arrows beneath the ring
## are the wheel now -- a visible thing, tapped once.
##
## THE RING IS THE WHEEL NOW. The drag that spun sixty-four figures under a
## finger is gone, but the sixty-four ticks it spun are still drawn, and a tick
## a person can see is a tick a person may touch: a tap on the ring walks the
## HEAD to the slot nearest the finger and says so through
## [signal ring_slot_tapped]. One visible target, one figure, no hidden travel.

## A tap on the outer ring, as a slot 0..63 of HuohoutuData.HEAD_SEQUENCE.
signal ring_slot_tapped(slot: int)

## How close to the rim a tap must land to be the ring rather than a dot.
const RING_INNER: float = 0.86

## How close to a human dot a tap must land to be that dot, in pixels.
const DOT_REACH: float = 28.0

## The eight human scores, 0..1, indexed by trigram code.
var scores: Array = []


func _ready() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_scores(row: Array) -> void:
	scores = row
	queue_redraw()


func score_of(trigram: int) -> float:
	var t: int = clampi(trigram, 0, 7)
	return float(scores[t]) if t < scores.size() else 0.0


func hub_radius() -> float:
	_measure()
	return dial_radius * 0.48


## The centre and the radius, worked out from the size the ring was given.
## The base only sets these while DRAWING, so a ring that has been laid out but
## not yet painted answers every tap at the top-left corner. A finger does not
## wait for a frame; neither does this.
func _measure() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.44


## Where a human dot sits on the glass, for a bubble that points at it.
func dot_position(station: int) -> Vector2:
	_measure()
	var s: int = clampi(station, 0, 7)
	var ang: float = -TAU * 0.25 + float(s) * (TAU / 8.0)
	return dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * 0.72)


## Where the dot of a given trigram sits, by trigram code rather than seat.
func trigram_position(trigram: int) -> Vector2:
	var seat: int = HUMAN_STATION_TRIGRAMS.find(clampi(trigram, 0, 7))
	return dot_position(maxi(0, seat))


## The head slot this ring is showing, 0..63.
func head_slot() -> int:
	return current_hex_index


## Walk the ring to a slot of HuohoutuData.HEAD_SEQUENCE. The ticks turn with
## it, so the figure in the hub and the graduation at the pointer agree.
func set_head_slot(slot: int) -> void:
	current_hex_index = posmod(slot, HuohoutuData.HEAD_SEQUENCE.size())
	dial_angle = -float(current_hex_index) * (TAU / 64.0)
	target_dial_angle = dial_angle
	queue_redraw()


## The same walk, said in bits, which is how the store says it.
func set_head_bits(bits: int) -> void:
	var id: int = int(HuohoutuData.get_by_bits(bits & 63).get("id", 1))
	set_head_slot(HuohoutuData.find_head_index_by_id(id))


## The slot whose graduation lies under a point, 0..63.
func slot_at(point: Vector2) -> int:
	var ang: float = (point - dial_center).angle()
	var step: float = TAU / 64.0
	return posmod(int(round((ang - dial_angle) / step)), 64)


func _draw() -> void:
	super()
	if scores.is_empty():
		return
	for s in range(8):
		var tri: int = HUMAN_STATION_TRIGRAMS[s]
		var ang: float = -TAU * 0.25 + float(s) * (TAU / 8.0)
		var pos: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * 0.72)
		var v: float = clampf(score_of(tri), 0.0, 1.0)
		var r: float = 13.0
		draw_arc(pos, r, 0.0, TAU, 24, Color(0.45, 0.5, 0.6, 0.35), 1.5, true)
		if v > 0.0:
			var a: float = -PI * 0.5
			draw_arc(pos, r, a, a + TAU * v, 24, Color(0.35, 0.85, 1.0, 0.9), 3.0, true)


## Tap only, and three targets in order of how small they are: the hub, then
## the eight dots, then the ring. The smallest thing a finger could have meant
## is asked first, so a dot never loses its tap to the ring behind it.
func _gui_input(event: InputEvent) -> void:
	if not _is_release(event):
		return
	_measure()
	var point: Vector2 = event.position
	var v: Vector2 = point - dial_center
	var dist: float = v.length()
	if dist < hub_radius():
		center_hub_clicked.emit()
		accept_event()
		return
	for seat in range(8):
		if (point - dot_position(seat)).length() < DOT_REACH:
			var tri: int = HUMAN_STATION_TRIGRAMS[seat]
			active_human_trigram = tri
			queue_redraw()
			human_station_clicked.emit(tri)
			accept_event()
			return
	if dist >= dial_radius * RING_INNER and dist <= dial_radius * 1.25:
		ring_slot_tapped.emit(slot_at(point))
		accept_event()


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false
