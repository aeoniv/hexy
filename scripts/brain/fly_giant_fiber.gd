class_name FlyGiantFiber
extends RefCounted

## DROSOPHILA GIANT FIBER (GF) ESCAPE & SHOCK REFLEX
##
## Models the fastest escape reflex in the insect nervous system (~5 ms latency).
## In Drosophila, the Giant Fiber neuron fires an explosive motor override when:
##   1. Looming shadow / Freefall occurs (loss of gravitational anchor).
##   2. Violent mechanical shock / impact occurs.
##
## In Hexy, when triggered:
##   - Overrides 3D tensegrity dynamics to instantly curl struts into a protective ball.
##   - Spikes Octopamine (Flight Arousal) and suppresses motor relaxation.
##   - Decays exponentially back to calm equilibrium over a 2.0s refractory period.

signal startled(intensity: float, reason: String)
signal recovered()

# Thresholds in SI units (m/s²)
const FREEFALL_THRESHOLD := 2.0     # Near 0g freefall
const SHOCK_THRESHOLD := 25.0       # > 2.5g sudden impact
const JERK_THRESHOLD := 90.0        # Rate of acceleration change (m/s³)

var is_startled: bool = false
var startle_intensity: float = 0.0
var recovery_time_sec: float = 2.0
var _last_accel: Vector3 = Vector3(0.0, -9.8, 0.0)


## Evaluates 3-axis accelerometer and steps recovery decay
func step(dt_sec: float, current_accel: Vector3) -> float:
	var accel_mag := current_accel.length()
	var jerk: float = (current_accel - _last_accel).length() / maxf(dt_sec, 0.001)
	_last_accel = current_accel
	
	var freshly_triggered := false
	# 1. Check for Freefall drop (0g state)
	if accel_mag < FREEFALL_THRESHOLD:
		_trigger_startle(1.0, "freefall_drop")
		freshly_triggered = true
	# 2. Check for Violent mechanical shock or high jerk
	elif accel_mag > SHOCK_THRESHOLD or jerk > JERK_THRESHOLD:
		var intensity: float = clampf(accel_mag / (SHOCK_THRESHOLD * 1.5), 0.5, 1.0)
		_trigger_startle(intensity, "mechanical_shock")
		freshly_triggered = true
	
	# 3. Exponential relaxation back to baseline (on subsequent frames)
	if is_startled and not freshly_triggered:
		startle_intensity = move_toward(startle_intensity, 0.0, dt_sec / recovery_time_sec)
		if startle_intensity <= 0.001:
			is_startled = false
			startle_intensity = 0.0
			recovered.emit()
			
	return startle_intensity


func _trigger_startle(intensity: float, reason: String) -> void:
	if not is_startled or intensity > startle_intensity:
		is_startled = true
		startle_intensity = intensity
		startled.emit(startle_intensity, reason)


## Returns structural curl factor for 3D Tensegrity (0.0 = normal, 1.0 = fully curled)
func get_curl_factor() -> float:
	return startle_intensity
