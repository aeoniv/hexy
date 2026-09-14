extends MainLoop

const FlyMushroomBodyScript := preload("res://scripts/brain/fly_mushroom_body.gd")
const FlyGiantFiberScript := preload("res://scripts/brain/fly_giant_fiber.gd")
const FlyCentralComplexScript := preload("res://scripts/brain/fly_central_complex.gd")
const CharacterScript := preload("res://scripts/brain/character.gd")

var passes := 0
var failures := 0


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func _process(_delta: float) -> bool:
	print("HEXY_TEST: Running Full Drosophila Connectome Test Suite...")
	_test_mushroom_body()
	_test_giant_fiber()
	_test_central_complex_goal_vector()
	_test_character_integration()
	
	print("\n=== CONNECTOME TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Full Fly Brain Verified)")
	return true


func _test_mushroom_body() -> void:
	print("\n• Testing FlyMushroomBody (Kenyon Cells & Associative Hebbian Learning)...")
	var mb: RefCounted = FlyMushroomBodyScript.new()
	
	# Test 1: 16-input sensory context encoding into 256 KCs
	var sensory_a := [0.1, 0.8, 0.2, 0.9, 0.0, 0.5, 0.3, 0.4, 0.7, 0.6, 0.2, 0.1, 0.9, 0.8, 0.5, 0.3]
	var kcs_a: PackedInt32Array = mb.encode_context(sensory_a)
	check(kcs_a.size() == 16, "Mushroom body produces exact top-16 sparse Kenyon cell activations")
	
	# Context hash check
	var hash_a: PackedInt32Array = mb.context_hash.duplicate()
	check(hash_a.size() == 8, "Context hash has 8 x 32-bit words (256-bit hash)")
	
	# Test 2: Similar sensory state yields low Hamming distance (LSH property)
	var sensory_similar := [0.12, 0.78, 0.22, 0.88, 0.0, 0.52, 0.31, 0.41, 0.69, 0.61, 0.21, 0.11, 0.89, 0.81, 0.51, 0.29]
	var _kcs_sim: PackedInt32Array = mb.encode_context(sensory_similar)
	var hash_sim: PackedInt32Array = mb.context_hash.duplicate()
	var dist_similar: int = FlyMushroomBodyScript.hamming_distance(hash_a, hash_sim)
	check(dist_similar <= 12, "Similar sensory context has small Hamming distance (%d <= 12)" % dist_similar)
	
	# Test 3: Very different sensory state yields large Hamming distance
	var sensory_diff := [0.9, 0.0, 0.8, 0.1, 0.9, 0.1, 0.8, 0.9, 0.0, 0.1, 0.9, 0.9, 0.0, 0.1, 0.1, 0.9]
	var _kcs_diff: PackedInt32Array = mb.encode_context(sensory_diff)
	var hash_diff: PackedInt32Array = mb.context_hash.duplicate()
	var dist_diff: int = FlyMushroomBodyScript.hamming_distance(hash_a, hash_diff)
	check(dist_diff >= 18, "Divergent sensory context has large Hamming distance (%d >= 18)" % dist_diff)
	
	# Test 4: Associative Hebbian Learning
	# Reinforce sensory_a with positive Dopamine reward on Focus (channel 4)
	mb.encode_context(sensory_a)
	var init_bias: Array[float] = mb.predict_habit_bias()
	check(absf(init_bias[4]) < 0.001, "Initial habit bias is 0.0 before training")
	
	for epoch in range(10):
		mb.learn([0.0, 0.0, 0.0, 0.0, 0.8, 0.0])  # +0.8 reward on Focus
	
	var learned_bias: Array[float] = mb.predict_habit_bias()
	check(learned_bias[4] > 0.15, "Associative Hebbian plasticity learned positive Focus habit (got %.3f > 0.15)" % learned_bias[4])
	
	# Present different context - habit bias should not bleed heavily
	mb.encode_context(sensory_diff)
	var diff_bias: Array[float] = mb.predict_habit_bias()
	check(diff_bias[4] < learned_bias[4] * 0.6, "Habit bias is context-selective (got %.3f < %.3f)" % [diff_bias[4], learned_bias[4] * 0.6])


func _test_giant_fiber() -> void:
	print("\n• Testing FlyGiantFiber (Escape & Shock Reflex)...")
	var gf: RefCounted = FlyGiantFiberScript.new()
	
	# Test 1: Normal steady gravity produces no startle
	var intensity: float = gf.step(0.016, Vector3(0.0, -9.8, 0.0))
	check(not gf.is_startled and intensity == 0.0, "Normal 1g gravity produces no startle")
	
	# Test 2: Freefall (0g) triggers immediate startle
	intensity = gf.step(0.016, Vector3(0.0, -0.5, 0.0))
	check(gf.is_startled and intensity == 1.0, "0g freefall triggers maximum startle (intensity = 1.0)")
	check(gf.get_curl_factor() == 1.0, "Startle curl factor is 1.0 for shock absorption")
	
	# Test 3: Exponential recovery
	for step in range(60): # 1 second at 60 FPS
		gf.step(0.016, Vector3(0.0, -9.8, 0.0))
	check(gf.startle_intensity < 0.6, "Startle decays back toward baseline during recovery (got %.3f)" % gf.startle_intensity)


func _test_central_complex_goal_vector() -> void:
	print("\n• Testing FlyCentralComplex Fan-Shaped Body (FB) 2D Goal Vector...")
	var cx: RefCounted = FlyCentralComplexScript.new()
	
	# Set current heading to 0.0 rad
	cx.current_heading = 0.0
	
	# Set target to Heaven (trigram 7: angle 7 * TAU / 8 = 7 * PI / 4 = -PI / 4)
	cx.set_target_trigram(7)
	var err: float = cx.steering_error()
	check(absf(err - (-PI * 0.25)) < 0.01, "Steering error calculates signed shortest angle (got %.3f)" % err)
	
	# Alignment with target
	cx.set_target_hexagram(1) # Hexagram 1 -> angle 0.0 rad
	var align: float = cx.target_alignment()
	check(align > 0.999, "Target alignment is 1.0 when heading matches target")
	
	var vec: Vector2 = cx.compute_steering_vector()
	check(vec.x > 0.99 and absf(vec.y) < 0.01, "Steering vector points full forward with zero turn")


func _test_character_integration() -> void:
	print("\n• Testing Character Integration with Connectome Subsystems...")
	var ch: RefCounted = CharacterScript.new()
	check(ch.mushroom_body != null, "Character instantiates FlyMushroomBody")
	check(ch.giant_fiber != null, "Character instantiates FlyGiantFiber")
	
	# Test Giant Fiber startle excitation
	var init_oa: float = ch.get_fullness(ch.LINE_BREATH)
	ch.giant_fiber._trigger_startle(1.0, "test_shock")
	var post_oa: float = ch.get_fullness(ch.LINE_BREATH)
	check(post_oa > init_oa, "Giant Fiber startle triggers Octopamine flight arousal spike (%.2f -> %.2f)" % [init_oa, post_oa])
	
	# Test to_q6_bias habit blending
	var bias_clean: PackedFloat64Array = ch.to_q6_bias(false)
	var bias_habit: PackedFloat64Array = ch.to_q6_bias(true)
	check(bias_clean.size() == 6 and bias_habit.size() == 6, "to_q6_bias returns 6-element bias vector")
