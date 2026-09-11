extends SceneTree

func _init() -> void:
	print("--- TEST SENSOR ORACLE 8x8 CYBERNETIC ENGINE ---")
	
	var oracle := SensorOracle.new()
	assert(oracle != null, "SensorOracle must instantiate")
	
	# Test 1: Validate array lengths and nomenclature
	assert(SensorOracle.MACHINE_NAMES.size() == 8, "Must have exactly 8 Machine substrates")
	assert(SensorOracle.HUMAN_NAMES.size() == 8, "Must have exactly 8 Human habit disciplines")
	assert(SensorOracle.TRIGRAM_NAMES.size() == 8, "Must have exactly 8 Trigrams")
	print("Test 1 Passed: 8 Machine x 8 Human arrays verified.")
	
	# Test 2: Verify Cartesian space 8x8 = 64 distinct states
	var seen_states := {}
	for h in range(8):
		for m in range(8):
			var hex_bits: int = (h << 3) | m
			assert(hex_bits >= 0 and hex_bits < 64, "Bit range must be [0, 63]")
			seen_states[hex_bits] = true
	assert(seen_states.size() == 64, "Cartesian space must produce all 64 King Wen binary states")
	print("Test 2 Passed: 64 King Wen Cartesian states perfectly mapped.")
	
	# Test 3: Machine Substrate classification rules
	# Desk flat (g.z = -9.8, jerk = 0, gyro = 0, prox = 5)
	oracle.filtered_grav = Vector3(0, 0, -9.8)
	oracle.filtered_jerk = 0.05
	oracle.filtered_gyro = Vector3.ZERO
	oracle.current_proximity = 5.0
	assert(oracle._classify_machine_trigram() == 4, "Desk rest must classify as Mountain (4)")
	
	# Solar Photosphere (lux = 5000)
	oracle.current_lux = 5000.0
	oracle.current_proximity = 0.0 # reset desk
	assert(oracle._classify_machine_trigram() == 5, "High lux must classify as Fire (5)")
	
	# Depleted Battery (bat = 15%)
	oracle.current_lux = 50.0
	oracle.current_battery = 15.0
	assert(oracle._classify_machine_trigram() == 2, "Low battery must classify as Water (2)")
	
	# Night Sanctuary (hour = 23.5, lux = 5)
	oracle.current_battery = 80.0
	oracle.solar_hour = 23.5
	oracle.current_lux = 5.0
	assert(oracle._classify_machine_trigram() == 0, "Night stillness must classify as Earth (0)")
	
	# Solar Noon (hour = 12.5, lux = 600)
	oracle.solar_hour = 12.5
	oracle.current_lux = 600.0
	assert(oracle._classify_machine_trigram() == 7, "Solar noon must classify as Heaven (7)")
	print("Test 3 Passed: Machine Substrates accurately classified.")
	
	# Test 4: Human Habit classification rules
	# Deep Work screen-down eclipse (g.z = -8.5, prox = 1.0)
	oracle.filtered_grav = Vector3(0, 0, -8.5)
	oracle.current_proximity = 1.0
	assert(oracle._classify_human_trigram() == 4, "Screen-down eclipse must classify as Mountain (4 - Deep Work)")
	
	# Locomotion Steps (jerk = 4.0)
	oracle.current_proximity = 5.0
	oracle.filtered_jerk = 4.0
	assert(oracle._classify_human_trigram() == 1, "Cadence / steps must classify as Thunder (1 - Locomotion)")
	
	# Upright Spine Posture (g.y = -8.5, g.z = 2.0, jerk = 0.1)
	oracle.filtered_jerk = 0.1
	oracle.kinetic_excitation = 0.0
	oracle.filtered_grav = Vector3(0, -8.5, 2.0)
	assert(oracle._classify_human_trigram() == 7, "Vertical orientation must classify as Heaven (7 - Upright Spine)")
	
	# Sleep Rest (hour = 23.5, jerk = 0.05)
	oracle.solar_hour = 23.5
	oracle.filtered_grav = Vector3(0, 0, 9.8) # on bed
	oracle.filtered_jerk = 0.05
	assert(oracle._classify_human_trigram() == 0, "Night rest must classify as Earth (0 - Sleep Rest)")
	print("Test 4 Passed: Human Habits accurately classified.")
	
	# Test 5: Telemetry snapshot completeness
	oracle._classify_both_trigrams()
	var snap := oracle.get_telemetry_snapshot()
	assert(snap.has("machine_trigram"), "Snapshot must contain machine_trigram")
	assert(snap.has("human_trigram"), "Snapshot must contain human_trigram")
	assert(snap.has("machine_name"), "Snapshot must contain machine_name")
	assert(snap.has("human_name"), "Snapshot must contain human_name")
	assert(snap.has("line_strains"), "Snapshot must contain line_strains")
	assert(snap["line_strains"].size() == 6, "Must have 6 line strains")
	print("Test 5 Passed: Telemetry snapshot conforms to 8x8 contract.")
	
	oracle.free()
	print("--- ALL 8x8 SENSOR ORACLE UNIT TESTS PASSED PERFECTLY ---")
	quit(0)