class_name SensorOracle
extends Node

## Hexy Autonomous Sensor Fusion & Coherence Engine
## Tier 1: Afferent Sensor Fusion (Kalman/EMA filter for Gravity, Accel, Gyro, Mag)
## Tier 2: Ba-Gua Topological Manifold (Spherical Voronoi Gravity -> Lower Trigram, Heading -> Upper Trigram)
## Tier 3: Temporal Coherence & Hysteresis (Schmitt Trigger + Hamming Distance d=1 walk)
## Tier 4: Tensegrity Equilibrium Coupling & Autonomous MNN Thought Trigger

signal shake_started()
signal shake_progress(normalized_energy: float)
signal shake_cast_completed(wen_index: int, moving_line: int, hex_bits: int)
signal autonomous_mutation_stepped(new_bits: int, moving_line: int, reason: String)
signal autonomous_thought_requested(prompt: String)
signal sensor_telemetry_updated(gravity: Vector3, heading: float, energy: float, lower_tri: int, upper_tri: int)

@export var enabled: bool = false
@export var shake_threshold: float = 13.0 # m/s^2 linear jerk threshold
@export var energy_to_cast: float = 24.0   # Accumulated energy for intentional shake cast
@export var settle_duration: float = 0.35  # Settle time for shake cast

# Afferent Filtered State (Tier 1)
var filtered_grav: Vector3 = Vector3(0.0, -9.8, 0.0)
var filtered_mag: Vector3 = Vector3(0.0, 0.0, -1.0)
var filtered_gyro: Vector3 = Vector3.ZERO
var filtered_jerk: float = 0.0
var current_heading_deg: float = 0.0

# Hysteresis & State Coherence (Tier 3)
var current_hex_bits: int = 0b111111 # Hexagram 1 (The Creative)
var candidate_hex_bits: int = 0b111111
var candidate_dwell_time: float = 0.0
const DWELL_THRESHOLD: float = 0.55 # Must dwell in sector for 0.55s
const MUTATION_COOLDOWN: float = 1.0 # Min cooldown between autonomous line steps
var last_mutation_time: float = 0.0
var step_mutation_count: int = 0

# Shake Divination State
var shake_energy: float = 0.0
var last_shake_time: float = 0.0
var is_shaking: bool = false
var last_haptic_time: float = 0.0

# Trigram metadata: 0=Earth (坤), 1=Thunder (震), 2=Water (坎), 3=Lake (兌), 4=Mountain (艮), 5=Fire (離), 6=Wind (巽), 7=Heaven (乾)
const TRIGRAM_NAMES: Array[String] = ["坤 Earth", "震 Thunder", "坎 Water", "兌 Lake", "艮 Mountain", "離 Fire", "巽 Wind", "乾 Heaven"]
const TRIGRAM_SYMBOLS: Array[String] = ["☷", "☳", "☵", "☱", "☶", "☲", "☴", "☰"]

func set_enabled(val: bool) -> void:
	enabled = val
	if not enabled:
		shake_energy = 0.0
		is_shaking = false
		candidate_dwell_time = 0.0

func _process(delta: float) -> void:
	if not enabled:
		return
		
	var now: float = Time.get_ticks_msec() * 0.001
	
	# --- TIER 1: AFFERENT SENSOR FUSION & FILTERING ---
	var raw_acc: Vector3 = Input.get_accelerometer()
	var raw_grav: Vector3 = Input.get_gravity()
	var raw_gyro: Vector3 = Input.get_gyroscope()
	var raw_mag: Vector3 = Input.get_magnetometer()
	
	# Exponential Moving Average (alpha=0.15 for smooth gravity, alpha=0.35 for dynamic response)
	if raw_grav.length_squared() > 1.0:
		filtered_grav = filtered_grav.lerp(raw_grav, delta * 8.0)
	else:
		filtered_grav = filtered_grav.lerp(Vector3(0.0, -9.8, 0.0), delta * 2.0)
		
	filtered_gyro = filtered_gyro.lerp(raw_gyro, delta * 12.0)
	if raw_mag.length_squared() > 1.0:
		filtered_mag = filtered_mag.lerp(raw_mag, delta * 5.0)
		
	var linear_vec: Vector3 = raw_acc - filtered_grav
	var jerk: float = linear_vec.length()
	filtered_jerk = lerp(filtered_jerk, jerk, delta * 10.0)
	
	# Compute Azimuth Heading (Compass)
	if filtered_mag.length_squared() > 0.01:
		var heading_rad: float = atan2(-filtered_mag.x, -filtered_mag.y)
		current_heading_deg = posmod(rad_to_deg(heading_rad), 360.0)
		
	# --- INTENTIONAL SHAKE DETECTION (Coins divination) ---
	if jerk > shake_threshold:
		shake_energy = min(shake_energy + jerk * delta * 10.0, 100.0)
		last_shake_time = now
		if not is_shaking:
			is_shaking = true
			shake_started.emit()
			
		if now - last_haptic_time > 0.11:
			Input.vibrate_handheld(18)
			last_haptic_time = now
			
		shake_progress.emit(clamp(shake_energy / energy_to_cast, 0.0, 1.0))
		return
	elif is_shaking:
		if now - last_shake_time > settle_duration:
			if shake_energy >= energy_to_cast:
				_execute_coin_toss_cast()
			is_shaking = false
			shake_energy = 0.0
		return
	else:
		shake_energy = max(0.0, shake_energy - delta * 25.0)
		
	# --- TIER 2: BA-GUA TOPOLOGICAL MANIFOLD CLASSIFICATION ---
	var lower_tri: int = _classify_lower_trigram_from_gravity(filtered_grav)
	var upper_tri: int = _classify_upper_trigram_from_heading(current_heading_deg)
	var raw_hex_bits: int = (upper_tri << 3) | (lower_tri & 0x07)
	
	sensor_telemetry_updated.emit(filtered_grav, current_heading_deg, filtered_jerk, lower_tri, upper_tri)
	
	# --- TIER 3: TEMPORAL COHERENCE & HYSTERESIS ---
	if raw_hex_bits == candidate_hex_bits:
		candidate_dwell_time += delta
	else:
		candidate_hex_bits = raw_hex_bits
		candidate_dwell_time = 0.0
		
	# Check if candidate has dwelled steadily beyond threshold and cooldown elapsed
	if candidate_dwell_time >= DWELL_THRESHOLD and (now - last_mutation_time >= MUTATION_COOLDOWN):
		if current_hex_bits != candidate_hex_bits:
			# HAMMING DISTANCE d=1 CONSTRAINT:
			# Mutate exactly one line at a time towards candidate
			var diff_mask: int = current_hex_bits ^ candidate_hex_bits
			var line_to_flip: int = -1
			for b in range(6):
				if ((diff_mask >> b) & 1) == 1:
					line_to_flip = b
					break
					
			if line_to_flip >= 0:
				current_hex_bits ^= (1 << line_to_flip)
				last_mutation_time = now
				candidate_dwell_time = 0.0 # reset dwell for next line step
				step_mutation_count += 1
				
				var is_now_yang: bool = ((current_hex_bits >> line_to_flip) & 1) == 1
				var reason: String = "Posture: %s | Azimuth: %s ➔ Line %d %s" % [
					TRIGRAM_NAMES[lower_tri],
					TRIGRAM_NAMES[upper_tri],
					line_to_flip + 1,
					"Igniting into Yang" if is_now_yang else "Yielding into Yin"
				]
				
				Input.vibrate_handheld(15) # Gentle tactile line mutation feedback
				autonomous_mutation_stepped.emit(current_hex_bits, line_to_flip, reason)
				
				# If settled after multiple steps, request spontaneous MNN thought
				if step_mutation_count >= 3:
					step_mutation_count = 0
					var prompt: String = "In one evocative sentence, reflect as the I-Ching on mutating into Hexagram binary 0b%06s through physical stillness and balance." % String.num_int64(current_hex_bits, 2).pad_zeros(6)
					autonomous_thought_requested.emit(prompt)

func _classify_lower_trigram_from_gravity(g: Vector3) -> int:
	# Spherical Voronoi Posture Classification
	# g: (gx, gy, gz) in m/s^2. Earth gravity is ~ 9.8.
	# Phone flat on back (screen up): gz ~ +9.8 -> 000 Earth (坤)
	if g.z > 6.5:
		return 0 # 坤 Earth
	# Phone upright portrait: gy ~ -9.8 -> 111 Heaven (乾)
	if g.y < -6.5:
		return 7 # 乾 Heaven
	# Phone face down: gz ~ -6.5 -> 100 Mountain (艮)
	if g.z < -5.5:
		return 4 # 艮 Mountain
	# Phone upside down: gy ~ +6.5 -> 011 Lake (兌)
	if g.y > 5.5:
		return 3 # 兌 Lake
	# Phone tilted left (landscape left): gx ~ -5.0 -> 001 Thunder (震)
	if g.x < -4.0:
		return 1 # 震 Thunder
	# Phone tilted right: gx ~ +5.0 -> 110 Wind (巽)
	if g.x > 4.0:
		return 6 # 巽 Wind
	# Pitched forward (leaning away): -> 010 Water (坎)
	if g.z < -2.0 and g.y < -2.0:
		return 2 # 坎 Water
	# Pitched back (leaning toward user): -> 101 Fire (離)
	if g.z > 2.0 and g.y < -2.0:
		return 5 # 離 Fire
		
	return 7 # Default Heaven if upright tilt

func _classify_upper_trigram_from_heading(heading_deg: float) -> int:
	# Later Heaven (King Wen) Compass Rose Cardinal Mapping:
	# Sector angle = 45 degrees per trigram (centered at each cardinal/intercardinal)
	var norm_deg: float = posmod(heading_deg + 22.5, 360.0)
	var sector: int = int(norm_deg / 45.0)
	match sector:
		0: return 2 # North: 坎 Water
		1: return 4 # North-East: 艮 Mountain
		2: return 1 # East: 震 Thunder
		3: return 6 # South-East: 巽 Wind
		4: return 5 # South: 離 Fire
		5: return 0 # South-West: 坤 Earth
		6: return 3 # West: 兌 Lake
		7: return 7 # North-West: 乾 Heaven
	return 5 # Default South Fire

func _execute_coin_toss_cast() -> void:
	# Classical 3-Coin Divination Algorithm
	var bits: int = 0
	var moving_lines: Array[int] = []
	for line in range(6):
		var coin1: int = 3 if randf() > 0.5 else 2
		var coin2: int = 3 if randf() > 0.5 else 2
		var coin3: int = 3 if randf() > 0.5 else 2
		var sum: int = coin1 + coin2 + coin3
		var is_yang: bool = (sum == 7 or sum == 9)
		if is_yang:
			bits |= (1 << line)
		if sum == 6 or sum == 9:
			moving_lines.append(line)
			
	var primary_moving: int = -1
	if moving_lines.size() > 0:
		primary_moving = moving_lines[randi() % moving_lines.size()]
		
	current_hex_bits = bits
	candidate_hex_bits = bits
	candidate_dwell_time = 0.0
	step_mutation_count = 0
	
	Input.vibrate_handheld(45) # Final affirmative cast haptic
	shake_cast_completed.emit(-1, primary_moving, bits)

func get_telemetry_snapshot() -> Dictionary:
	var l_tri: int = _classify_lower_trigram_from_gravity(filtered_grav)
	var u_tri: int = _classify_upper_trigram_from_heading(current_heading_deg)
	var cand_l_tri: int = candidate_hex_bits & 0b111
	return {
		"gravity": filtered_grav,
		"gyro": filtered_gyro,
		"heading": current_heading_deg,
		"jerk": filtered_jerk,
		"shake_energy": shake_energy,
		"shake_progress": clamp(shake_energy / energy_to_cast, 0.0, 1.0),
		"dwell_progress": clamp(candidate_dwell_time / DWELL_THRESHOLD, 0.0, 1.0),
		"lower_trigram": l_tri,
		"upper_trigram": u_tri,
		"candidate_trigram": cand_l_tri,
		"current_bits": current_hex_bits,
		"candidate_bits": candidate_hex_bits,
		"is_shaking": is_shaking
	}
