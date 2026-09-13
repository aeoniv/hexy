class_name BodyDialTap
extends BodyDial2D

## THE OWNER'S MACHINE BA-GUA RING, WITH THE DRAG TAKEN OUT.
##
## Everything drawn here is BodyDial2D's own drawing; this subclass adds two
## things and removes one.
##
## ADDED: the eight machine scores, drawn as an arc around each station, so a
## person can see how loudly every machine sense is speaking and not only which
## one won. And the winner ring, which the base already lights, is now told by
## the store instead of by a sensor object of its own.
##
## REMOVED: the drag. The base dial span the 64-figure wheel under a finger,
## which is a hidden gesture -- two fingers' travel decided the figure and
## nothing on the glass said so. On this surface a figure arrives by a TAP on
## the hub or by the senses, and the ring answers taps on its eight stations
## only. The base script is not edited: the old app keeps its drag.

## The eight machine scores, 0..1, indexed by trigram code.
var scores: Array = []


func _ready() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP


## The base lerps its wheel angle every frame toward a drag that can no longer
## happen. Redraw, and leave the angle where it was put.
func _process(_delta: float) -> void:
	queue_redraw()


func set_scores(row: Array) -> void:
	scores = row
	queue_redraw()


func score_of(trigram: int) -> float:
	var t: int = clampi(trigram, 0, 7)
	return float(scores[t]) if t < scores.size() else 0.0


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


## Tap only: the eight stations, and nothing else on the ring.
func _gui_input(event: InputEvent) -> void:
	if not _is_release(event):
		return
	var pos: Vector2 = event.position
	for station in MACHINE_STATIONS:
		var ang: float = float(station["angle"])
		var st: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * 0.78)
		if (pos - st).length() < 34.0:
			machine_station_clicked.emit(int(station["trigram"]))
			accept_event()
			return


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false
