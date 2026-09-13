class_name MandalaDialTap
extends MandalaDial2D

## THE OWNER'S HUMAN RING AND ITS CENTRE HUB, WITH THE DRAG TAKEN OUT.
##
## Same bargain as BodyDialTap: the base's drawing is kept whole, the eight
## human scores are drawn on top of it, and the wheel-under-the-finger is gone.
## The hub is the one target that casts, and the two arrows beneath the ring
## are the wheel now -- a visible thing, tapped once.

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
	return dial_radius * 0.48


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


## Tap only: the hub casts, the eight stations speak, the rest is nothing.
func _gui_input(event: InputEvent) -> void:
	if not _is_release(event):
		return
	var v: Vector2 = event.position - dial_center
	var dist: float = v.length()
	if dist < hub_radius():
		center_hub_clicked.emit()
		accept_event()
		return
	if dist <= dial_radius * 1.25:
		var ang: float = fposmod(v.angle() + (TAU * 0.25) + (TAU / 16.0), TAU)
		var idx: int = int(ang / (TAU / 8.0)) % 8
		var tri: int = HUMAN_STATION_TRIGRAMS[idx]
		active_human_trigram = tri
		queue_redraw()
		human_station_clicked.emit(tri)
		accept_event()


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false
