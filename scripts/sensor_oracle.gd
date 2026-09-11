class_name SensorOracle
extends Node

## Autonomous 8x8 Cybernetic Sensor Fusion Engine (Machine Context x Human Activity)
##
## THE 8x8 PARADIGM:
## Lower Trigram (Inner / Substrate) = 8 Machine Environmental States
## Upper Trigram (Outer / Action)    = 8 Human Activity & Habit Disciplines
## Combined: 8 x 8 = 64 King Wen Hexagrams

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

# Trigram definitions (0..7)
const TRIGRAM_NAMES: Array[String] = [
	"坤 Earth", "震 Thunder", "坎 Water", "兌 Lake",
	"艮 Mountain", "離 Fire", "巽 Wind", "乾 Heaven"
]

# 8 Machine Environmental Substrates (Lower Trigram)
const MACHINE_NAMES: Array[String] = [
	"Sanctuary (Location Stillness)",
	"Thermal/Power Surge",
	"Battery Energy Reserve",
	"Acoustic Atmosphere",
	"Surface / Desk Rest",
	"Solar Photosphere (Light)",
	"Geomagnetic Flux",
	"Circadian Solar Noon"
]

# 8 Human Habit & Activity Disciplines (Upper Trigram)
const HUMAN_NAMES: Array[String] = [
	"Sleep Hygiene (Night Rest)",
	"Locomotion (Steps & Cadence)",
	"Hydration & Metabolic Pacing",
	"Tactile Grip & Intentional Holding",
	"Deep Work (Screen-Down Focus)",
	"Active Gaze & Screen Engagement",
	"Breath & Handling Equanimity",
	"Upright Spine & Posture"
]

# Sovereign Homeostatic Anchor
var current_hex_bits: int = 0b111111 # (upper_human << 3) | lower_machine
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
var current_proximity: float = 5.0 # cm (>= 5.0 clear, < 2.5 covered)
var current_battery: float = 100.0 # %
var solar_hour: float = 12.0

# Dynamic Kinetic Excitation & Line Strain Field
var kinetic_excitation: float = 0.0
var line_strains: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var last_mutation_time: float = 0.0
const MUTATION_COOLDOWN: float = 3.5
var step_mutation_count: int = 0

# Coin Toss Divination State
var shake_energy: float = 0.0
var last_shake_time: float = 0.0
var is_shaking: bool = false
var last_haptic_time: float = 0.0

var current_machine_tri: int = 7 # Heaven
var current_human_tri: int = 7   # Heaven


func _ready() -> void:
	anchor_grav = Vector3(0.0, -9.8, 0.0)
	filtered_grav = anchor_grav
	var time_dict = Time.get_time_dict_from_system()
	solar_hour = float(time_dict.get("hour", 12)) + float(time_dict.get("minute", 0)) / 60.0
	_classify_both_trigrams()


func set_enabled(val: bool) -> void:
	enabled = val
	if not enabled:
		shake_energy = 0.0
		is_shaking = false
		kinetic_excitation = 0.0
		for i in range(6):
			line_strains[i] = 0.0


func inject_manual_state(bits: int, _moving_line: int = -1) -> void:
	current_hex_bits = bits
	anchor_hex_bits = bits
	anchor_grav = filtered_grav
	anchor_heading = current_heading_deg
	anchor_lux = current_lux
	current_machine_tri = bits & 0x07
	current_human_tri = (bits >> 3) & 0x07
	kinetic_excitation = 0.0
	for i in range(6):
		line_strains[i] = 0.0
	last_mutation_time = Time.get_ticks_msec() * 0.001 + 2.5


func _process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	
	# 1. Raw sensor acquisition & smoothing
	var raw_acc: Vector3 = Input.get_accelerometer()
	var raw_grav: Vector3 = Input.get_gravity()
	var raw_gyro: Vector3 = Input.get_gyroscope()
	var raw_mag: Vector3 = Input.get_magnetometer()
	
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
	
	if filtered_mag.length_squared() > 0.01:
		var heading_rad: float = atan2(-filtered_mag.x, -filtered_mag.y)
		current_heading_deg = posmod(rad_to_deg(heading_rad), 360.0)
		
	_sample_hardware_extensions()
	
	var time_dict = Time.get_time_dict_from_system()
	solar_hour = float(time_dict.get("hour", 12)) + float(time_dict.get("minute", 0)) / 60.0

	# 2. Coin toss divination
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

	# 3. Classify Machine and Human Trigrams
	_classify_both_trigrams()

	# 4. Sensor mode line strain & autonomous mutation
	if not enabled:
		sensor_telemetry_updated.emit(filtered_grav, current_heading_deg, filtered_jerk, current_machine_tri, current_human_tri)
		return

	_update_habit_line_strains(delta)
	sensor_telemetry_updated.emit(filtered_grav, current_heading_deg, filtered_jerk, current_machine_tri, current_human_tri)

	# Mutate towards the classified 8x8 state when excitation peaks
	if kinetic_excitation >= 0.90 and (now - last_mutation_time >= MUTATION_COOLDOWN):
		var target_bits: int = (current_human_tri << 3) | current_machine_tri
		if target_bits != current_hex_bits:
			var diff: int = current_hex_bits ^ target_bits
			# Flip lowest differing bit (Hamming d=1 step)
			var bit_to_flip: int = 0
			for b in range(6):
				if ((diff >> b) & 1) == 1:
					bit_to_flip = b
					break
			
			current_hex_bits ^= (1 << bit_to_flip)
			anchor_hex_bits = current_hex_bits
			anchor_grav = filtered_grav
			anchor_heading = current_heading_deg
			anchor_lux = current_lux
			kinetic_excitation = 0.0
			last_mutation_time = now
			step_mutation_count += 1
			
			var is_yang: bool = ((current_hex_bits >> bit_to_flip) & 1) == 1
			var line_names: Array[String] = ["Body", "Food", "Breath", "Rest", "Focus", "Connection"]
			var reason: String = "8x8 Synergy: Line %d (%s) ➔ %s" % [
				bit_to_flip + 1,
				line_names[bit_to_flip],
				"Ignited into Yang ⚊" if is_yang else "Yielded into Yin ⚋"
			]
			Input.vibrate_handheld(20)
			autonomous_mutation_stepped.emit(current_hex_bits, bit_to_flip, reason)


func _classify_both_trigrams() -> void:
	current_machine_tri = _classify_machine_trigram()
	current_human_tri = _classify_human_trigram()


func _classify_machine_trigram() -> int:
	# Machine Substrate Classification:
	# 4 Mountain: Desk / Surface rest
	var is_desk_flat: bool = (abs(filtered_grav.z) > 8.0 or abs(filtered_grav.y) > 9.0) and filtered_jerk < 0.12 and filtered_gyro.length() < 0.08
	if is_desk_flat and current_proximity >= 3.0:
		return 4 # Mountain (Desk Rest)
		
	# 5 Fire: Open Sunlight / Bright Photosphere
	if current_lux > 3500.0:
		return 5 # Fire (Photosphere)
		
	# 2 Water: Battery Reserve Depleted
	if current_battery < 25.0:
		return 2 # Water (Energy Depth)
		
	# 0 Earth: Night / Dark Dormancy
	if (solar_hour >= 23.0 or solar_hour < 5.5) and current_lux < 20.0:
		return 0 # Earth (Sanctuary)
		
	# 7 Heaven: Solar Noon Apex
	if solar_hour >= 11.0 and solar_hour <= 14.5 and current_lux > 400.0:
		return 7 # Heaven (Solar Peak)
		
	# 6 Wind: Strong Geomagnetic Alignment
	if current_heading_deg < 30.0 or current_heading_deg > 330.0 or (current_heading_deg > 150.0 and current_heading_deg < 210.0):
		return 6 # Wind (Planetary Flux)
		
	# 3 Lake: Open Ambient Atmosphere
	if current_lux > 150.0:
		return 3 # Lake (Atmosphere)
		
	# 1 Thunder: Electrical / Power Excitation
	return 1 # Thunder (Surge)


func _classify_human_trigram() -> int:
	# Human Habit & Activity Classification:
	# 4 Mountain: Deep Work Screen-Down Eclipse
	var is_screen_down: bool = (filtered_grav.z < -7.0 and current_proximity < 2.5)
	if is_screen_down:
		return 4 # Mountain (Deep Work Focus)
		
	# 1 Thunder: Locomotion / Cadence / Steps
	var is_moving: bool = (filtered_jerk > 2.5 or kinetic_excitation > 0.45)
	if is_moving:
		return 1 # Thunder (Locomotion Steps)
		
	# 7 Heaven: Upright Spine & Alert Vertical Posture
	var is_upright: bool = (filtered_grav.y < -7.5 and abs(filtered_grav.z) < 4.8)
	if is_upright:
		return 7 # Heaven (Upright Posture)
		
	# 0 Earth: Sleep Stillness
	if (solar_hour >= 22.5 or solar_hour < 6.0) and filtered_jerk < 0.15:
		return 0 # Earth (Sleep Rest)
		
	# 6 Wind: Breath & Handling Equanimity (Smooth, low gyro jitter)
	var is_calm_held: bool = (filtered_gyro.length() < 0.22 and not is_screen_down)
	if is_calm_held and is_upright:
		return 6 # Wind (Breath Equanimity)
		
	# 5 Fire: Active Visual Screen Focus
	if current_proximity >= 4.0 and abs(filtered_grav.z) > 3.0:
		return 5 # Fire (Active Screen Gaze)
		
	# 3 Lake: Intentional Tactile Holding
	if filtered_gyro.length() > 0.1:
		return 3 # Lake (Tactile Contact)
		
	# 2 Water: Metabolic Nutrition / Rest Window
	return 2 # Water (Metabolic Pacing)


func _update_habit_line_strains(delta: float) -> void:
	# Strain accumulation towards habit disciplines:
	# L1: Body (Movement)
	line_strains[0] = lerp(line_strains[0], clamp(filtered_jerk / 6.0, 0.0, 1.0), delta * 3.0)
	# L2: Food / Battery
	line_strains[1] = lerp(line_strains[1], clamp((100.0 - current_battery) / 80.0, 0.0, 1.0), delta * 2.0)
	# L3: Breath (Gyro smoothness)
	line_strains[2] = lerp(line_strains[2], clamp(filtered_gyro.length() / 2.0, 0.0, 1.0), delta * 4.0)
	# L4: Rest (Night darkness)
	var night_factor: float = 1.0 if (solar_hour >= 23.0 or solar_hour < 6.0) else 0.0
	line_strains[3] = lerp(line_strains[3], night_factor, delta * 3.0)
	# L5: Focus (Screen-down)
	var focus_factor: float = 1.0 if (filtered_grav.z < -7.0 and current_proximity < 2.5) else 0.0
	line_strains[4] = lerp(line_strains[4], focus_factor, delta * 4.0)
	# L6: Connection (Heading alignment)
	var heading_flux: float = abs(sin(deg_to_rad(current_heading_deg)))
	line_strains[5] = lerp(line_strains[5], heading_flux, delta * 2.0)
	
	var total_flux: float = float(line_strains[0] + line_strains[2] + line_strains[4]) * 0.4
	if total_flux > 0.25:
		kinetic_excitation = min(1.0, kinetic_excitation + total_flux * delta * 0.45)
	else:
		kinetic_excitation = max(0.0, kinetic_excitation - delta * 0.40)


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
		"lower_trigram": current_machine_tri,
		"upper_trigram": current_human_tri,
		"machine_trigram": current_machine_tri,
		"human_trigram": current_human_tri,
		"machine_name": MACHINE_NAMES[current_machine_tri],
		"human_name": HUMAN_NAMES[current_human_tri],
		"candidate_trigram": current_machine_tri,
		"current_bits": current_hex_bits,
		"candidate_bits": current_hex_bits,
		"is_shaking": is_shaking
	}
