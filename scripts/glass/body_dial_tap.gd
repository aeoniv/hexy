class_name BodyDialTap
extends BodyDial2D

## THE MACHINE REALM DIAL: FULL TOUCH-DRAG ORBIT & SENSOR INTERACTIONS.
##
## Dragging around the dial orbits the 3D creature and rotates the machine dial.
## Tapping the 8 machine diamond stations opens telemetry and triggers sensor pulses.
## Tapping the central 3D creature fetches full machine physical status.

signal dial_dragged(delta_angle: float)
signal center_clicked()

## The eight machine scores, 0..1, indexed by trigram code.
var scores: Array = []

var _is_dragging: bool = false
var _touch_down_pos: Vector2 = Vector2.ZERO
var _touch_down_time: int = 0
var _prev_angle: float = 0.0
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


func _measure() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.46


func station_position(trigram: int) -> Vector2:
	_measure()
	for station in MACHINE_STATIONS:
		if int(station["trigram"]) == clampi(trigram, 0, 7):
			var ang: float = float(station["angle"])
			return dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * 0.78)
	return dial_center


func body_slot() -> int:
	return current_hex_index


func set_body_slot(slot: int) -> void:
	current_hex_index = posmod(slot, HuohoutuData.BODY_SEQUENCE.size())
	current_hex_id = HuohoutuData.BODY_SEQUENCE[current_hex_index]
	dial_angle = -float(current_hex_index) * (TAU / 64.0)
	target_dial_angle = dial_angle
	queue_redraw()


func set_body_bits(bits: int) -> void:
	var id: int = int(HuohoutuData.get_by_bits(bits & 63).get("id", 1))
	set_body_slot(HuohoutuData.find_body_index_by_id(id))


func _draw() -> void:
	super()
	if scores.is_empty():
		return
	for station in MACHINE_STATIONS:
		var tri: int = int(station["trigram"])
		var ang: float = float(station["angle"])
		var pos: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * 0.78)
		var s: float = clampf(score_of(tri), 0.0, 1.0)
		var r: float = 17.0
		draw_arc(pos, r, 0.0, TAU, 24, Color(0.45, 0.5, 0.6, 0.35), 1.5, true)
		if s > 0.0:
			var a: float = -PI * 0.5
			draw_arc(pos, r, a, a + TAU * s, 24, Color(1.0, 0.78, 0.22, 0.9), 3.0, true)


func _gui_input(event: InputEvent) -> void:
	_measure()
	var is_press: bool = false
	var is_release: bool = false
	var is_move: bool = false
	var ev_pos: Vector2 = event.position

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		ev_pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenTouch:
		ev_pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		ev_pos = event.position
		is_move = true

	if is_press:
		_is_dragging = true
		_touch_down_pos = ev_pos
		_touch_down_time = int(Time.get_ticks_msec())
		_has_moved = false
		_prev_angle = (ev_pos - dial_center).angle()
		accept_event()
		return

	if is_move and _is_dragging:
		if (ev_pos - _touch_down_pos).length() > 10.0:
			_has_moved = true
		var cur_angle: float = (ev_pos - dial_center).angle()
		var delta_ang: float = wrapf(cur_angle - _prev_angle, -PI, PI)
		_prev_angle = cur_angle
		dial_angle += delta_ang
		target_dial_angle = dial_angle
		dial_dragged.emit(delta_ang)
		queue_redraw()
		accept_event()
		return

	if is_release:
		var was_drag: bool = _is_dragging and _has_moved
		_is_dragging = false
		_has_moved = false
		if was_drag:
			accept_event()
			return

		# Tap detection
		var dist: float = (ev_pos - dial_center).length()

		# A. Check 8 Machine Diamond Stations
		var closest_tri: int = -1
		var closest_dist: float = 9999.0
		for station in MACHINE_STATIONS:
			var tri: int = int(station["trigram"])
			var ang: float = float(station["angle"])
			var st: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * 0.78)
			var d: float = (ev_pos - st).length()
			if d < closest_dist:
				closest_dist = d
				closest_tri = tri

		if closest_tri != -1 and closest_dist < 46.0:
			active_machine_trigram = closest_tri
			machine_station_clicked.emit(closest_tri)
			Input.vibrate_handheld(25)
			queue_redraw()
			accept_event()
			return

		# B. Center 3D Creature Tap
		if dist < dial_radius * 0.56:
			center_clicked.emit()
			Input.vibrate_handheld(30)
			accept_event()
			return

		accept_event()
