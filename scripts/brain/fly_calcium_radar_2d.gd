class_name FlyCalciumRadar2D
extends Control

## DROSOPHILA CENTRAL COMPLEX (EB/PB) CIRCULAR CALCIUM RADAR
##
## Visualizes the real-time activity bump of the fruit fly's 8-wedge ellipsoid body.
## Mirroring 2-photon GCaMP calcium imaging in neuroscience labs:
##   - 8 Circular wedges mapping to the 8 Bagua trigrams.
##   - Real-time fluorescent glow proportional to wedge activity.
##   - Heading vector pointer (P-EN heading angle).
##   - 6 Neuromodulatory spectrum bars (DA, NPF, OA, dFB, CX, Fru).
##
## THE ROOM LIVES INSIDE THE RING. This is also the swarm radar wmn needs: the
## disc the needle sweeps is the peer field, you at the centre, three rings for
## the three proximity classes the transport can honestly report (touch / room /
## far), one blip per peer the fabric has heard from. Inside and outside share
## ONE frame: the needle is your fly heading, a blip's angle is that peer's fly
## heading (the fact we already hold) until a nav door hands a real bearing in
## through `set_peer_bearings`, at which point the same blip moves to where the
## person actually is and grows a nose. Nothing is invented: a peer with no
## proximity yet parks on the default "room" ring, as the LAN backend rules.

const TRIGRAM_NAMES := ["坤 ☷", "艮 ☶", "坎 ☵", "巽 ☴", "震 ☳", "离 ☲", "兑 ☱", "乾 ☰"]
const NEURO_NAMES := ["DA (Body)", "NPF (Food)", "OA (Breath)", "dFB (Rest)", "CX (Focus)", "Fru (Conn)"]
const NEURO_COLORS := [
	Color(0.95, 0.75, 0.2),  # DA: Gold
	Color(0.3, 0.85, 0.4),   # NPF: Green
	Color(1.0, 0.45, 0.2),   # OA: Orange/Red
	Color(0.4, 0.6, 0.95),   # dFB: Indigo/Blue
	Color(0.2, 0.95, 0.95),  # CX: Cyan
	Color(0.95, 0.35, 0.85)  # Fru: Magenta
]

var central_complex: RefCounted = null
var character: RefCounted = null

## THE STATE DICTIONARY, WHICH IS THE ONLY THING THE GLASS HANDS OVER.
## `set_state` fills these from one `get_fly_state()` call, so the shipping
## surface never reaches into a brain subsystem for a member. When nothing has
## been fed the radar falls back to `central_complex` / `character` exactly as
## it did before, which is how the brain's own scenes still drive it.
var _fed: bool = false
var _heading: float = 0.0
var _coherence: float = 0.0
var _startled: bool = false
var _activity: PackedFloat32Array = PackedFloat32Array()
var _mods: PackedFloat32Array = PackedFloat32Array()
const Identity := preload("res://scripts/social/identity.gd")

## fabric peer id -> their heading in radians. Places the blip until a bearing exists.
var _peers: Dictionary = {}
## fabric peer id -> "touch" / "room" / "far", as the transport reported it.
var _proximity: Dictionary = {}
## fabric peer id -> bearing from us in radians, allocentric. Empty until a
## nav add-on opens the compass door; then it wins over the fly heading.
var _bearings: Dictionary = {}

const CLS_TOUCH := "touch"
const CLS_ROOM := "room"
const CLS_FAR := "far"
const DEFAULT_CLASS := CLS_ROOM
## Ring radius as a fraction of the disc inside the wedge track.
const RING_FRAC := {"touch": 0.30, "room": 0.56, "far": 0.82}
const RING_ORDER: Array[String] = ["touch", "room", "far"]
const PEER_RING_COLOR := Color(0.30, 0.52, 0.48, 0.35)
const BLIP_R_FRAC := 0.075

@export var radar_radius: float = 72.0
@export var ring_thickness: float = 18.0
@export var show_neuromodulators: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(220, 260)


func _ready() -> void:
	custom_minimum_size = Vector2(220, 260)


## ONE DICTIONARY IN, THE WHOLE DIAL OUT. The keys are Character's fixed
## `get_fly_state()` keys and nothing else.
##
## The eight wedges are not in that dictionary -- the character publishes a
## heading and a coherence, not the ellipsoid body's raw calcium -- so the bump
## is rebuilt here: a cosine hill centred on the heading, sharpened by
## coherence, normalised to sum 1. A flat 0.125 ring is exactly what zero
## coherence means, which is the honest picture of a fly that is not oriented.
func set_state(fs: Dictionary) -> void:
	if fs.is_empty():
		return
	_fed = true
	_heading = float(fs.get("heading_rad", 0.0))
	_coherence = clampf(float(fs.get("coherence", 0.0)), 0.0, 1.0)
	_startled = bool(fs.get("is_startled", false))
	_activity = bump_of(_heading, _coherence)
	_mods = PackedFloat32Array([
		float(fs.get("dopamine", 0.0)),
		float(fs.get("serotonin", 0.0)),
		float(fs.get("octopamine", 0.0)),
		float(fs.get("gaba", 0.0)),
		_coherence,
		float(fs.get("acetylcholine", 0.0)),
	])


## The eight-wedge calcium bump for a heading and a coherence. Static and pure,
## so a test can read it without a tree.
static func bump_of(heading: float, coherence: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total: float = 0.0
	var sharp: float = 0.2 + 2.8 * clampf(coherence, 0.0, 1.0)
	for i in range(8):
		var ang: float = float(i) * TAU / 8.0
		var v: float = pow(maxf(0.0, 0.5 + 0.5 * cos(ang - heading)), sharp)
		out.append(v)
		total += v
	if total <= 0.0:
		return PackedFloat32Array([0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125])
	for i in range(8):
		out[i] = out[i] / total
	return out


## The swarm, as MeshFabric.peer_headings keeps it: peer id -> radians.
func set_peer_headings(headings: Dictionary) -> void:
	_peers = headings.duplicate()


func peer_heading_count() -> int:
	return _peers.size()


## fabric peer id -> proximity class, as MeshFabric.peer_proximity_by_src keeps it.
func set_peer_proximity(classes: Dictionary) -> void:
	_proximity = classes.duplicate()


func note_proximity(id: String, cls: String) -> void:
	_proximity[id] = cls if RING_FRAC.has(cls) else DEFAULT_CLASS


## fabric peer id -> allocentric bearing in radians. The nav door's gift.
func set_peer_bearings(bearings: Dictionary) -> void:
	_bearings = bearings.duplicate()


func drop_peer(id: String) -> void:
	_peers.erase(id)
	_proximity.erase(id)
	_bearings.erase(id)


static func ring_frac(cls: String) -> float:
	return float(RING_FRAC.get(cls, RING_FRAC[DEFAULT_CLASS]))


## The disc the peers live in: everything inside the wedge track, minus a gap.
func field_radius() -> float:
	return maxf(8.0, radar_radius - ring_thickness * 0.5 - 6.0)


## WHERE EVERY PEER STANDS, pure of drawing so a test can read it. id ->
## {angle: rad, frac: 0..1 of field_radius, cls, bearing: bool}. A peer known
## only by proximity (no pulse yet) is still plotted, at angle 0 -- silence
## about direction is not a reason to hide a person.
func peer_plots() -> Dictionary:
	var out := {}
	var ids := {}
	for id in _peers:
		ids[id] = true
	for id in _proximity:
		ids[id] = true
	for id in ids:
		var cls: String = String(_proximity.get(id, DEFAULT_CLASS))
		if not RING_FRAC.has(cls):
			cls = DEFAULT_CLASS
		var has_bearing: bool = _bearings.has(id)
		var ang: float = float(_bearings[id]) if has_bearing else float(_peers.get(id, 0.0))
		out[id] = {"angle": fposmod(ang, TAU), "frac": ring_frac(cls), "cls": cls, "bearing": has_bearing}
	return out


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, radar_radius + 18.0)
	var tau_slice: float = TAU / 8.0
	
	# 1. Background ring track
	draw_arc(center, radar_radius, 0.0, TAU, 48, Color(0.12, 0.16, 0.22, 0.8), ring_thickness, true)
	
	# 2. Draw 8 Calcium Activity Wedges
	var activities: Array = [0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125]
	var current_heading: float = 0.0
	if _fed:
		activities = Array(_activity)
		current_heading = _heading
	elif central_complex != null:
		if "activity" in central_complex:
			activities = central_complex.activity
		if "current_heading" in central_complex:
			current_heading = central_complex.current_heading
	
	for i in range(8):
		var start_angle: float = float(i) * tau_slice - (tau_slice * 0.5)
		var end_angle: float = start_angle + tau_slice * 0.92
		var act: float = float(activities[i]) if i < activities.size() else 0.125
		
		# Fluorescent GCaMP Calcium Green/Cyan glow
		var glow_alpha: float = clampf(act * 2.5, 0.15, 1.0)
		var glow_color := Color(0.1, 0.95, 0.7, glow_alpha)
		if act > 0.22:
			glow_color = Color(0.4, 1.0, 0.85, glow_alpha) # Peak excitation
			
		draw_arc(center, radar_radius, start_angle, end_angle, 12, glow_color, ring_thickness * clampf(act * 2.2, 0.7, 1.3), true)
		
		# Trigram label on perimeter
		var label_angle: float = float(i) * tau_slice
		var label_pos: Vector2 = center + Vector2(cos(label_angle), sin(label_angle)) * (radar_radius + ring_thickness * 0.5 + 14.0)
		draw_string(ThemeDB.fallback_font, label_pos + Vector2(-12, 5), TRIGRAM_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.75, 0.82, 0.9, glow_alpha))
	
	# 3b. THE ROOM INSIDE THE RING. Three proximity rings on the disc, and one
	# blip per peer, coloured by the same hue every other surface gives them.
	var fr: float = field_radius()
	for cls in RING_ORDER:
		draw_arc(center, fr * ring_frac(cls), 0.0, TAU, 40, PEER_RING_COLOR, 1.0, true)
	var blip_r: float = maxf(2.5, fr * BLIP_R_FRAC)
	var plots: Dictionary = peer_plots()
	for pid in plots:
		var p: Dictionary = plots[pid]
		var dir := Vector2(cos(float(p["angle"])), sin(float(p["angle"])))
		var at: Vector2 = center + dir * (fr * float(p["frac"]))
		var hue: float = Identity.hue_from_id(String(pid))
		draw_circle(at, blip_r, Identity.body_color(hue))
		draw_arc(at, blip_r, 0.0, TAU, 16, Identity.edge_color(hue), 1.0, true)
		# A blip placed by a real bearing wears a nose; one placed by its own
		# fly heading does not, so the glass never claims a position it lacks.
		if bool(p["bearing"]):
			draw_line(at, at + dir * (blip_r * 1.8), Identity.edge_color(hue), 1.5, true)

	# 3. Inner Heading Cursor Needle
	var needle_dir := Vector2(cos(current_heading), sin(current_heading))
	var needle_end := center + needle_dir * (radar_radius - ring_thickness * 0.6)
	var needle_col := Color(1.0, 0.35, 0.25, 0.95) if _startled else Color(1.0, 0.95, 0.3, 0.95)
	draw_line(center, needle_end, needle_col, 2.5, true)
	draw_circle(center, 4.0, needle_col)
	
	# 4. Neuromodulator Spectrum Gauges
	if show_neuromodulators and _fed:
		_draw_bars(center, Array(_mods))
	elif show_neuromodulators and character != null and "_fullness" in character:
		_draw_bars(center, Array(character._fullness))


## The six bars, wherever the numbers came from.
func _draw_bars(center: Vector2, fullness_arr: Array) -> void:
	var bar_y := center.y + radar_radius + 36.0
	var bar_w := size.x * 0.8
	var bar_x := (size.x - bar_w) * 0.5
	var bar_h := 7.0
	var spacing := 14.0
	for n in range(mini(6, fullness_arr.size())):
		var y: float = bar_y + float(n) * spacing
		var val: float = clampf(float(fullness_arr[n]), 0.0, 1.0)
		
		# Label
		draw_string(ThemeDB.fallback_font, Vector2(bar_x, y - 2), NEURO_NAMES[n], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.72, 0.8))
		# Value text
		draw_string(ThemeDB.fallback_font, Vector2(bar_x + bar_w - 28, y - 2), "%d%%" % int(val * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(0.85, 0.9, 0.95))
		
		# Bar track
		draw_rect(Rect2(bar_x, y, bar_w, bar_h), Color(0.12, 0.15, 0.20, 0.9), true)
		# Fill
		var fill_color: Color = NEURO_COLORS[n]
		if val < 0.5:
			fill_color = fill_color.lerp(Color(0.4, 0.4, 0.4), 0.5)
		draw_rect(Rect2(bar_x, y, bar_w * val, bar_h), fill_color, true)
