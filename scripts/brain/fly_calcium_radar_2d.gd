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

# -- THE COMPASS, WHICH IS GODOT'S OWN AND NOBODY'S PLUGIN ---------------------
# `Heading` (scripts/core/heading.gd) reads Input.get_magnetometer() and
# Input.get_gravity() and publishes an azimuth. When it is live AND the derived
# accuracy is one we may believe, THE WHOLE PEER FIELD TURNS so that screen-up
# is the way the phone is facing: turn on the spot and the peers sweep round
# the disc until the one you want is at the top and you can walk at them.
#
# RULE 1, PORTED VERBATIM FROM THE ORIGIN DIAL: YOUR OWN HEADING IS NEVER AN
# OBJECT ON THIS SCREEN. No cone thrown from the centre, no rim marker, no big
# degrees, no nose on your own body. Every one of those swept across the glass
# as the phone turned, which is precisely the motion the dial exists to stop.
# The heading is READ, and it decides where the others sit. What moves is the
# other people. Nothing else. (The calcium needle is not an exception: it is the
# FLY's heading -- a fact about the organism in the allocentric frame the eight
# wedges live in -- and it is drawn in that frame, not in the compass one.)
#
# AND THE ROTATION IS CONDITIONAL. A magnetometer that has been near a laptop, a
# speaker or a car dashboard is not broken, it is uncalibrated. At LOW or
# UNRELIABLE this dial stops rotating anything, suppresses the guidance arrow,
# and says one short line about what to do instead of turning confidently from a
# reading nothing stands behind.

## The hint, when the compass cannot be believed. A figure-8 is the gesture
## Android's own calibration prompt asks for, so it is the one worth naming.
const UNRELIABLE_HINT := "compass unreliable — wave the phone in a figure-8"
## Close enough to "you are pointing at them" that a number would be noise. A
## person cannot hold a phone steadier than this while walking anyway.
const ON_TARGET_DEG := 12.0

# -- log distance, when there are metres to be log of --------------------------
# Rings at 10 m / 100 m / 1 km. The interesting range spans three decades and a
# linear dial spends all of its pixels on the far half. These are used ONLY for
# a peer whose distance in metres somebody has actually handed in through
# `set_peer_distances_m`; a peer known only by proximity class keeps the three
# coarse rings above, because touch/room/far is the honest granularity the LAN
# transport can report and dressing it up as metres would be a lie.
const RING_M: Array[float] = [10.0, 100.0, 1000.0]
const RING_LABELS: Array[String] = ["10 m", "100 m", "1 km"]
const RING_DECADES := 3.0
## Where 1 m sits: the innermost usable radius, as a fraction of the field.
const HUB_FRAC := 0.34

## Half the radial thickness of a trust band, as a fraction of the field. A band
## is drawn ALONG THE PEER'S OWN RING -- never as a wedge from the centre, see
## rule 1 -- so it is thin next to the gap between two rings.
const BAND_HALF_FRAC := 0.045
const BAND_COLOR := Color(0.55, 0.78, 0.72, 0.30)
const GUIDE_COLOR := Color(0.98, 0.78, 0.32)
const DIM_COLOR := Color(0.62, 0.70, 0.68)
## HOW CLOSE TWO BODIES MUST BE IN THE DAY TO BE CALLED SAME-PHASE. 0.08 of a
## day is a shade under two hours, measured the short way round the circle --
## close enough that two people are awake, or tired, together, and loose enough
## that a clock nobody set to the minute still finds its company.
const IN_PHASE_FRAC := 0.08
## The second ring an in-phase blip wears, as a multiple of the blip radius.
const PHASE_RING_MUL := 1.45
const PHASE_RING_COLOR := Color(0.62, 0.88, 0.95, 0.75)
## The tick a mentor wears, pointing up: one chapter ahead is up the page.
const MENTOR_TICK_MUL := 2.2
const MENTOR_COLOR := Color(0.98, 0.86, 0.45, 0.9)

## Tap radius as a fraction of the field. A blip with a reach twice its own
## radius is a touch target a thumb can actually hit.
const BLIP_HIT_FRAC := 0.16

## fabric peer id -> distance in metres. Empty in base: nothing here asks the
## platform where anybody is. A nav add-on that learns two positions calls
## Geo.distance_m itself and hands the answer in, and only then does that peer
## move onto the log rings.
var _distances: Dictionary = {}
## fabric peer id -> half-angle of how much that bearing can be believed, in
## degrees. Also the nav door's gift (Geo.bearing_spread_deg). Without one the
## radar falls back to the honest default in `peer_plots`.
var _spreads: Dictionary = {}

## fabric peer id -> where in their own day they are, 0..1, exactly as
## MeshFabric.peer_phase_by_src keeps it. Empty in base: this dial estimates no
## circadian phase of its own and a peer who never said stays unsaid.
var _phases: Dictionary = {}
## fabric peer id -> which chapter of the journey they are in.
var _stages: Dictionary = {}
## This body's own place in the day and the story. -1 for either means the
## comparison cannot be made at all, and every flag below stays false rather
## than defaulting to "everybody matches".
var _own_phase: float = -1.0
var _own_stage: int = -1

## The compass, exactly as `Heading` publishes it. Defaults are the headless
## truth: nothing is live, nothing has been seen, and the dial is the
## allocentric disc it has always been.
var _heading_rad: float = 0.0
var _heading_accuracy: int = Geo.ACC_UNKNOWN
var _heading_pose: String = Geo.POSE_FLAT
var _heading_live: bool = false
var _heading_seen: bool = false
var _true_north: bool = false
var _declination: float = 0.0

## The peer the guidance arrow is pointing at, or "". One tap in, same tap out.
var guide_id: String = ""
## Where each blip was last drawn, so what you see is what you can hit.
var _blips: Dictionary = {}

@export var radar_radius: float = 72.0
@export var ring_thickness: float = 18.0
@export var show_neuromodulators: bool = true

## QUIET MODE: the same instance parked on the front glass as "the room", the
## creature standing in `hub_rect()`. No wedges, no neuromod bars, the ring
## track thinned to a single faint arc, peer rings dimmed -- but the needle,
## the north caption, the blips, the in-phase ring, the mentor tick and the
## guide line all stay, because those are the room, not the instrument panel.
var quiet: bool = false
## Independent of `quiet` so a caller can mix (e.g. wedges off, bars on).
## `set_quiet` drives both together; toggling one directly is also honest.
var show_wedges: bool = true
var show_bars: bool = true
## The ring track's alpha in quiet mode, against the loud `Color(0.12, 0.16, 0.22, 0.8)` above.
const QUIET_TRACK_ALPHA := 0.35
## Peer rings in quiet mode: PEER_RING_COLOR's own alpha times this.
const QUIET_PEER_RING_MUL := 0.5
## The creature's parking spot, as a fraction of field_radius(), side length.
const HUB_RECT_FRAC := HUB_FRAC


## Sets `quiet` and, with it, `show_wedges` / `show_bars` together: quiet hides
## both, loud restores both. Queues a redraw so the change is seen on the next
## frame rather than waiting for whatever else happens to touch the tree.
func set_quiet(on: bool) -> void:
	quiet = on
	show_wedges = not on
	show_bars = not on
	queue_redraw()


## The square the creature stands in: centred on the disc, side
## `2 * field_radius() * HUB_FRAC`. Identical in both modes -- the room's
## floor plan does not change when the instrument panel does.
func hub_rect() -> Rect2:
	var side: float = 2.0 * field_radius() * HUB_RECT_FRAC
	var c: Vector2 = disc_center()
	return Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))


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


## fabric peer id -> 0..1 of their internal day. A value outside [0, 1) or not
## finite is dropped rather than wrapped: an out-of-range phase is a field that
## was filled in wrong, not a time of day.
func set_peer_phase(d: Dictionary) -> void:
	_phases = {}
	for id in d:
		var v: float = float(d[id])
		if is_finite(v) and v >= 0.0 and v < 1.0:
			_phases[id] = v


## fabric peer id -> journey chapter. Negative is the wire's "unknown" and is
## dropped, so `peer_plots` never compares against a stage nobody claimed.
func set_peer_stage(d: Dictionary) -> void:
	_stages = {}
	for id in d:
		var v: int = int(d[id])
		if v >= 0:
			_stages[id] = v


## WHERE YOU STAND, which is the other half of every comparison on this dial.
## Pass -1 for either to say you do not know; nothing is then flagged.
func set_own_phase(phase: float = -1.0, stage: int = -1) -> void:
	_own_phase = phase if (is_finite(phase) and phase >= 0.0 and phase < 1.0) else -1.0
	_own_stage = stage if stage >= 0 else -1


func own_phase() -> float:
	return _own_phase


func own_stage() -> int:
	return _own_stage


## THE SHORT WAY ROUND THE DAY. Midnight-minus-a-bit and midnight-plus-a-bit are
## neighbours, not a day apart, so 0.99 and 0.02 are three hundredths away.
static func phase_gap(a: float, b: float) -> float:
	var d: float = absf(fposmod(a - b, 1.0))
	return minf(d, 1.0 - d)


## Awake together: both sides known, and less than IN_PHASE_FRAC of a day apart
## the short way round.
func _in_phase(id: Variant) -> bool:
	if _own_phase < 0.0 or not _phases.has(id):
		return false
	return phase_gap(float(_phases[id]), _own_phase) < IN_PHASE_FRAC


## One chapter ahead, and exactly one: the person who has just walked the bit of
## road you are on now. Two chapters ahead is a stranger again.
func _is_mentor(id: Variant) -> bool:
	if _own_stage < 0 or not _stages.has(id):
		return false
	return int(_stages[id]) == _own_stage + 1


func drop_peer(id: String) -> void:
	_peers.erase(id)
	_phases.erase(id)
	_stages.erase(id)
	_proximity.erase(id)
	_bearings.erase(id)
	_distances.erase(id)
	_spreads.erase(id)
	_blips.erase(id)
	if guide_id == id:
		guide_id = ""


## fabric peer id -> how far away they are, in METRES. THE ONLY THING THAT PUTS
## A PEER ON THE LOG RINGS. Empty in base and it stays empty: this app has no
## GPS, asks for none, and the door that will have one hands the metres in here
## rather than reaching into the radar. A peer absent from this dictionary keeps
## the coarse proximity ring, which is what the transport can honestly say.
##
## A non-positive or non-finite distance is dropped rather than drawn: "0 m" is
## not a measurement, it is a field that was never filled in.
func set_peer_distances_m(metres: Dictionary) -> void:
	_distances = {}
	for id in metres:
		var d: float = float(metres[id])
		if is_finite(d) and d > 0.0:
			_distances[id] = d


## fabric peer id -> half-angle, in degrees, of how much that peer's bearing can
## be believed (Geo.bearing_spread_deg). The nav door's third gift.
func set_peer_spreads_deg(spreads: Dictionary) -> void:
	_spreads = {}
	for id in spreads:
		var v: float = float(spreads[id])
		if is_finite(v):
			_spreads[id] = clampf(v, Geo.SPREAD_MIN_DEG, Geo.SPREAD_MAX_DEG)


# -- the compass ---------------------------------------------------------------

## THE WHOLE COMPASS IN ONE DICTIONARY, exactly the shape `Heading` publishes.
## Keys, all optional: heading_rad, accuracy, pose, live, seen, true_north,
## declination. An absent key keeps what was there, so a caller that only knows
## half of it does not silently blank the other half.
func set_compass(c: Dictionary) -> void:
	if c.has("heading_rad"):
		_heading_rad = fposmod(float(c["heading_rad"]), TAU)
	if c.has("accuracy"):
		_heading_accuracy = int(c["accuracy"])
	if c.has("pose"):
		_heading_pose = String(c["pose"])
	if c.has("live"):
		_heading_live = bool(c["live"])
	if c.has("seen"):
		_heading_seen = bool(c["seen"])
	if c.has("true_north"):
		_true_north = bool(c["true_north"])
	if c.has("declination"):
		_declination = float(c["declination"])


## True when a live compass exists AND the derived accuracy is one we may
## believe. The single condition behind everything that turns or points.
func compass_ok() -> bool:
	return _heading_live and Geo.accuracy_trusted(_heading_accuracy)


## True when a sensor IS feeding us and it may not be believed. This is the
## state the hint is drawn for; no sensor at all is silence, not a warning.
func compass_unreliable() -> bool:
	return _heading_live and not Geo.accuracy_trusted(_heading_accuracy)


## True when the peer field is drawn in the phone's own frame: screen-up is the
## way the phone faces. Same predicate as compass_ok(), under its own name
## because "may the picture turn" is a different question that happens to have
## the same answer.
func north_up() -> bool:
	return compass_ok()


## THE ONE ANGLE SUBTRACTED FROM EVERY PEER, and the only way the compass
## reaches the screen at all.
##
## Zero in the allocentric frame, which is the dial that predates the compass:
## a blip's screen angle is its own angle, 0 is to the right, and the eight
## calcium wedges and the peer field share one frame.
##
## In north-up mode it is (heading + a quarter turn), because screen-up in draw
## coordinates is -PI/2 and we want the direction the phone faces to land there.
## Nothing else in this file knows about the compass.
func frame_offset() -> float:
	return fposmod(_heading_rad + PI * 0.5, TAU) if north_up() else 0.0


## THE ONE LINE OF PROSE ON THIS DIAL, AND IT DOES NOT MOVE. It says only what
## does NOT change when you turn: which north the bearings are referenced to,
## the declination folded in, and how the phone is being held. Where YOU are
## pointing is said by the peers, by swinging; it is never said in words.
func north_caption() -> String:
	if compass_unreliable():
		return UNRELIABLE_HINT
	if compass_ok():
		var said: String = "magnetic north"
		if _true_north:
			said = "true north  \u00b7  decl %+.1f\u00b0" % _declination
		return said + "  \u00b7  " + _heading_pose
	if _heading_seen:
		return "compass quiet \u2014 the peers show the last heading"
	return "no compass"


## Which way to turn to face the peer being guided to, said in words. Empty when
## nothing is being guided to, or when there is no compass to turn against.
func guide_line() -> String:
	if guide_id == "":
		return ""
	var plots: Dictionary = peer_plots()
	if not plots.has(guide_id):
		return ""
	var p: Dictionary = plots[guide_id]
	if bool(p["ring"]):
		return "somewhere around you"
	if compass_unreliable():
		return UNRELIABLE_HINT
	if not compass_ok():
		return ""
	var turn: float = Geo.heading_delta(rad_to_deg(_heading_rad), rad_to_deg(float(p["angle"])))
	if absf(turn) < ON_TARGET_DEG:
		return "straight ahead"
	return "turn %s %.0f\u00b0" % ["right" if turn > 0.0 else "left", absf(turn)]


static func ring_frac(cls: String) -> float:
	return float(RING_FRAC.get(cls, RING_FRAC[DEFAULT_CLASS]))


## Metres to a fraction of the field radius. Log over three decades: 1 m sits on
## the hub, 1 km on the rim, every ring a third of the way further out.
## Monotonic non-decreasing and clamped at both ends, so a peer 40 km away is
## drawn on the rim rather than off the screen.
static func log_frac(distance_m: float) -> float:
	if distance_m <= 1.0:
		return HUB_FRAC
	var t: float = clampf(log(distance_m) / log(10.0) / RING_DECADES, 0.0, 1.0)
	return lerpf(HUB_FRAC, 1.0, t)


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
	for id in _phases:
		ids[id] = true
	for id in _stages:
		ids[id] = true
	var off: float = frame_offset()
	for id in ids:
		var cls: String = String(_proximity.get(id, DEFAULT_CLASS))
		if not RING_FRAC.has(cls):
			cls = DEFAULT_CLASS
		var has_bearing: bool = _bearings.has(id)
		var ang: float = fposmod(float(_bearings[id]) if has_bearing else float(_peers.get(id, 0.0)), TAU)
		# METRES WIN OVER A CLASS, and only metres. `log` says which ring family
		# seated this peer, so a reader never has to guess whether 0.56 meant
		# "the room ring" or "about forty metres".
		var by_metres: bool = _distances.has(id)
		var dist: float = float(_distances.get(id, -1.0))
		var frac: float = log_frac(dist) if by_metres else ring_frac(cls)
		# HOW MUCH TO BELIEVE THE DIRECTION. A handed-in spread wins. Without one:
		# a peer placed by a real bearing gets the minimum ink, and a peer placed
		# by its own fly heading gets the maximum -- which is the ring case,
		# because a fly heading is a fact about THEM and says nothing at all about
		# which way they are from us.
		var spread: float = Geo.SPREAD_MAX_DEG
		if _spreads.has(id):
			spread = float(_spreads[id])
		elif has_bearing:
			spread = Geo.SPREAD_MIN_DEG
		out[id] = {
			"angle": ang,
			"screen": fposmod(ang - off, TAU),
			"frac": frac,
			"cls": cls,
			"bearing": has_bearing,
			"dist_m": dist,
			"log": by_metres,
			"spread": spread,
			"ring": spread >= Geo.SPREAD_RING_DEG,
			# WHERE THEY ARE IN THE DAY AND THE STORY, and the two readings a
			# glass actually draws off them. Both flags need BOTH sides known:
			# a body that has not placed itself recognises nobody.
			"phase": float(_phases.get(id, -1.0)),
			"stage": int(_stages.get(id, -1)),
			"in_phase": _in_phase(id),
			"mentor": _is_mentor(id),
		}
	return out


## True when any peer has been given metres, which is the only thing that puts
## the 10 m / 100 m / 1 km rings on the glass.
func has_metres() -> bool:
	return not _distances.is_empty()


# -- input ---------------------------------------------------------------------

## A tap on the disc, in this Control's own coordinates. Returns the peer now
## being guided to, or "". Guidance is a toggle: tapping while it runs cancels,
## whatever was under the finger -- one gesture in, the same gesture out.
func tap(at: Vector2) -> String:
	if guide_id != "":
		guide_id = ""
		return ""
	guide_id = blip_at(at)
	return guide_id


## The blip under a point, nearest wins. Reads the positions the last draw (or
## `refresh_blips`) actually used, so what you see is what you can hit. "" when
## the finger landed on empty disc.
func blip_at(at: Vector2) -> String:
	var best: String = ""
	var best_d: float = maxf(12.0, field_radius() * BLIP_HIT_FRAC)
	for id in _blips:
		var d: float = (_blips[id] as Vector2).distance_to(at)
		if d <= best_d:
			best_d = d
			best = String(id)
	return best


## Where each blip currently sits, for a test and for the hit-test above.
func blip_positions() -> Dictionary:
	return _blips.duplicate()


## The centre of the disc in this Control's coordinates. The one place the
## drawing and the hit-test agree.
func disc_center() -> Vector2:
	return Vector2(size.x * 0.5, radar_radius + 18.0)


## Recompute the hit-test map without waiting for a frame. `_draw` calls it, and
## so does a headless test that has no viewport to draw into.
func refresh_blips() -> void:
	var c: Vector2 = disc_center()
	var fr: float = field_radius()
	_blips = {}
	var plots: Dictionary = peer_plots()
	for pid in plots:
		var p: Dictionary = plots[pid]
		var a: float = float(p["screen"])
		_blips[pid] = c + Vector2(cos(a), sin(a)) * (fr * float(p["frac"]))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, radar_radius + 18.0)
	var tau_slice: float = TAU / 8.0
	
	# 1. Background ring track. Loud: the full wedge-thick band. Quiet: a
	# single faint arc -- the room's wall, not an instrument.
	if quiet:
		draw_arc(center, radar_radius, 0.0, TAU, 48, Color(0.12, 0.16, 0.22, QUIET_TRACK_ALPHA), 1.0, true)
	else:
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

	if show_wedges:
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
	
	# 3b. THE ROOM INSIDE THE RING. The proximity rings on the disc, the log
	# rings when somebody has handed in metres, and one blip per peer, coloured
	# by the same hue every other surface gives them.
	var fr: float = field_radius()
	refresh_blips()
	var plots: Dictionary = peer_plots()
	var ring_color: Color = PEER_RING_COLOR
	if quiet:
		ring_color = Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * QUIET_PEER_RING_MUL)
	if has_metres():
		# 10 m / 100 m / 1 km. Drawn only when there are metres to be log of;
		# a dial that showed a metric scale for a touch/room/far transport would
		# be inventing a precision nobody measured.
		for i in RING_M.size():
			var rr: float = fr * log_frac(RING_M[i])
			draw_arc(center, rr, 0.0, TAU, 64, ring_color, 1.0, true)
			draw_string(ThemeDB.fallback_font, center + Vector2(6.0, -rr + 11.0),
				RING_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM_COLOR)
	else:
		for cls in RING_ORDER:
			draw_arc(center, fr * ring_frac(cls), 0.0, TAU, 40, ring_color, 1.0, true)
	# 3c. HOW MUCH TO BELIEVE EACH BEARING, as a BAND ALONG THAT PEER'S OWN RING
	# -- never as a wedge from the centre. A shape that starts at your character
	# and opens outward is the universal drawing of a FIELD OF VIEW, and every
	# wedge on a dial begins at the same point, so two peers meant two
	# overlapping fans over the middle and three meant mush. Drawn where the
	# uncertainty IS: a smear at the peer's own distance, centred on the peer's
	# own bearing, spanning the same half-angle. Under the blips, so a band
	# never hides the person it belongs to.
	for pid in plots:
		_draw_band(center, fr, plots[pid])
	var blip_r: float = maxf(2.5, fr * BLIP_R_FRAC)
	for pid in plots:
		var p: Dictionary = plots[pid]
		var a: float = float(p["screen"])
		var dir := Vector2(cos(a), sin(a))
		var at: Vector2 = center + dir * (fr * float(p["frac"]))
		var hue: float = Identity.hue_from_id(String(pid))
		draw_circle(at, blip_r, Identity.body_color(hue))
		draw_arc(at, blip_r, 0.0, TAU, 16, Identity.edge_color(hue), 1.0, true)
		# A blip placed by a real bearing wears a nose; one placed by its own
		# fly heading does not, so the glass never claims a position it lacks.
		if bool(p["bearing"]):
			draw_line(at, at + dir * (blip_r * 1.8), Identity.edge_color(hue), 1.5, true)
		# SOMEBODY ELSE IS AWAKE WITH YOU: a thin second ring, drawn nowhere
		# near the guidance ring's weight so the two never read as one mark.
		if bool(p.get("in_phase", false)):
			draw_arc(at, blip_r * PHASE_RING_MUL, 0.0, TAU, 20, PHASE_RING_COLOR, 1.0, true)
		# ONE CHAPTER AHEAD: a small tick above the blip. Up the page, not up
		# the dial -- a mentor is not a direction in the room.
		if bool(p.get("mentor", false)):
			draw_line(at + Vector2(0.0, -blip_r * 1.2),
				at + Vector2(0.0, -blip_r * MENTOR_TICK_MUL), MENTOR_COLOR, 1.5, true)
		if String(pid) == guide_id:
			draw_arc(at, blip_r * 1.9, 0.0, TAU, 24, GUIDE_COLOR, 2.0, true)
	# 3d. NORTH, WHEN THERE IS A NORTH. Four small ticks that swing with the
	# frame so N keeps pointing at north while the peers sweep past it, and one
	# line of prose that does not move at all. Nothing here draws YOUR heading:
	# see rule 1 at the top of the compass block.
	_draw_north(center, fr)
	# 3e. THE GUIDANCE ARROW, ON THE RIM. It points at the peer being guided to
	# from where you are standing, so turning on the spot swings it to stay on
	# them. Suppressed when the compass may not be believed -- a confident arrow
	# drawn from a reading nothing stands behind is the one thing this screen
	# must not do.
	_draw_guidance(center, fr, plots)

	# 3. Inner Heading Cursor Needle
	var needle_dir := Vector2(cos(current_heading), sin(current_heading))
	var needle_end := center + needle_dir * (radar_radius - ring_thickness * 0.6)
	var needle_col := Color(1.0, 0.35, 0.25, 0.95) if _startled else Color(1.0, 0.95, 0.3, 0.95)
	draw_line(center, needle_end, needle_col, 2.5, true)
	draw_circle(center, 4.0, needle_col)
	
	# 4. Neuromodulator Spectrum Gauges
	if show_neuromodulators and show_bars and _fed:
		_draw_bars(center, Array(_mods))
	elif show_neuromodulators and show_bars and character != null and "_fullness" in character:
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


## The trust band for one peer: an arc at their own radius, centred on their own
## screen bearing, `spread` degrees to either side, fading out at both ends. A
## hard-edged slice invites the eye to read the edges as boundaries in the
## world; one that dissolves says "somewhere along here", which is what a
## bearing spread means. A ring peer gets the whole circle: somewhere around
## you, at a distance that is still perfectly real.
func _draw_band(c: Vector2, fr: float, p: Dictionary) -> void:
	var rad: float = fr * float(p["frac"])
	var half: float = deg_to_rad(float(p["spread"]))
	var thick: float = maxf(2.0, fr * BAND_HALF_FRAC * 2.0)
	if bool(p["ring"]):
		draw_arc(c, rad, 0.0, TAU, 64, BAND_COLOR, thick, true)
		return
	var a: float = float(p["screen"])
	var steps: int = 16
	for i in range(steps):
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var mid: float = (t0 + t1) * 0.5
		# 0 at either end, 1 across the middle.
		var fade: float = sin(mid * PI)
		draw_arc(c, rad, a - half + 2.0 * half * t0, a - half + 2.0 * half * t1, 4,
			BAND_COLOR * Color(1, 1, 1, fade), thick, true)


func _draw_north(c: Vector2, fr: float) -> void:
	var said: String = north_caption()
	if said != "":
		draw_string(ThemeDB.fallback_font, c + Vector2(-fr, -fr - 6.0), said,
			HORIZONTAL_ALIGNMENT_LEFT, fr * 2.0, 9,
			GUIDE_COLOR if compass_unreliable() else DIM_COLOR)
	if not north_up():
		return
	var off: float = frame_offset()
	var cardinals := {0.0: "N", 90.0: "E", 180.0: "S", 270.0: "W"}
	for b in cardinals:
		var a: float = fposmod(deg_to_rad(float(b)) - off, TAU)
		var d := Vector2(cos(a), sin(a))
		var north: bool = is_zero_approx(float(b))
		draw_line(c + d * (fr - (9.0 if north else 6.0)), c + d * fr,
			GUIDE_COLOR if north else PEER_RING_COLOR, 2.0 if north else 1.0, true)
		draw_string(ThemeDB.fallback_font, c + d * (fr - 16.0) + Vector2(-4.0, 4.0),
			String(cardinals[b]), HORIZONTAL_ALIGNMENT_CENTER, -1, 9,
			GUIDE_COLOR if north else DIM_COLOR)


func _draw_guidance(c: Vector2, fr: float, plots: Dictionary) -> void:
	if guide_id == "" or not plots.has(guide_id):
		return
	var p: Dictionary = plots[guide_id]
	var line: String = guide_line()
	if line != "":
		draw_string(ThemeDB.fallback_font, c + Vector2(-fr, fr + 14.0), line,
			HORIZONTAL_ALIGNMENT_CENTER, fr * 2.0, 10, GUIDE_COLOR)
	# A ring has no direction in it, and a compass nobody stands behind has no
	# business drawing one either.
	if bool(p["ring"]) or compass_unreliable():
		return
	var a: float = float(p["screen"])
	var d := Vector2(cos(a), sin(a))
	var side: Vector2 = d.orthogonal() * (fr * 0.07)
	# ON THE RIM, not from the centre. Rule 1: nothing on this dial originates at
	# your own body.
	draw_colored_polygon(PackedVector2Array([
		c + d * (fr * 1.02),
		c + d * (fr * 0.88) + side,
		c + d * (fr * 0.88) - side,
	]), GUIDE_COLOR)
