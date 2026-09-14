class_name FlyCentralComplex
extends RefCounted

## Central Complex 8-Wedge Ring Attractor Compass for Hexy.
## Modeled after the Drosophila Ellipsoid Body (EB) E-PG neurons and Protocerebral Bridge (PB).
##
## The 8 wedges map directly to the 8 Bagua Trigrams (45 degrees each):
##   0: 坤 Earth     (0 deg - North / Sanctuary / Stillness)
##   1: 震 Thunder   (45 deg - NE / Kinetic Surge)
##   2: 坎 Water     (90 deg - East / Battery Fluid / Depth)
##   3: 兌 Lake      (135 deg - SE / Acoustic Resonance)
##   4: 艮 Mountain  (180 deg - South / Desk Grounding / Stillness)
##   5: 離 Fire      (225 deg - SW / Solar Radiance / Heat)
##   6: 巽 Wind      (270 deg - West / Geomagnetic Flow)
##   7: 乾 Heaven    (315 deg - NW / Circadian Solar Noon / High Energy)
##
## Pure arithmetic, zero clock calls, deterministic.

const WEDGES := 8
const TAU_SLICE := TAU / float(WEDGES)  # PI/4 = 0.785398 rad (45 deg)

var activity: PackedFloat64Array
var current_heading: float = 0.0  # radians [0, TAU)

func _init() -> void:
	activity = PackedFloat64Array()
	activity.resize(WEDGES)
	# Initialize with a single stable Gaussian bump centered at wedge 0 (Earth / Kun)
	for i in range(WEDGES):
		var dist: float = absf(float(i))
		if dist > 4.0:
			dist = 8.0 - dist
		activity[i] = exp(-0.5 * (dist * dist))
	_normalize()

## Injects directional sensory currents from Hexy's 8 machine/human sensor scores.
## Shifts the internal compass bump toward external stimuli.
func inject_stimulus(scores: Array, gain: float = 1.0) -> void:
	if scores.size() < WEDGES:
		return
	var sin_sum := 0.0
	var cos_sum := 0.0
	for i in range(WEDGES):
		var stim: float = float(scores[i]) * gain
		activity[i] += stim
		var angle: float = float(i) * TAU_SLICE
		sin_sum += stim * sin(angle)
		cos_sum += stim * cos(angle)
	
	if sin_sum != 0.0 or cos_sum != 0.0:
		var stim_angle := fposmod(atan2(sin_sum, cos_sum), TAU)
		current_heading = stim_angle
	_normalize()

## Steps the ring attractor forward with lateral inhibition and slight spontaneous drift.
func step(dt_sec: float, angular_velocity: float = 0.0, drift: float = 0.01) -> void:
	# 1. Apply angular velocity shift (P-EN heading shift neurons)
	current_heading = fposmod(current_heading + angular_velocity * dt_sec + (randf_range(-1.0, 1.0) * drift * dt_sec), TAU)
	
	# 2. Recalculate bump centered around current_heading with lateral inhibition
	var target_wedge := current_heading / TAU_SLICE
	for i in range(WEDGES):
		var diff := absf(float(i) - target_wedge)
		if diff > 4.0:
			diff = 8.0 - diff
		# Local excitation + global lateral inhibition
		var target_act: float = exp(-0.8 * diff * diff) - 0.25
		activity[i] = lerpf(activity[i], maxf(target_act, 0.01), dt_sec * 4.0)
	
	_normalize()

## Returns the index of the dominant wedge (0..7).
func dominant_trigram() -> int:
	var best_idx := 0
	var best_val := -1.0
	for i in range(WEDGES):
		if activity[i] > best_val:
			best_val = activity[i]
			best_idx = i
	return best_idx

## Returns the normalized continuous angle in radians [0, TAU).
func heading_angle() -> float:
	return current_heading

## Returns heading coherence / attention sharpness in [0, 1].
## 1.0 = sharp single-target focus, 0.0 = uniform confusion.
func coherence() -> float:
	var max_v := 0.0
	var sum_v := 0.0
	for i in range(WEDGES):
		max_v = maxf(max_v, activity[i])
		sum_v += activity[i]
	if sum_v <= 0.0:
		return 0.0
	var mean_v := sum_v / float(WEDGES)
	return clampf((max_v - mean_v) / max_v, 0.0, 1.0)

## --- FAN-SHAPED BODY (FB) 2D GOAL VECTOR NAVIGATION ---
var target_heading: float = 0.0

## Sets the allocentric goal heading using an intended hexagram (1..64)
func set_target_hexagram(hex_id: int) -> void:
	var h_clamped: int = clampi(hex_id, 1, 64)
	target_heading = fposmod(float(h_clamped - 1) * (TAU / 64.0), TAU)

## Sets the allocentric goal heading using an intended trigram (0..7)
func set_target_trigram(trigram_idx: int) -> void:
	var t_clamped: int = clampi(trigram_idx, 0, 7)
	target_heading = fposmod(float(t_clamped) * TAU_SLICE, TAU)

## Returns the signed egocentric steering error in radians [-PI, PI].
## Positive = target is to the left; Negative = target is to the right.
func steering_error() -> float:
	var diff := target_heading - current_heading
	return fposmod(diff + PI, TAU) - PI

## Computes 2D vector path integration steering: Vector2(forward, turn)
func compute_steering_vector() -> Vector2:
	var err := steering_error()
	var forward: float = maxf(cos(err), 0.0)
	var turn: float = sin(err)
	return Vector2(forward, turn)

## Returns alignment with goal in [-1.0, 1.0]. (1.0 = perfectly on target)
func target_alignment() -> float:
	return cos(steering_error())

func _normalize() -> void:
	var total := 0.0
	for i in range(WEDGES):
		activity[i] = maxf(activity[i], 0.001)
		total += activity[i]
	if total > 0.0:
		for i in range(WEDGES):
			activity[i] /= total
