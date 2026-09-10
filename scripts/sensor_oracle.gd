class_name SensorOracle
extends Node

## Autonomous Cybernetic Sensor Fusion & Dynamic Line Strain Engine
## Integrates multi-modal afferent telemetry from hardware:
## - 3D Inclinometer / Accelerometer (Tilt strain on lower lines)
## - Tri-Axis Gyroscope (Kinetic perturbation & whirlpool flux)
## - 3D Geomagnetic Magnetometer (Azimuth heading & polar strain)
## - Ambient Light Sensor (Solar illuminance & twilight flare)
## - Infrared Proximity Sensor (Occultation / Palm eclipse hover)
## - Battery State & Diurnal Chronos (Vitality metabolism & solar hour)
## - Kinetic Jerk (Coin divination reservoir)
##
## Cybernetic Principle:
## Manual intent (dialing or casting) establishes the sovereign equilibrium anchor.
## Physical stillness preserves the chosen hexagram indefinitely (no static angle traps).
## Sustained physical gestures accumulate line strain, mutating one line at a time (d=1 Hamming).

signal shake_started()
signal shake_progress(progress: float)
signal shake_cast_completed(wen: int, moving_line: int, bits: int)
signal autonomous_mutation_stepped(new_bits: int, moving_line: int, reason: String)
signal autonomous_thought_requested(prompt: String)
signal sensor_telemetry_updated(grav: Vector3, heading: float, jerk: float, lower: int, upper: int)

@export var enabled: bool = false
@export var shake_threshold: float = 18.0
@export var energy_to_cast: float = 85.0
@export var settle_duration: float = 0.55

# Sovereign Homeostatic Anchor
var current_hex_bits: int = 0b111111 # Manifested Hexagram bits (0..63)
var anchor_hex_bits: int = 0b111111
var anchor_grav: Vector3 = Vector3(0.0, -9.8, 0.0)
var anchor_heading: float = 0.0
var anchor_lux: float = 250.0

# Filtered Afferent Sensor Telemetry
var filtered_grav: Vector3 = Vector3(0.0, -9.8, 0.0)
var filtered_gyro: Vector3 = Vector3.ZERO
var filtered_mag: Vector3 = Vector3.ZERO
var filtered_jerk: float = 0.0
var current_heading_deg: float = 0.0
var current_lux: float = 250.0
var current_proximity: float = 5.0 # cm (>= 5.0 is clear, < 3.0 is covered/eclipse)
var current_battery: float = 100.0 # percentage
var solar_hour: float = 12.0

# Dynamic Kinetic Excitation & Line Strain Field
var kinetic_excitation: float = 0.0 # 0.0 (stillness) to 1.0 (mutation threshold)
var line_strains: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var last_mutation_time: float = 0.0
const MUTATION_COOLDOWN: float = 3.5 # Minimum seconds between autonomous line mutations
var step_mutation_count: int = 0

# Coin Toss Divination State
var shake_energy: float = 0.0
var last_shake_time: float = 0.0
var is_shaking: bool = false
var last_haptic_time: float = 0.0

# Trigram metadata
const TRIGRAM_NAMES: Array[String] = ["坤 Earth", "震 Thunder", "坎 Water", "兌 Lake", "艮 Mountain", "離 Fire", "巽 Wind", "乾 Heaven"]

func _ready() -> void:
	anchor_grav = Vector3(0.0, -9.8, 0.0)
	filtered_grav = anchor_grav
	var time_dict = Time.get_time_dict_from_system()
	solar_hour = float(time_dict.get("hour", 12)) + float(time_dict.get("minute", 0)) / 60.0

func set_enabled(val: bool) -> void:
	enabled = val
	if not enabled:
		shake_energy = 0.0
		is_shaking = false
		kinetic_excitation = 0.0
		for i in range(6):
			line_strains[i] = 0.0

func inject_manual_state(bits: int, _moving_line: int = -1) -> void:
	## Ingests manual user intention as sovereign equilibrium anchor
	current_hex_bits = bits
	anchor_hex_bits = bits
	anchor_grav = filtered_grav
	anchor_heading = current_heading_deg
	anchor_lux = current_lux
	kinetic_excitation = 0.0
	for i in range(6):
		line_strains[i] = 0.0
	last_mutation_time = Time.get_ticks_msec() * 0.001 + 2.5 # Grace cooldown after user interaction

func _process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	
	# --- TIER 1: MULTI-MODAL AFFERENT SENSOR ACQUISITION ---
	var raw_acc: Vector3 = Input.get_accelerometer()
	var raw_grav: Vector3 = Input.get_gravity()
	var raw_gyro: Vector3 = Input.get_gyroscope()
	var raw_mag: Vector3 = Input.get_magnetometer()
	
	# Gravity filtering
	if raw_grav.length_squared() > 1.0:
		filtered_grav = filtered_grav.lerp(raw_grav, delta * 8.0)
	elif raw_acc.length_squared() > 1.0:
		filtered_grav = filtered_grav.lerp(raw_acc, delta * 2.0)
		
	filtered_gyro = filtered_gyro.lerp(raw_gyro, delta * 12.0)
	if raw_mag.length_squared() > 1.0:
		filtered_mag = filtered_mag.lerp(raw_mag, delta * 5.0)
		
	var linear_vec: Vector3 = raw_acc - filtered_grav
	var jerk: float = linear_vec.length()
	filtered_jerk = lerp(filtered_jerk, jerk, delta * 10.0)
	
	# Azimuth Heading
	if filtered_mag.length_squared() > 0.01:
		var heading_rad: float = atan2(-filtered_mag.x, -filtered_mag.y)
		current_heading_deg = posmod(rad_to_deg(heading_rad), 360.0)
		
	# Hardware Light, Proximity & Battery from Android Plugin (with graceful fallbacks)
	_sample_hardware_extensions()
	
	# Local Solar Time
	var time_dict = Time.get_time_dict_from_system()
	solar_hour = float(time_dict.get("hour", 12)) + float(time_dict.get("minute", 0)) / 60.0

	# --- TIER 2: COIN TOSS DIVINATION (Vigorous intentional shaking) ---
	if jerk > shake_threshold:
		shake_energy = min(shake_energy + jerk * delta * 12.0, 100.0)
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

	if not enabled:
		return

	# --- TIER 3: DYNAMIC PERTURBATION & RELATIVE FLUX ---
	var delta_grav: Vector3 = filtered_grav - anchor_grav
	var tilt_pitch: float = abs(delta_grav.y) + abs(delta_grav.z)
	var tilt_roll: float = abs(delta_grav.x)
	var gyro_speed: float = filtered_gyro.length()
	var d_heading: float = abs(angle_difference(deg_to_rad(current_heading_deg), deg_to_rad(anchor_heading)))
	var is_eclipse: bool = (current_proximity >= 0.0 and current_proximity < 3.5)
	var delta_lux: float = abs(current_lux - anchor_lux)
	
	# Overall physical movement flux
	var kinetic_flux: float = (
		tilt_pitch * 0.15 +
		tilt_roll * 0.18 +
		gyro_speed * 0.25 +
		d_heading * 0.35 +
		jerk * 0.08 +
		(1.2 if is_eclipse else 0.0)
	)
	
	# Homeostatic excitation / cooling:
	if kinetic_flux > 0.35:
		kinetic_excitation = min(1.0, kinetic_excitation + kinetic_flux * delta * 0.35)
	else:
		kinetic_excitation = max(0.0, kinetic_excitation - delta * 0.5)
		
	# Distribute strain across the 6 lines:
	line_strains[0] = lerp(line_strains[0], clamp(jerk / 8.0, 0.0, 1.0), delta * 3.0)
	line_strains[1] = lerp(line_strains[1], clamp(tilt_pitch / 4.0, 0.0, 1.0), delta * 4.0)
	line_strains[2] = lerp(line_strains[2], clamp(tilt_roll / 3.5, 0.0, 1.0), delta * 4.0)
	line_strains[3] = lerp(line_strains[3], 1.0 if is_eclipse else 0.0, delta * 5.0)
	line_strains[4] = lerp(line_strains[4], clamp(delta_lux / 250.0, 0.0, 1.0), delta * 3.0)
	line_strains[5] = lerp(line_strains[5], clamp(d_heading / 0.8, 0.0, 1.0), delta * 3.0)
	
	var lower_tri: int = current_hex_bits & 0x07
	var upper_tri: int = (current_hex_bits >> 3) & 0x07
	sensor_telemetry_updated.emit(filtered_grav, current_heading_deg, filtered_jerk, lower_tri, upper_tri)

	# --- TIER 4: HAMMING d=1 MUTATION ON HIGH STRAIN ---
	if kinetic_excitation >= 0.92 and (now - last_mutation_time >= MUTATION_COOLDOWN):
		var max_strain: float = -1.0
		var line_to_flip: int = -1
		for i in range(6):
			if line_strains[i] > max_strain:
				max_strain = line_strains[i]
				line_to_flip = i
				
		if line_to_flip >= 0 and max_strain > 0.35:
			current_hex_bits ^= (1 << line_to_flip)
			anchor_hex_bits = current_hex_bits
			anchor_grav = filtered_grav
			anchor_heading = current_heading_deg
			anchor_lux = current_lux
			kinetic_excitation = 0.0
			for i in range(6):
				line_strains[i] = 0.0
			last_mutation_time = now
			step_mutation_count += 1
			
			var is_yang: bool = ((current_hex_bits >> line_to_flip) & 1) == 1
			var strain_reasons: Array[String] = [
				"Kinetic Impact / Jerk",
				"Pitch Tilt / Gravitational Incline",
				"Roll Tilt / Lateral Horizon",
				"Occultation / Palm Eclipse",
				"Celestial Lux Flux",
				"Geomagnetic Azimuth Turning"
			]
			var reason: String = "Physical Strain: %s ➔ Line %d %s" % [
				strain_reasons[line_to_flip],
				line_to_flip + 1,
				"Ignited into Yang ⚊" if is_yang else "Yielded into Yin ⚋"
			]
			
			Input.vibrate_handheld(20)
			autonomous_mutation_stepped.emit(current_hex_bits, line_to_flip, reason)
			
			if step_mutation_count >= 3:
				step_mutation_count = 0
				var prompt: String = "In one evocative sentence, reflect as the I-Ching on mutating into Hexagram binary 0b%06s through physical stillness and balance." % String.num_int64(current_hex_bits, 2).pad_zeros(6)
				autonomous_thought_requested.emit(prompt)

func _sample_hardware_extensions() -> void:
	if Engine.has_singleton("IxMnn"):
		var mnn = Engine.get_singleton("IxMnn")
		if mnn:
			if mnn.has_method("get_ambient_lux"):
				var lux_val: float = mnn.get_ambient_lux()
				if lux_val >= 0.0:
					current_lux = lerp(current_lux, lux_val, 0.15)
			if mnn.has_method("get_proximity"):
				var prox: float = mnn.get_proximity()
				if prox >= 0.0:
					current_proximity = prox
			if mnn.has_method("get_battery_level"):
				var bat: float = mnn.get_battery_level()
				if bat >= 0.0:
					current_battery = bat

func _execute_coin_toss_cast() -> void:
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
		
	inject_manual_state(bits, primary_moving)
	step_mutation_count = 0
	
	Input.vibrate_handheld(45)
	shake_cast_completed.emit(-1, primary_moving, bits)

func get_telemetry_snapshot() -> Dictionary:
	return {
		"gravity": filtered_grav,
		"gyro": filtered_gyro,
		"heading": current_heading_deg,
		"jerk": filtered_jerk,
		"lux": current_lux,
		"proximity": current_proximity,
		"battery": current_battery,
		"solar_hour": solar_hour,
		"kinetic_excitation": kinetic_excitation,
		"line_strains": line_strains.duplicate(),
		"shake_energy": shake_energy,
		"shake_progress": clamp(shake_energy / energy_to_cast, 0.0, 1.0),
		"dwell_progress": kinetic_excitation,
		"lower_trigram": current_hex_bits & 0x07,
		"upper_trigram": (current_hex_bits >> 3) & 0x07,
		"candidate_trigram": current_hex_bits & 0x07,
		"current_bits": current_hex_bits,
		"candidate_bits": current_hex_bits,
		"is_shaking": is_shaking
	}