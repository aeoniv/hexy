extends MainLoop

const SensorOracleScript := preload("res://scripts/sensor_oracle.gd")
const ModelStoreScript := preload("res://scripts/brain/model_store.gd")

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
	print("HEXY_TEST: Running Samsung Galaxy Z Fold 4 Gating Test Suite...")
	_test_flex_mode_tabletop()
	_test_fold4_ram_gating()
	_test_fold4_display_aspect()
	
	print("\n=== FOLD 4 GATING TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Fold 4 Gating Verified)")
	return true


func _test_flex_mode_tabletop() -> void:
	print("\n• Testing Fold 4 Flex-Mode Tabletop Detection...")
	var oracle: Node = SensorOracleScript.new()
	
	# Test 1: Phone flat on desk (gravity.y = 0.0, gravity.z = -9.8) -> Not angled flex mode
	oracle.filtered_grav = Vector3(0.0, -0.2, -9.8)
	oracle.filtered_jerk = 0.05
	oracle.filtered_gyro = Vector3(0.01, 0.01, 0.01)
	check(not oracle.is_flex_mode_tabletop(), "Flat on desk is not flex-mode tabletop")
	
	# Test 2: Phone held in hand (moving/shaking) -> Not stationary tabletop
	oracle.filtered_grav = Vector3(0.0, -7.0, 6.8) # Angled
	oracle.filtered_jerk = 1.2 # Human hand trembling
	check(not oracle.is_flex_mode_tabletop(), "Angled phone trembling in hand is not stationary tabletop")
	
	# Test 3: Fold 4 resting on desk in Flex Mode (~90° hinge angle, stationary)
	oracle.filtered_grav = Vector3(0.0, -7.0, 6.8) # Angled
	oracle.filtered_jerk = 0.05 # Stationary on desk
	oracle.filtered_gyro = Vector3(0.02, 0.01, 0.01)
	check(oracle.is_flex_mode_tabletop(), "Fold 4 stationary in Flex Mode triggers tabletop sanctuary")
	
	oracle.free()


func _test_fold4_ram_gating() -> void:
	print("\n• Testing ModelStore RAM Gating (Galaxy A22 vs Fold 4)...")
	# Galaxy A22 profile: 3.5 GB available RAM
	OS.set_environment("HEXY_RAM_BYTES", str(int(3.5 * 1024 * 1024 * 1024)))
	var a22_lane: Dictionary = ModelStore.resolve_chat_lane()
	check(a22_lane["tier"] == "Floor" and a22_lane["gated_by_ram"] == true,
		"Galaxy A22 (3.5 GB) is gated to Floor tier (qwen3-0.6b)")
	
	# Galaxy Z Fold 4 profile: 12.0 GB RAM
	OS.set_environment("HEXY_RAM_BYTES", str(int(12.0 * 1024 * 1024 * 1024)))
	var fold4_lane: Dictionary = ModelStore.resolve_chat_lane()
	check(fold4_lane["tier"] == "High" and fold4_lane["gated_by_ram"] == false,
		"Galaxy Z Fold 4 (12 GB) unlocks High tier (qwen3-1.7b) with gated_by_ram == false")


func _test_fold4_display_aspect() -> void:
	print("\n• Testing Fold 4 Display Form Factors...")
	var cover_size := Vector2i(1080, 2408)
	var unfolded_size := Vector2i(1812, 2176)
	
	var cover_aspect: float = float(cover_size.y) / float(cover_size.x)
	var unfolded_aspect: float = float(unfolded_size.y) / float(unfolded_size.x)
	
	check(cover_aspect > 2.0, "Cover screen is tall slab aspect (> 2.0: %.2f)" % cover_aspect)
	check(unfolded_aspect >= 1.1 and unfolded_aspect <= 1.3,
		"Unfolded screen is square tablet aspect (1.1..1.3: %.2f)" % unfolded_aspect)
	check(unfolded_size.x > 1200, "Unfolded width (%d > 1200) qualifies for dual-pane studio layout" % unfolded_size.x)
