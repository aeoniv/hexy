class_name MandalaDialTap
extends MandalaDial2D

## THE HUMAN REALM DIAL: FULL TOUCH-DRAG ROTATION & SENSORY STATIONS.
##
## The dial spins smoothly under the finger to browse the 64 Huohoutu slots,
## with snapping to ticks on release. The 8 human habit sensor stations show
## real-time vitality arcs. The center hub showcases human consciousness,
## breathing, and focus state with zero hexagram lines.

signal ring_slot_tapped(slot: int)

const RING_INNER: float = 0.82
const DOT_REACH: float = 28.0

var scores: Array = []
var _is_dragging: bool = false
var _touch_down_pos: Vector2 = Vector2.ZERO
var _drag_start_angle: float = 0.0
var _has_moved: bool = false


func _ready() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


func set_scores(row: Array) -> void:
	scores = row
	queue_redraw()


func score_of(trigram: int) -> float:
	var t: int = clampi(trigram, 0, 7)
	return float(scores[t]) if t < scores.size() else 0.0


func hub_radius() -> float:
	_measure()
	return dial_radius * 0.48


func _measure() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.44


func dot_position(station: int) -> Vector2:
	_measure()
	var s: int = clampi(station, 0, 7)
	var ang: float = -TAU * 0.25 + float(s) * (TAU / 8.0)
	return dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * 0.72)


func trigram_position(trigram: int) -> Vector2:
	var seat: int = HUMAN_STATION_TRIGRAMS.find(clampi(trigram, 0, 7))
	return dot_position(maxi(0, seat))


func head_slot() -> int:
	return current_hex_index


func set_head_slot(slot: int) -> void:
	current_hex_index = posmod(slot, HuohoutuData.HEAD_SEQUENCE.size())
	dial_angle = -float(current_hex_index) * (TAU / 64.0)
	target_dial_angle = dial_angle
	queue_redraw()


func set_head_bits(bits: int) -> void:
	var id: int = int(HuohoutuData.get_by_bits(bits & 63).get("id", 1))
	set_head_slot(HuohoutuData.find_head_index_by_id(id))


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


func _gui_input(event: InputEvent) -> void:
	_measure()
	var point: Vector2 = event.position

	if _is_release(event):
		var was_drag: bool = _is_dragging and _has_moved
		_is_dragging = false
		_has_moved = false
		if not was_drag:
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
			if dist >= dial_radius * RING_INNER and dist <= dial_radius * 1.35:
				var slot: int = slot_at(point)
				set_head_slot(slot)
				ring_slot_tapped.emit(slot)
				accept_event()
				return
		else:
			target_dial_angle = -float(current_hex_index) * (TAU / 64.0)
			dial_angle = target_dial_angle
			queue_redraw()
			accept_event()
		return

	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_is_dragging = true
		_touch_down_pos = point
		_has_moved = false
		var dir: Vector2 = point - dial_center
		_drag_start_angle = dir.angle() - dial_angle
		accept_event()
		return

	if (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_dragging:
		if (point - _touch_down_pos).length() > 10.0:
			_has_moved = true
		var dir: Vector2 = point - dial_center
		dial_angle = dir.angle() - _drag_start_angle
		target_dial_angle = dial_angle
		var step_rad := TAU / 64.0
		var new_idx: int = posmod(int(round(-dial_angle / step_rad)), HuohoutuData.HEAD_SEQUENCE.size())
		if new_idx != current_hex_index:
			current_hex_index = new_idx
			ring_slot_tapped.emit(new_idx)
		queue_redraw()
		accept_event()
		return


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false
