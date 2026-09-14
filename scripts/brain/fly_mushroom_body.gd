class_name FlyMushroomBody
extends RefCounted

## DROSOPHILA MUSHROOM BODY (MB) ASSOCIATIVE HABIT CIRCUIT
##
## Models the learning and episodic memory center of Drosophila melanogaster:
##   - 256 Kenyon Cells (KCs): Sparse high-dimensional projection of sensory state (LSH).
##   - Dopaminergic Neurons (DANs): Teach / reinforcement signal (valence).
##   - Mushroom Body Output Neurons (MBONs): Drive approach / avoid valence.
##
## Implements online Hebbian learning:
##   ΔW = η · x_KC · r_DAN
##
## Enables Hexy to learn and anticipate personal daily routines (e.g. 9:00 AM desk focus)
## without cloud storage or heavyweight neural networks (< 50 KB RAM).

const NUM_INPUTS := 16     # 16 Cybernetic Senses (8 Machine x 8 Human)
const NUM_KCS := 256       # Kenyon Cells (Sparse Binary Hash)
const SPARSITY := 16       # Top-K active KCs per pattern (6.25% firing rate)
const NUM_OUTPUTS := 6     # Biases for the 6 Needs / Q6 Lines

## The projection seed lives on disk so the same context lands on the same
## Kenyon cells tomorrow. Written once, on first run, and read ever after.
const SEED_PATH := "user://fly_mb_seed.json"
const DEFAULT_SEED := 0x64_46_46_42  # "FFB", the seed this circuit was born with

## Sleep pruning: fraction of a weight shed per second of fully permitted sleep.
const DECAY_PER_SEC := 0.002

# Fixed random projection matrix for Locality-Sensitive Hashing (LSH)
# Generated deterministically via fixed seed
var _proj_weights: Array = []

# Associative synaptic weight matrix: W[output_idx][kc_idx]
# Positive = Approach / Facilitate; Negative = Suppress
var _weights: Array = []

# Active Kenyon Cell indices for current state
var active_kcs: PackedInt32Array = PackedInt32Array()

# Binary 256-bit hash of the current context (packed into 8 x 32-bit ints)
var context_hash: PackedInt32Array = PackedInt32Array()

# Learning rate for Hebbian consolidation
var learning_rate: float = 0.05

## The seed the KC projection was drawn from. Stable per install.
var seed: int = DEFAULT_SEED


func _init(p_seed: int = -1) -> void:
	seed = install_seed() if p_seed < 0 else p_seed
	_init_projection_matrix()
	_init_synaptic_weights()
	context_hash.resize(8)
	context_hash.fill(0)


## Initializes deterministic pseudo-random projection matrix (16 inputs -> 256 KCs)
func _init_projection_matrix() -> void:
	_proj_weights.clear()
	# Deterministic LCG seed to ensure byte-for-byte reproducibility
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	
	for kc in range(NUM_KCS):
		var row: Array = []
		for inp in range(NUM_INPUTS):
			# Sparse ternary projection: {-1, 0, 1}
			var r: float = rng.randf()
			if r < 0.2:
				row.append(-1.0)
			elif r > 0.8:
				row.append(1.0)
			else:
				row.append(0.0)
		_proj_weights.append(row)


## Initializes associative weights from Kenyon Cells to MBONs
func _init_synaptic_weights() -> void:
	_weights.clear()
	for out in range(NUM_OUTPUTS):
		var row: Array = []
		for kc in range(NUM_KCS):
			row.append(0.0)
		_weights.append(row)


## Encodes a 16-element sensory vector into sparse Kenyon Cell activations (LSH)
func encode_context(sensory_inputs: Array) -> PackedInt32Array:
	if sensory_inputs.size() < NUM_INPUTS:
		return active_kcs
	
	# 1. Compute linear projection scores for all 256 KCs
	var scores: Array[Dictionary] = []
	for kc in range(NUM_KCS):
		var proj_row: Array = _proj_weights[kc]
		var sum_val := 0.0
		for inp in range(NUM_INPUTS):
			var w: float = proj_row[inp]
			if w != 0.0:
				sum_val += float(sensory_inputs[inp]) * w
		scores.append({"kc": kc, "val": sum_val})
	
	# 2. Winner-Take-All (WTA) / Top-K Sparsity: Keep highest SPARSITY cells
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["val"]) > float(b["val"])
	)
	
	active_kcs.clear()
	context_hash.fill(0)
	
	for i in range(SPARSITY):
		var kc_idx: int = scores[i]["kc"]
		active_kcs.append(kc_idx)
		
		# Pack into 256-bit bitmask (8 x 32-bit ints)
		var int_idx: int = kc_idx / 32
		var bit_idx: int = kc_idx % 32
		context_hash[int_idx] = context_hash[int_idx] | (1 << bit_idx)
	
	return active_kcs


## Predicts the habitual bias vector (-1.0..1.0 for each of the 6 needs)
func predict_habit_bias() -> Array[float]:
	var biases: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if active_kcs.is_empty():
		return biases
	
	var norm: float = 1.0 / float(active_kcs.size())
	for out in range(NUM_OUTPUTS):
		var row: Array = _weights[out]
		var sum_val := 0.0
		for kc in active_kcs:
			sum_val += float(row[kc])
		biases[out] = clampf(sum_val * norm, -1.0, 1.0)
	
	return biases


## Online Hebbian Reinforcement: Associates active Kenyon Cells with a reward/valence vector
## dan_rewards: Array of floats (-1.0..1.0) representing Dopaminergic teaching signals
func learn(dan_rewards: Array, rate_scale: float = 1.0) -> void:
	if active_kcs.is_empty():
		return
	
	var effective_rate := learning_rate * rate_scale
	var limit := mini(NUM_OUTPUTS, dan_rewards.size())
	
	for out in range(limit):
		var reward := float(dan_rewards[out])
		if reward == 0.0:
			continue
		var row: Array = _weights[out]
		for kc in active_kcs:
			var w := float(row[kc])
			# Hebbian rule with saturation bounds [-1.0, 1.0]
			row[kc] = clampf(w + effective_rate * reward, -1.0, 1.0)


## Computes bitwise Hamming distance between two 256-bit context hashes
## Lower distance (0..32) = High context similarity (same time/place/posture)
static func hamming_distance(hash_a: PackedInt32Array, hash_b: PackedInt32Array) -> int:
	if hash_a.size() != 8 or hash_b.size() != 8:
		return 256
	var dist := 0
	for i in range(8):
		var diff: int = hash_a[i] ^ hash_b[i]
		# Brian Kernighan bit count
		var count := 0
		var u: int = diff
		while u != 0:
			u = u & (u - 1)
			count += 1
		dist += count
	return dist


## SLEEP CONSOLIDATION (dFB / R5 synaptic downscaling).
##
## Sleeping flies prune: every synapse is shaved a little so that only what was
## reinforced often enough survives the night. `protection` is the circadian
## permissiveness -- high at night, when the fly is allowed to sleep and the
## memory it just made must be protected, low at noon, when an unrehearsed
## association is free to fade.
func decay(dt_sec: float, protection: float) -> void:
	var dt: float = maxf(dt_sec, 0.0)
	if dt <= 0.0:
		return
	var rate: float = DECAY_PER_SEC * (1.0 - clampf(protection, 0.0, 1.0))
	if rate <= 0.0:
		return
	var keep: float = maxf(1.0 - rate * dt, 0.0)
	for out in range(NUM_OUTPUTS):
		var row: Array = _weights[out]
		for kc in range(NUM_KCS):
			row[kc] = float(row[kc]) * keep


## Reads the install's projection seed, creating it on first run.
static func install_seed() -> int:
	if FileAccess.file_exists(SEED_PATH):
		var f := FileAccess.open(SEED_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("seed"):
				return int((parsed as Dictionary)["seed"])
	var born: int = DEFAULT_SEED
	var w := FileAccess.open(SEED_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(JSON.stringify({"seed": born, "born": int(Time.get_unix_time_from_system())}))
		w.close()
	return born


## Clears associative habit memory
func reset() -> void:
	_init_synaptic_weights()
	active_kcs.clear()
	context_hash.fill(0)
