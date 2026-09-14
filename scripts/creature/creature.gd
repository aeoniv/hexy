class_name Creature
extends Node3D

## THE BODY ON THE GLASS: one ball, one mandala, one camera.
##
## Creature owns no geometry of its own. It INSTANCES the two things the old
## app already drew -- CreatureBall3D (the strut/cord solid) and
## SensorMandala3D (the dual orbit and its resonance arc) -- and wires them to
## the store. Nothing is copied down from them; if either ever learns a new
## trick, the creature learns it the same day.
##
## IT REACHES FOR NOTHING. No plugin, no socket, no sense object of its own.
## The store arrives in `bind`, the sixteen (if the host has them) arrive in
## `set_senses`, and everything else is a signal. That is the whole contract,
## and the import wall test keeps it honest.
##
## A TAP IS ASKED, NOT GUESSED. The ball already knows which of its eight
## machine nodes a point lands on; duplicating that arithmetic here would mean
## two hit tests that drift apart. So `tap` pushes the touch INTO the ball and
## watches: if a node answered, the creature asks for a throw; if the ball had
## nothing under the finger, the solid turns to its next geometry instead.

const BallScript := preload("res://scripts/creature_ball_3d.gd")
const MandalaScript := preload("res://scripts/sensor_mandala_3d.gd")

## A machine node was tapped: the glass should cast.
signal throw_requested(trigram: int)
## The solid turned to another geometry (0 ico, 1 rhombic dodeca, 2 triaconta).
signal geometry_changed(mode: int)

var ball: Node3D = null
var mandala: Node3D = null
var camera: Camera3D = null

var _store: Node = null
var _senses: Node = null
var _node_hit: bool = false


func _init() -> void:
	ball = BallScript.new()
	ball.name = "Ball"
	mandala = MandalaScript.new()
	mandala.name = "Mandala"
	camera = Camera3D.new()
	camera.name = "Eye"
	camera.position = Vector3(0.0, 0.0, 2.05)
	camera.fov = 52.0
	camera.current = true


func _ready() -> void:
	add_child(ball)
	add_child(mandala)
	add_child(camera)
	if not ball.machine_node_clicked.is_connected(_on_machine_node_clicked):
		ball.machine_node_clicked.connect(_on_machine_node_clicked)
	set_process(true)


func _process(_delta: float) -> void:
	if _store != null and _store.has_method("get_character"):
		var ch: Variant = _store.get_character()
		if ch != null and ball != null and ball.has_method("set_fly_brain_state"):
			var cc: Variant = ch.get("central_complex")
			var gf: Variant = ch.get("giant_fiber")
			var nms: Dictionary = ch.get_neuromodulators() if ch.has_method("get_neuromodulators") else {}
			var h_rad: float = float(cc.get("heading_rad")) if cc != null else 0.0
			var oa_v: float = float(nms.get("octopamine", 0.5))
			var da_v: float = float(nms.get("dopamine", 0.5))
			var dfb_v: float = float(nms.get("gaba", 0.2))
			var curl_v: float = float(gf.get("startle_intensity")) if (gf != null and gf.get("startle_intensity") != null) else 0.0
			ball.set_fly_brain_state(h_rad, oa_v, da_v, dfb_v, curl_v)


# -- wiring ------------------------------------------------------------------

## The one piece of shared state. Everything the creature shows comes through
## these three signals and nothing else.
func bind(store: Node) -> void:
	_store = store
	if store == null:
		return
	if not store.hexagram_changed.is_connected(_on_hexagram_changed):
		store.hexagram_changed.connect(_on_hexagram_changed)
	if not store.machine_changed.is_connected(_on_family_changed):
		store.machine_changed.connect(_on_family_changed)
	if not store.human_changed.is_connected(_on_family_changed):
		store.human_changed.connect(_on_family_changed)
	_on_hexagram_changed(store.hexagram)
	_on_family_changed(store.machine)


## Optional: the sixteen, so the mandala can be fed 8 + 8 real scores instead
## of the two winners alone. A creature without them is not a broken creature.
func set_senses(senses: Node) -> void:
	_senses = senses
	_on_family_changed({})


func set_thinking(b: bool) -> void:
	ball.set_thinking(b)
	mandala.set_thinking(b)


## The eight machine scores and the eight human ones, 0..1. Read from the
## sixteen when they are here, else a single lit seat per family.
func scores() -> Dictionary:
	if _senses != null and _senses.has_method("scores"):
		var s: Dictionary = _senses.scores()
		return {
			"machine": _as_floats(s.get("machine", [])),
			"human": _as_floats(s.get("human", [])),
		}
	return {"machine": _winner_row(_store_family("machine")), "human": _winner_row(_store_family("human"))}


func geometry_mode() -> int:
	return int(ball.geometry_mode)


func geometry_name() -> String:
	return String(ball.get_current_geometry_name())


# -- the tap -----------------------------------------------------------------

## One tap at `pos`, in this creature's viewport coordinates. The ball is asked
## first; only a touch that hits no node turns the geometry.
func tap(pos: Vector2) -> void:
	_node_hit = false
	var vp: Viewport = get_viewport()
	if vp != null:
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.position = pos
		down.pressed = true
		vp.push_input(down, true)
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.position = pos
		up.pressed = false
		vp.push_input(up, true)
	if not _node_hit:
		geometry_changed.emit(ball.cycle_geometry_mode())


func _on_machine_node_clicked(trigram: int) -> void:
	_node_hit = true
	throw_requested.emit(int(trigram))


# -- the store speaks --------------------------------------------------------

func _on_hexagram_changed(h: Dictionary) -> void:
	var bits: int = int(h.get("bits", 0)) & 63
	var moving: int = int(h.get("moving", 0)) & 63
	# The store keeps the moving lines as a MASK; the ball lights exactly one
	# strut and wants a line INDEX. The bottom moving line is the one that turns
	# first, so that is the strut the body shows. Handing the mask over instead
	# would index the strut table with a number up to 63 and tear the solid.
	ball.set_hexagram(bits, _first_moving(moving))
	if mandala.has_method("set_body_hexagram"):
		mandala.set_body_hexagram(KingWen.number(bits))


## The bottom moving line, counted from 0, or -1 when the figure holds.
static func _first_moving(mask: int) -> int:
	for i in range(6):
		if ((mask >> i) & 1) == 1:
			return i
	return -1


func _on_family_changed(_f: Dictionary) -> void:
	if _store == null:
		return
	var rows: Dictionary = scores()
	var m: Array = rows.get("machine", [])
	var h: Array = rows.get("human", [])
	mandala.update_telemetry({
		"lower_trigram": int(_store.machine.get("trigram", 0)),
		"upper_trigram": int(_store.human.get("trigram", 0)),
		"line_strains": _strains(m, h),
	})


## The six lines, strained by the two rows the glass is showing: the lower
## three read the machine row, the upper three the human one.
static func _strains(m: Array, h: Array) -> Array:
	var out: Array = []
	for i in range(3):
		out.append(_pick(m, i))
	for i in range(3):
		out.append(_pick(h, i))
	return out


static func _pick(row: Array, i: int) -> float:
	if i < 0 or i >= row.size():
		return 0.0
	return float(row[i])


func _store_family(which: String) -> Dictionary:
	if _store == null:
		return {}
	return _store.machine if which == "machine" else _store.human


static func _winner_row(f: Dictionary) -> Array[float]:
	var out: Array[float] = ([] as Array[float])
	var seat: int = clampi(int(f.get("trigram", 0)), 0, 7)
	var score: float = float(f.get("score", 0.0))
	for i in range(8):
		out.append(score if i == seat else 0.0)
	return out


static func _as_floats(v: Variant) -> Array[float]:
	var out: Array[float] = ([] as Array[float])
	if v is Array:
		for x in (v as Array):
			out.append(float(x))
	while out.size() < 8:
		out.append(0.0)
	return out
