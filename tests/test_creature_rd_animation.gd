extends SceneTree

const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")
const Creature = preload("res://scripts/creature/creature.gd")

func _initialize() -> void:
	print("\n--- TEST CREATURE RD ANIMATION & KINEMATICS ---")
	
	var creature_ball := CreatureBall3D.new()
	root.add_child(creature_ball)
	
	# Verify default is Rhombic Dodecahedron
	check(creature_ball.geometry_mode == CreatureBall3D.GeometryMode.RHOMBIC_DODECAHEDRON, "default geometry is Rhombic Dodecahedron")
	check(creature_ball.get_current_geometry_name() == "Rhombic Dodeca", "geometry name is Rhombic Dodeca")
	
	# Test 1: Centroid centering & vertex bounds
	var tips: Array[Vector3] = creature_ball._compute_base_vertices(0b111111, 0.15, 0.0, 0.0)
	check(tips.size() == 14, "RD has exactly 14 tips (6 axial + 8 cubic)")
	
	var centroid: Vector3 = Vector3.ZERO
	for pt in tips:
		centroid += pt
	centroid /= float(tips.size())
	check(centroid.length() < 0.001, "initial centroid is identically zero")
	
	for i in range(tips.size()):
		check(abs(tips[i].x) <= 0.65 and abs(tips[i].y) <= 0.65 and abs(tips[i].z) <= 0.65, "vertex %d is within bounds: %s" % [i, str(tips[i])])
		
	# Test 2: Coupled Breathing Dynamics (Axial & Cubic)
	var t0_axial_len: float = tips[0].distance_to(tips[1])
	var t0_cubic_r: float = tips[6].length()
	
	var tips_t1: Array[Vector3] = creature_ball._compute_base_vertices(0b111111, 0.15, 0.0, 1.2)
	var t1_axial_len: float = tips_t1[0].distance_to(tips_t1[1])
	var t1_cubic_r: float = tips_t1[6].length()
	
	check(abs(t1_axial_len - t0_axial_len) > 0.0001, "axial struts breathe over time")
	check(abs(t1_cubic_r - t0_cubic_r) > 0.0001, "cubic trigram hubs breathe radially over time")
	
	# Test 3: Neuromodulator state integration
	creature_ball.set_fly_brain_state(PI * 0.5, 0.9, 0.8, 0.1, 0.0)
	check(creature_ball.octopamine_level == 0.9, "octopamine level updated")
	check(creature_ball.dopamine_level == 0.8, "dopamine level updated")
	check(creature_ball.target_heading_yaw == PI * 0.5, "target heading updated")
	
	# Test 4: DFB Sleep contraction
	creature_ball.set_fly_brain_state(0.0, 0.2, 0.5, 0.95, 0.0)
	var tips_sleep: Array[Vector3] = creature_ball._compute_base_vertices(0b111111, 0.15, 0.0, 0.0)
	var sleep_r: float = tips_sleep[6].length()
	check(sleep_r < t0_cubic_r, "DFB sleep contracts the creature into resting posture")
	
	# Test 5: Touch impulse response & damping
	creature_ball.apply_touch_impulse(Vector3.FORWARD, 1.5)
	check(creature_ball.impulse_wobble > 1.0, "touch impulse excited wobble")
	check(creature_ball.impulse_vel.length() > 0.1, "touch impulse added velocity")
	
	# Process one simulation tick
	creature_ball._process(0.016)
	check(creature_ball.position.length() > 0.0001, "zero-g buoyancy and impulse translated position")
	
	# Test 6: Full Creature host node integration
	var creature := Creature.new()
	root.add_child(creature)
	check(creature.ball != null, "creature owns ball")
	check(creature.mandala != null, "creature owns mandala")
	check(creature.mandala.visible == false, "creature mandala is hidden to avoid duplicate icons")
	
	# Test tap impulse forwarding
	creature.tap(Vector2(540, 960))
	check(creature.ball.impulse_wobble > 0.5, "tap forwarded impulse to ball")
	
	creature_ball.queue_free()
	creature.queue_free()
	
	print("--- ALL CREATURE RD ANIMATION TESTS PASSED PERFECTLY ---\n")
	quit(0)

func check(condition: bool, description: String) -> void:
	if not condition:
		printerr("FAIL: ", description)
		assert(false, description)
	print("PASS: ", description)
