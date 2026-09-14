extends SceneTree

## THE FLY'S OUTPUTS: what the organism actually does to the glass, the phone
## and the room.
##
## Four sections, and each of them is a claim somebody could otherwise only
## check by holding a phone:
##   1. the calcium radar is really mounted in the shipping scene, and it moves
##      between its two placements the way DeviceProfile says it should;
##   2. the three dials keep out of each other's way with the radar standing,
##      at a tall slab and at a fold that is open;
##   3. the Kuramoto coupling says zero for a balanced room and pulls toward a
##      single peer -- the number the store now carries as swarm_yaw;
##   4. the bio pulse payload carries the heading, the breath and the six-line
##      habit, and survives the trip through a second fabric.

const SCENE: String = "res://scenes/hexy.tscn"
const MeshFabricScript = preload("res://scripts/net/mesh_fabric.gd")

## A tall slab and a fold, unfolded. Both are asked of DeviceProfile with
## explicit arguments, so this test says the same thing on every machine.
const TALL: Vector2i = Vector2i(1080, 2400)
const WIDE: Vector2i = Vector2i(1812, 2176)
const FOLD_RAM: int = 12 * 1024 * 1024 * 1024

var _fails: int = 0
var _checks: int = 0
## A suite that ran nothing must not print ALL PASS. Raise with the checks.
const MIN_CHECKS: int = 22


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		print("FAIL ", what)


func _initialize() -> void:
	print("\n--- TEST FLY OUTPUTS (radar, swarm, haptics) ---")
	_test_profiles()
	_test_kuramoto()
	_test_bio_payload()
	await _test_radar_in_the_glass()
	print("checks: ", _checks, " (floor ", MIN_CHECKS, ")")
	if _checks < MIN_CHECKS:
		_fails += 1
		print("FAIL only ", _checks, " checks ran; the floor is ", MIN_CHECKS)
	if _fails == 0:
		print("--- ALL FLY OUTPUT TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- FLY OUTPUT TESTS FAILED: ", _fails, " ---\n")
		quit(1)


# --- 1. which layout each phone gets ----------------------------------------

func _test_profiles() -> void:
	var tall: Dictionary = DeviceProfile.resolve(FOLD_RAM, TALL, "Android")
	var wide: Dictionary = DeviceProfile.resolve(FOLD_RAM, WIDE, "Android")
	_check(String(tall.get("layout", "")) == "tall_slab",
		"1080x2400 on a fold's RAM is a tall slab")
	_check(not bool(tall.get("is_dual_pane", true)),
		"and a tall slab is not dual pane, so the radar is a disc")
	_check(String(wide.get("layout", "")) == "dual_pane",
		"1812x2176 is the fold open, and that is dual pane")
	_check(bool(wide.get("is_dual_pane", false)),
		"so the radar gets a column of its own beside the stage")


# --- 2. the swarm's pull ----------------------------------------------------

func _test_kuramoto() -> void:
	var f: Node = MeshFabricScript.new()
	root.add_child(f)

	_check(is_equal_approx(f.compute_kuramoto_coupling(0.0), 0.0),
		"a room of one has no pull at all")

	f.peer_headings["a"] = 0.5
	f.peer_headings["b"] = -0.5
	var balanced: float = f.compute_kuramoto_coupling(0.0)
	_check(absf(balanced) < 1e-6,
		"two peers at +0.5 and -0.5 cancel exactly (got %.9f)" % balanced)

	f.peer_headings.clear()
	f.peer_headings["a"] = 1.0
	var pulled: float = f.compute_kuramoto_coupling(0.0)
	_check(pulled > 0.0, "one peer at +1.0 rad pulls positive (got %.4f)" % pulled)
	_check(is_equal_approx(pulled, 0.15 * sin(1.0)),
		"and the pull is the gain times sin(delta), nothing more")
	_check(f.compute_kuramoto_coupling(1.0) == 0.0,
		"a body already facing the peer is not turned")
	_check(f.compute_kuramoto_coupling(2.0) < 0.0,
		"and a body past the peer is turned back")

	## THE CONSUMER. The store carries the number and clamps it, which is the
	## field sensor_oracle adds to its gyro yaw rate.
	var store := HexyStore.new()
	root.add_child(store)
	store.set_swarm_yaw(pulled)
	_check(is_equal_approx(store.swarm_yaw, pulled), "the store carries the swarm's pull")
	store.set_swarm_yaw(99.0)
	_check(is_equal_approx(store.swarm_yaw, HexyStore.MAX_SWARM_YAW),
		"and a coupling is a nudge, never a spin")
	store.free()
	f.free()


# --- 3. what goes on the wire -----------------------------------------------

func _test_bio_payload() -> void:
	var habit: Array = [0.1234, -0.5, 0.0, 0.9999, -0.25, 0.5]
	var body: Dictionary = MeshFabricScript.bio_payload(1.23456, 0.77777, habit)
	_check(body.has("heading") and body.has("oa") and body.has("habit_bias"),
		"the pulse carries the heading, the breath and the habit")
	_check(is_equal_approx(float(body["heading"]), 1.235),
		"the heading is rounded to three decimals (%s)" % str(body["heading"]))
	_check((body["habit_bias"] as PackedFloat32Array).size() == 6,
		"the habit is all six lines")
	_check(not body.has("q6"),
		"and no Q6 cloud rides along until a store publishes one")

	# A second fabric hears it. No sockets: the envelope is handed to the
	# receiving fabric through the same door a transport would use.
	var a: Node = MeshFabricScript.new()
	var b: Node = MeshFabricScript.new()
	root.add_child(a)
	root.add_child(b)
	var heard: Array = []
	b.swarm_heading_received.connect(func(pid, h, oa): heard.append([pid, h, oa]))
	var env: Dictionary = a.broadcast_bio_state(1.23456, 0.77777, habit)
	_check(int(env.get("ttl", 9)) == 1,
		"a heading is a fact about a body in a room and is never relayed")
	b._on_transport_event("link-a", env)
	_check(heard.size() == 1, "the far fabric raises swarm_heading_received once")
	if heard.size() == 1:
		_check(String(heard[0][0]) == String(a.fabric_id),
			"and names the fabric that spoke")
		_check(is_equal_approx(float(heard[0][1]), 1.235), "with the heading intact")
	else:
		_check(false, "and names the fabric that spoke")
		_check(false, "with the heading intact")
	_check(b.peer_bio.has(a.fabric_id), "the whole payload is kept as peer_bio")
	if b.peer_bio.has(a.fabric_id):
		var kept: Dictionary = b.peer_bio[a.fabric_id]
		_check((kept.get("habit_bias", []) as PackedFloat32Array).size() == 6,
			"habit and all, so a radar can draw the swarm")
	else:
		_check(false, "habit and all, so a radar can draw the swarm")
	a.free()
	b.free()


# --- 4. the radar in the shipping glass -------------------------------------

func _test_radar_in_the_glass() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		_check(false, "scenes/hexy.tscn loads")
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var found: Control = _find_radar(app)
	_check(found != null, "a FlyCalciumRadar2D is mounted in the shipping scene")
	if found == null:
		app.queue_free()
		return
	_check(found.custom_minimum_size.x >= 220.0,
		"and it is at least 220 px wide wherever it stands")

	var hud: Hud3 = app.hud
	for px in [TALL, WIDE]:
		await _use(px)
		var h: Rect2 = hud.head_rect()
		var b: Rect2 = hud.body_rect()
		var e: Rect2 = hud.earth_rect()
		var r: Rect2 = found.get_global_rect()
		print("at %dx%d: radar %s (%s) head %s body %s earth %s" % [
			px.x, px.y, r, hud.radar_layout(), h, b, e])
		_check(not h.intersects(b) and not b.intersects(e) and not h.intersects(e),
			"at %dx%d the three dials still keep out of each other's way" % [px.x, px.y])
		_check(h.size.x > 8.0 and b.size.x > 8.0 and e.size.x > 8.0,
			"at %dx%d all three dials still have a band" % [px.x, px.y])
		if hud.radar_layout() == "dual_pane":
			_check(found.is_visible_in_tree(), "at %dx%d the radar is on the glass" % [px.x, px.y])
			_check(not r.intersects(h) and not r.intersects(b) and not r.intersects(e),
				"at %dx%d the radar lies beside the dials, never over one" % [px.x, px.y])

	# The radar is fed the character's own dictionary, not a brain member.
	await _use(WIDE)
	_check(hud.radar_layout() == "dual_pane", "the fold open puts the radar in its own column")
	var fly: Dictionary = app.store.get_character().get_fly_state()
	found.set_state(fly)
	found.set_peer_headings({"p1": 0.5, "p2": -1.0})
	_check(found.peer_heading_count() == 2, "and it draws a tick for every peer heading")
	var bump: PackedFloat32Array = FlyCalciumRadar2D.bump_of(0.0, 1.0)
	var total: float = 0.0
	for v in bump:
		total += v
	_check(is_equal_approx(total, 1.0), "the eight wedges are a distribution")
	var peak: float = 0.0
	for v in bump:
		peak = maxf(peak, v)
	_check(is_equal_approx(bump[0], peak), "and the bump sits on the heading")

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


func _use(px: Vector2i) -> void:
	root.size = px
	root.content_scale_size = px
	await process_frame
	await process_frame


static func _find_radar(n: Node) -> Control:
	if n is FlyCalciumRadar2D:
		return n as Control
	for c in n.get_children():
		var hit: Control = _find_radar(c)
		if hit != null:
			return hit
	return null
