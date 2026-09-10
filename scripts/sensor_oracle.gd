class_name SensorOracle
extends Node

signal shake_started()
signal shake_progress(normalized_energy: float)
signal shake_cast_completed(wen_index: int, moving_line: int, hex_bits: int)
signal sensor_telemetry_updated(gravity: Vector3, linear_jerk: float, energy: float)

@export var enabled: bool = false
@export var shake_threshold: float = 12.0 # m/s^2 linear jerk threshold
@export var energy_to_cast: float = 24.0   # Accumulated energy to trigger cast
@export var settle_duration: float = 0.35  # Time without shake to settle

var shake_energy: float = 0.0
var last_shake_time: float = 0.0
var is_shaking: bool = false
var last_haptic_time: float = 0.0

# 64 King Wen binary-to-index lookup (bitmask: 6-bit -> King Wen #)
# Pre-populated from canonical King Wen 6-bit mapping
var king_wen_lookup: Dictionary = {}

func _ready() -> void:
	_init_lookup()

func _init_lookup() -> void:
	# Will be initialized or mapped from MandalaDial2D
	pass

func set_enabled(val: bool) -> void:
	enabled = val
	if not enabled:
		shake_energy = 0.0
		is_shaking = false

func _process(delta: float) -> void:
	if not enabled:
		return
		
	var accel: Vector3 = Input.get_accelerometer()
	var grav: Vector3 = Input.get_gravity()
	var linear: Vector3 = accel - grav
	var jerk: float = linear.length()
	var now: float = Time.get_ticks_msec() * 0.001
	
	if jerk > shake_threshold:
		shake_energy = min(shake_energy + jerk * delta * 10.0, 100.0)
		last_shake_time = now
		if not is_shaking:
			is_shaking = true
			shake_started.emit()
			
		# Progressive coin rattle haptic clicks
		if now - last_haptic_time > 0.11:
			Input.vibrate_handheld(18)
			last_haptic_time = now
			
		shake_progress.emit(clamp(shake_energy / energy_to_cast, 0.0, 1.0))
	else:
		if is_shaking:
			if now - last_shake_time > settle_duration:
				if shake_energy >= energy_to_cast:
					_execute_coin_toss_cast()
				is_shaking = false
				shake_energy = 0.0
		else:
			shake_energy = max(0.0, shake_energy - delta * 30.0)
			
	sensor_telemetry_updated.emit(grav, jerk, shake_energy)

func _execute_coin_toss_cast() -> void:
	# Authentic 3-Coin Divination Algorithm (三金錢筮法)
	# For each line (from line 1 at bottom to line 6 at top):
	# 3 coins: Heads = 3 (Yang), Tails = 2 (Yin)
	# Sum = 6 (Old Yin, ---x---, Mutating to Yang)
	# Sum = 7 (Young Yang, -------, Stable)
	# Sum = 8 (Young Yin, --- ---, Stable)
	# Sum = 9 (Old Yang, ---o---, Mutating to Yin)
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
		
	Input.vibrate_handheld(45) # Final affirmative cast haptic
	shake_cast_completed.emit(-1, primary_moving, bits)
