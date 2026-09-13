class_name EarthDial2D
extends Control

## THE THIRD RING: THE EARTH, WHERE THE APP ITSELF IS A BA-GUA.
##
## The head dial walks the oracle and the body dial walks the machine. Neither
## of them can open a view, toggle a mode or speak to the room, and those acts
## used to live in a row of buttons that said nothing about where they belong.
## Here they are eight stations on a ring drawn in the SAME VOCABULARY as the
## other two -- the same rim, the same sixty-four ticks, the same diamonds --
## so a person learns one shape once and reads three dials with it.
##
## THE HUB IS THE ROOM. The middle draws the figure the room is holding, line
## by line, and the number of phones that voted for it. Tapping the hub is the
## one act that leaves this phone: it broadcasts the head and the body.
##
## TAP ONLY. Eight diamonds and a hub. There is no drag on this ring and never
## was one; the wheel that the other two inherited is not reproduced here.

## The station a finger touched, by index into [constant STATIONS].
signal station_tapped(index: int)

## The middle of the ring: broadcast what this phone is holding.
signal hub_tapped()

## The eight app controls, clockwise from the top, at the Ba-Gua angles the
## body dial already uses. The captions are ASCII: this ring is new, and a
## glyph the phone's font does not carry is a box, not a coin.
const STATIONS: Array[Dictionary] = [
	{"index": 0, "angle": -PI * 0.5, "label": "CAST HEAD"},
	{"index": 1, "angle": -PI * 0.25, "label": "PREV"},
	{"index": 2, "angle": 0.0, "label": "NEXT"},
	{"index": 3, "angle": PI * 0.25, "label": "MODE"},
	{"index": 4, "angle": PI * 0.5, "label": "GEOMETRY"},
	{"index": 5, "angle": PI * 0.75, "label": "TELEMETRY"},
	{"index": 6, "angle": PI, "label": "BRAIN"},
	{"index": 7, "angle": -PI * 0.75, "label": "PERIOD"},
]

## Which station a tap must land within, in pixels. The same reach the machine
## ring gives its diamonds, so the two rings feel the same under a thumb.
const STATION_REACH: float = 34.0

## Where the diamonds sit, and where the ticks begin, as a share of the radius.
## THE CAPTIONS GO INSIDE THE DIAMONDS, not outside: outside is where the
## sixty-four graduations and the rim are, and a word printed across a ruler is
## a word that has taken something else's place.
const STATION_RING: float = 0.74
const TICK_INNER: float = 0.88

## The captions, and the count under the hub's figure. Small, because there
## are nine pieces of text on one small ring and none of them may touch.
const CAPTION_PT: int = 10

## The figure the room is holding, and how many phones stand in it.
var room_bits: int = 0
var peers: int = 0

## The station drawn lit, or -1 for none. The last one touched.
var active_station: int = -1

var dial_center: Vector2 = Vector2.ZERO
var dial_radius: float = 110.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## What the room is holding. Set by the glass from the mesh, never guessed.
func set_room(bits: int, peer_count: int) -> void:
	var b: int = bits & 63
	var p: int = maxi(0, peer_count)
	if b == room_bits and p == peers:
		return
	room_bits = b
	peers = p
	queue_redraw()


## The centre and the radius, worked out from the size the ring was given, so
## that a ring laid out but not yet painted still answers a tap where the
## finger landed rather than at its top-left corner.
func _measure() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.46


## Where a station sits on the glass, for a bubble that wants to point at it.
func station_position(index: int) -> Vector2:
	_measure()
	var st: Dictionary = STATIONS[clampi(index, 0, 7)]
	var ang: float = float(st["angle"])
	return dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * STATION_RING)


func hub_radius() -> float:
	_measure()
	return dial_radius * 0.38


func station_label(index: int) -> String:
	return String(STATIONS[clampi(index, 0, 7)]["label"])


func _draw() -> void:
	dial_center = size * 0.5
	dial_radius = min(size.x, size.y) * 0.46

	# 1. The rim: the earth's own hue over the track the other two share.
	draw_arc(dial_center, dial_radius, 0.0, TAU, 96, Color(1.0, 0.55, 0.15, 0.42), 3.0, true)
	draw_arc(dial_center, dial_radius - 18.0, 0.0, TAU, 96, Color(0.25, 0.75, 0.95, 0.3), 1.5, true)

	# 2. The same sixty-four graduations, so the three rings count alike.
	for i in range(64):
		var ang: float = (float(i) / 64.0) * TAU
		var is_major: bool = (i % 8 == 0)
		var r1: float = dial_radius * TICK_INNER + (0.0 if is_major else 6.0)
		var col: Color = Color(1.0, 0.7, 0.22, 0.9) if is_major else Color(0.3, 0.6, 0.8, 0.45)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dial_center + dir * r1, dial_center + dir * dial_radius,
			col, 2.0 if is_major else 1.0)

	# 3. The eight stations, drawn as the body ring draws its machines.
	var font: Font = get_theme_default_font()
	for station in STATIONS:
		var idx: int = int(station["index"])
		var ang: float = float(station["angle"])
		var pos: Vector2 = dial_center + Vector2(cos(ang), sin(ang)) * (dial_radius * STATION_RING)
		var lit: bool = (idx == active_station)
		var d: float = 10.0 if lit else 6.5
		var pts := PackedVector2Array([
			pos + Vector2(0.0, -d), pos + Vector2(d, 0.0),
			pos + Vector2(0.0, d), pos + Vector2(-d, 0.0),
		])
		if lit:
			draw_colored_polygon(pts, Color(1.0, 0.7, 0.22, 0.95))
		else:
			draw_colored_polygon(pts, Color(0.08, 0.18, 0.28, 0.8))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.2, 0.7, 0.9, 0.6), 1.5)
		if font == null:
			continue
		var text: String = String(station["label"])
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT).x
		var inward: Vector2 = (dial_center - pos).normalized()
		var at: Vector2 = pos + inward * 15.0 + Vector2(-w * 0.5, 4.0)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT,
			Color(0.85, 0.92, 0.98, 0.95) if lit else Color(0.55, 0.68, 0.8, 0.7))

	# 4. The hub: the room's figure, and the count that made it.
	var hub_r: float = hub_radius()
	draw_circle(dial_center, hub_r, Color(0.06, 0.09, 0.14, 0.92))
	draw_arc(dial_center, hub_r, 0.0, TAU, 32, Color(1.0, 0.55, 0.15, 0.75), 2.0, true)

	var line_w: float = hub_r * 1.0
	var line_h: float = 3.0
	var line_gap: float = 5.0
	var start_y: float = dial_center.y + (line_gap * 2.0)
	for line_idx in range(6):
		var y: float = start_y - float(line_idx) * (line_h + line_gap)
		var is_yang: bool = ((room_bits >> line_idx) & 1) == 1
		var col: Color = Color(1.0, 0.62, 0.2) if is_yang else Color(0.7, 0.42, 0.15)
		if is_yang:
			draw_line(Vector2(dial_center.x - line_w * 0.5, y),
				Vector2(dial_center.x + line_w * 0.5, y), col, line_h)
		else:
			var gap: float = line_w * 0.2
			draw_line(Vector2(dial_center.x - line_w * 0.5, y),
				Vector2(dial_center.x - gap * 0.5, y), col, line_h)
			draw_line(Vector2(dial_center.x + gap * 0.5, y),
				Vector2(dial_center.x + line_w * 0.5, y), col, line_h)

	# The count sits UNDER THE FIGURE AND INSIDE THE HUB. Below the hub is
	# where the south-west and south-east captions pass, and a number sharing
	# a line with a word reads as neither.
	if font != null:
		var count: String = "%d in room" % peers
		var cw: float = font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT).x
		draw_string(font, dial_center + Vector2(-cw * 0.5, hub_r * 0.74), count,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_PT, Color(0.7, 0.82, 0.92, 0.85))


## Tap only: the hub, then the eight diamonds, then nothing.
func _gui_input(event: InputEvent) -> void:
	if not _is_release(event):
		return
	_measure()
	var pos: Vector2 = event.position
	if (pos - dial_center).length() < hub_radius():
		hub_tapped.emit()
		accept_event()
		return
	for station in STATIONS:
		var idx: int = int(station["index"])
		if (pos - station_position(idx)).length() < STATION_REACH:
			active_station = idx
			queue_redraw()
			station_tapped.emit(idx)
			accept_event()
			return


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false
