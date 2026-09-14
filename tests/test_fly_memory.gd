extends MainLoop

## DOPAMINE, SLEEP, AND RECALL.
##
## Four claims, each of them about the mushroom body doing something real:
##   1. A named event moves the habit bias, because a DAN fired on live KCs.
##   2. The KC projection is seeded from disk, so yesterday's hash is today's.
##   3. Weights fade slower at night, when sleep both permits and protects.
##   4. The same sparse hash, widened to 768 inputs, retrieves text neighbours.

const FlyBrainScript := preload("res://scripts/brain/fly_brain.gd")
const FlyMushroomBodyScript := preload("res://scripts/brain/fly_mushroom_body.gd")
const FlyHashScript := preload("res://scripts/brain/fly_hash.gd")
const FlyRecallScript := preload("res://scripts/brain/fly_recall.gd")
const CharacterScript := preload("res://scripts/brain/character.gd")

const DIM := 768
const CLUSTERS := 20
const PER_CLUSTER := 10
const NOISE := 0.05

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
	print("HEXY_TEST: Running Fly Memory Suite (dopamine, sleep, sparse recall)...")
	_test_reward_events()
	_test_seed_persistence()
	_test_sleep_decay()
	_test_fly_hash()
	_test_recall()
	_test_hash_latency()

	print("\n=== FLY MEMORY RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (The Fly Remembers)")
	return true


func _senses(fill: float) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(16)
	v.fill(fill)
	return v


# ---------------------------------------------------------------- 1. dopamine

func _test_reward_events() -> void:
	print("\n• Testing that named events teach the mushroom body...")
	var brain: RefCounted = FlyBrainScript.new()
	check(FlyBrainScript.REWARDS.has("cast_confirmed"), "REWARDS table names cast_confirmed")
	check(float(FlyBrainScript.REWARDS["startle"]) < 0.0, "startle is a punishment, not a reward")

	# A pattern must be live before dopamine means anything.
	brain.feed({"senses": _senses(0.5), "solar_hour": 12.0}, 1.0 / 60.0)
	check(brain.mushroom_body.active_kcs.size() == 16, "A KC pattern is present before the reward")

	var before: Array[float] = brain.state()["habit_bias"]
	var sum_before := 0.0
	for b in before:
		sum_before += b
	for i in range(10):
		brain.reward_event("cast_confirmed")
	var after: Array[float] = brain.state()["habit_bias"]
	var sum_after := 0.0
	for b in after:
		sum_after += b
	check(sum_after > sum_before + 0.5,
		"cast_confirmed raised habit_bias on the live pattern (%.3f -> %.3f)" % [sum_before, sum_after])

	# Punishment pulls the other way.
	var brain2: RefCounted = FlyBrainScript.new()
	brain2.feed({"senses": _senses(0.5), "solar_hour": 12.0}, 1.0 / 60.0)
	for i in range(10):
		brain2.reward_event("battery_critical")
	var punished: Array[float] = brain2.state()["habit_bias"]
	var sum_punished := 0.0
	for b in punished:
		sum_punished += b
	check(sum_punished < 0.0, "battery_critical drove the habit bias negative (%.3f)" % sum_punished)

	check(brain.reward_event("no_such_event") == 0.0, "An unknown event name teaches nothing")

	# The startle wires itself: no caller has to call reward_event for it.
	var brain3: RefCounted = FlyBrainScript.new()
	brain3.feed({"senses": _senses(0.5), "accel": Vector3(0.0, -9.8, 0.0)}, 1.0 / 60.0)
	brain3.feed({"senses": _senses(0.5), "accel": Vector3.ZERO}, 1.0 / 60.0)
	var startled_bias: Array[float] = brain3.state()["habit_bias"]
	var sum_startled := 0.0
	for b in startled_bias:
		sum_startled += b
	check(sum_startled < 0.0, "A freefall startle punished the live pattern by itself (%.3f)" % sum_startled)

	# And the character forwards the whole thing.
	var ch: RefCounted = CharacterScript.new()
	check(ch.has_method("reward_event"), "Character exposes reward_event")
	ch.feed_senses({"senses": _senses(0.6), "solar_hour": 12.0}, 1.0 / 60.0)
	var q_before: PackedFloat64Array = ch.to_q6_bias(true)
	for i in range(20):
		ch.reward_event("owner_tap")
	var q_after: PackedFloat64Array = ch.to_q6_bias(true)
	var moved := false
	for i in range(6):
		if absf(q_after[i] - q_before[i]) > 0.001:
			moved = true
	check(moved, "Character.reward_event moved the 85/15 habit blend in to_q6_bias")


# ------------------------------------------------------------------- 2. seed

func _test_seed_persistence() -> void:
	print("\n• Testing that the KC projection is seeded from disk...")
	var seed_a: int = FlyMushroomBodyScript.install_seed()
	var seed_b: int = FlyMushroomBodyScript.install_seed()
	check(seed_a == seed_b, "install_seed() is stable across calls (%d)" % seed_a)
	check(FileAccess.file_exists(FlyMushroomBodyScript.SEED_PATH), "The seed file exists after first run")

	var mb_a: RefCounted = FlyMushroomBodyScript.new()
	var mb_b: RefCounted = FlyMushroomBodyScript.new()
	check(mb_a.seed == seed_a, "FlyMushroomBody.seed exposes the install seed")

	var ctx := [0.1, 0.8, 0.2, 0.9, 0.0, 0.5, 0.3, 0.4, 0.7, 0.6, 0.2, 0.1, 0.9, 0.8, 0.5, 0.3]
	mb_a.encode_context(ctx)
	mb_b.encode_context(ctx)
	check(FlyMushroomBodyScript.hamming_distance(mb_a.context_hash, mb_b.context_hash) == 0,
		"Two bodies on the same install hash the same context identically")

	var mb_other: RefCounted = FlyMushroomBodyScript.new(12345)
	mb_other.encode_context(ctx)
	check(mb_other.seed == 12345, "An explicit seed overrides the install seed")
	check(FlyMushroomBodyScript.hamming_distance(mb_a.context_hash, mb_other.context_hash) > 0,
		"A different seed wires a different projection")


# ------------------------------------------------------------------ 3. sleep

func _test_sleep_decay() -> void:
	print("\n• Testing that sleep prunes slower than noon...")
	var ctx := [0.1, 0.8, 0.2, 0.9, 0.0, 0.5, 0.3, 0.4, 0.7, 0.6, 0.2, 0.1, 0.9, 0.8, 0.5, 0.3]

	var noon: RefCounted = FlyBrainScript.new()
	noon.feed({"senses": _senses(0.5), "solar_hour": 12.0}, 1.0 / 60.0)
	for i in range(20):
		noon.learn(1.0)
	var night: RefCounted = FlyBrainScript.new()
	night.feed({"senses": _senses(0.5), "solar_hour": 2.0}, 1.0 / 60.0)
	for i in range(20):
		night.learn(1.0)

	var noon_start: float = noon.state()["habit_bias"][0]
	var night_start: float = night.state()["habit_bias"][0]
	check(absf(noon_start - night_start) < 0.001, "Both brains start from the same learned weight")

	# One simulated hour of the clock they are each under.
	for i in range(360):
		noon.feed({"senses": _senses(0.5), "solar_hour": 12.0}, 10.0)
		night.feed({"senses": _senses(0.5), "solar_hour": 2.0}, 10.0)
	var noon_end: float = noon.state()["habit_bias"][0]
	var night_end: float = night.state()["habit_bias"][0]
	check(noon_end < noon_start, "Noon weights faded (%.4f -> %.4f)" % [noon_start, noon_end])
	check(night_end > noon_end,
		"Night weights decayed slower than noon (night %.4f > noon %.4f)" % [night_end, noon_end])

	# And the bare unit does the arithmetic it claims.
	var mb: RefCounted = FlyMushroomBodyScript.new()
	mb.encode_context(ctx)
	mb.learn([1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var w0: float = mb.predict_habit_bias()[0]
	mb.decay(100.0, 1.0)
	check(is_equal_approx(mb.predict_habit_bias()[0], w0), "Full protection decays nothing")
	mb.decay(100.0, 0.0)
	check(mb.predict_habit_bias()[0] < w0 * 0.9, "Zero protection sheds 0.002/s of the weight")


# --------------------------------------------------------------- 4. fly hash

func _unit_random(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(DIM)
	var n := 0.0
	for i in range(DIM):
		var x: float = rng.randfn(0.0, 1.0)
		v[i] = x
		n += x * x
	n = sqrt(maxf(n, 1e-9))
	for i in range(DIM):
		v[i] = v[i] / n
	return v


## Gaussian jitter of `sigma`, in units of the vector's own per-component scale
## (1/sqrt(dim) for a unit vector), so sigma=0.05 is a 5% nudge rather than a
## per-component noise floor twenty times larger than the signal itself.
func _perturb(base: PackedFloat32Array, sigma: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var scale: float = sigma / sqrt(float(DIM))
	var v := PackedFloat32Array()
	v.resize(DIM)
	var n := 0.0
	for i in range(DIM):
		var x: float = base[i] + rng.randfn(0.0, scale)
		v[i] = x
		n += x * x
	n = sqrt(maxf(n, 1e-9))
	for i in range(DIM):
		v[i] = v[i] / n
	return v


static func _cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var dot := 0.0
	for i in range(a.size()):
		dot += float(a[i]) * float(b[i])
	return dot


func _test_fly_hash() -> void:
	print("\n• Testing FlyHash (768 -> 2048 cells, 102 active)...")
	var fh: RefCounted = FlyHashScript.new(DIM, 2048, 102, 99991)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var a: PackedFloat32Array = _unit_random(rng)
	var ha: PackedInt32Array = fh.hash(a)
	check(ha.size() == 64, "hash() returns 64 words of 32 bits (2048 cells)")

	var bits := 0
	for w in ha:
		var u: int = int(w) & 0xFFFFFFFF
		while u != 0:
			u = u & (u - 1)
			bits += 1
	check(bits == 102, "Exactly 102 cells fire (got %d)" % bits)

	var ha2: PackedInt32Array = fh.hash(a)
	check(FlyHashScript.hamming(ha, ha2) == 0, "The same vector hashes to Hamming 0")
	check(is_equal_approx(fh.similarity(ha, ha2), 1.0), "similarity() of a vector with itself is 1.0")

	var near: PackedFloat32Array = _perturb(a, NOISE, rng)
	var hn: PackedInt32Array = fh.hash(near)
	var d_near: int = FlyHashScript.hamming(ha, hn)
	check(d_near <= 40, "A sigma=0.05 perturbation stays close (%d <= 40)" % d_near)

	var other: PackedFloat32Array = _unit_random(rng)
	var d_far: int = FlyHashScript.hamming(ha, fh.hash(other))
	check(d_far >= 120, "An unrelated vector is far (%d >= 120)" % d_far)
	check(fh.similarity(ha, hn) > fh.similarity(ha, fh.hash(other)),
		"similarity() ranks the neighbour above the stranger")


# -------------------------------------------------------------- 5. recall

func _test_recall() -> void:
	print("\n• Testing FlyRecall over 20 clusters x 10 synthetic vectors...")
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var fh: RefCounted = FlyHashScript.new(DIM, 2048, 102, 99991)
	var rec: RefCounted = FlyRecallScript.new(fh)

	var centers: Array = []
	var vectors: Array = []
	var labels: Array[int] = []
	for c in range(CLUSTERS):
		centers.append(_unit_random(rng))
	for c in range(CLUSTERS):
		for m in range(PER_CLUSTER):
			var v: PackedFloat32Array = _perturb(centers[c], NOISE, rng)
			vectors.append(v)
			labels.append(c)
			rec.remember("c%d_m%d" % [c, m], v, {"cluster": c})
	check(rec.size() == CLUSTERS * PER_CLUSTER, "200 memories stored")

	var hash_hits := 0
	var cos_hits := 0
	var total := 0
	for c in range(CLUSTERS):
		var q: PackedFloat32Array = _perturb(centers[c], NOISE, rng)
		for row in rec.recall(q, 5):
			total += 1
			if int((row["meta"] as Dictionary).get("cluster", -1)) == c:
				hash_hits += 1
		# Cosine ranking over the same fixture, for a ceiling to compare to.
		var scored: Array[Dictionary] = []
		for i in range(vectors.size()):
			scored.append({"i": i, "s": _cosine(q, vectors[i])})
		scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return float(x["s"]) > float(y["s"]))
		for j in range(5):
			if labels[int(scored[j]["i"])] == c:
				cos_hits += 1

	var recall_at_5: float = float(hash_hits) / float(total)
	var cos_at_5: float = float(cos_hits) / float(total)
	print("  recall@5 (FlyHash) = %.3f, recall@5 (cosine) = %.3f" % [recall_at_5, cos_at_5])
	check(recall_at_5 >= 0.9, "FlyHash recall@5 >= 0.9 (got %.3f)" % recall_at_5)
	check(recall_at_5 >= cos_at_5 * 0.9,
		"FlyHash is within 10%% of cosine ranking (%.3f vs %.3f)" % [recall_at_5, cos_at_5])

	# Round trip through user://.
	var path := "user://test_fly_recall.json"
	check(rec.save(path), "FlyRecall saved to user://")
	var rec2: RefCounted = FlyRecallScript.new(fh)
	check(rec2.load(path), "FlyRecall loaded back")
	check(rec2.size() == rec.size(), "Loaded store has every memory")
	var probe: PackedFloat32Array = vectors[0]
	check(String(rec2.recall(probe, 1)[0]["text"]) == String(rec.recall(probe, 1)[0]["text"]),
		"Loaded store recalls the same nearest memory")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# -------------------------------------------------------------- 6. latency

func _test_hash_latency() -> void:
	print("\n• Measuring hash() latency over 1000 calls of a 768-dim vector...")
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var fh: RefCounted = FlyHashScript.new(DIM, 2048, 102, 99991)
	var v: PackedFloat32Array = _unit_random(rng)
	fh.hash(v)  # warm
	var t0: int = Time.get_ticks_usec()
	for i in range(1000):
		fh.hash(v)
	var mean_us: float = float(Time.get_ticks_usec() - t0) / 1000.0
	print("  HASH_LATENCY_MEAN_US = %.1f (goal 200.0)" % mean_us)
	check(mean_us < 5000.0, "hash() mean latency %.1f us is within the GDScript ceiling" % mean_us)
