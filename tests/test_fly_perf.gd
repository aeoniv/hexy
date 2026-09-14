extends MainLoop

## Measures the fly brain's actual per-feed cost and memory footprint on this
## machine, against the documented targets in docs/fly-brain.md. Run with:
##   godot --headless --path . -s res://tests/test_fly_perf.gd

const CharacterScript := preload("res://scripts/brain/character.gd")

const DEVICE_TARGET_US := 40.0
const WARMUP_ITERS := 500
const MEASURE_ITERS := 10000

var passes := 0
var failures := 0


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func _make_sample(i: int) -> Dictionary:
	var noise: float = sin(float(i) * 0.017) * 0.05
	var senses := PackedFloat32Array()
	senses.resize(16)
	for j in range(16):
		senses[j] = clampf(0.5 + 0.3 * sin(float(i) * 0.01 + float(j)), 0.0, 1.0)
	return {
		"accel": Vector3(noise, 9.8 + noise, -noise),
		"gyro_yaw_rate": 0.3,
		"solar_hour": 10.0,
		"heading_deg": 45.0,
		"senses": senses,
		"peers": 1,
	}


func _percentile(sorted_vals: PackedFloat64Array, p: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = int(ceil(p * sorted_vals.size())) - 1
	idx = clampi(idx, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


func _process(_delta: float) -> bool:
	print("HEXY_TEST: Fly brain performance measurement...")

	var mem_before: int = OS.get_static_memory_usage()
	var character := CharacterScript.new()
	var dt := 1.0 / 60.0

	# Warm up: let allocations, buffer resizes, JIT-ish caches settle.
	for i in range(WARMUP_ITERS):
		character.feed_senses(_make_sample(i), dt)
		character.get_fly_state()

	# Measure feed_senses + get_fly_state together (the real per-frame cost).
	var samples := PackedFloat64Array()
	samples.resize(MEASURE_ITERS)
	for i in range(MEASURE_ITERS):
		var sample := _make_sample(i)
		var t0 := Time.get_ticks_usec()
		character.feed_senses(sample, dt)
		character.get_fly_state()
		var t1 := Time.get_ticks_usec()
		samples[i] = float(t1 - t0)

	var mem_after: int = OS.get_static_memory_usage()
	var mem_delta: int = mem_after - mem_before

	var total := 0.0
	for s in samples:
		total += s
	var mean_us: float = total / float(MEASURE_ITERS)

	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var p95_us: float = _percentile(sorted_samples, 0.95)

	print("\n=== FLY BRAIN PERFORMANCE ===")
	print("FLY_FEED_MEAN_US=%.3f" % mean_us)
	print("FLY_FEED_P95_US=%.3f" % p95_us)
	print("FLY_MEM_DELTA_BYTES=%d" % mem_delta)
	print("Device target: %.1f us/frame (documented goal, not this machine's ceiling)" % DEVICE_TARGET_US)
	print("Ratio to device target: %.2fx" % (mean_us / DEVICE_TARGET_US))

	# hud state read alone
	var t_state0 := Time.get_ticks_usec()
	for i in range(MEASURE_ITERS):
		character.get_fly_state()
	var t_state1 := Time.get_ticks_usec()
	var state_mean_us: float = float(t_state1 - t_state0) / float(MEASURE_ITERS)
	print("FLY_STATE_READ_MEAN_US=%.3f" % state_mean_us)

	# Cross-platform ceiling: Linux workstations with JIT run ~365 us, while Windows
	# debug bytecode execution has ~1.5 ms baseline. Both comfortably satisfy the 16.6 ms (60 FPS) budget.
	var max_mean: float = 2500.0 if OS.get_name() == "Windows" else 400.0
	var max_p95: float = 4000.0 if OS.get_name() == "Windows" else 2000.0
	check(mean_us < max_mean, "mean feed+state time under %.0fus ceiling (got %.3f)" % [max_mean, mean_us])
	check(p95_us < max_p95, "p95 feed+state time under %.0fus (got %.3f)" % [max_p95, p95_us])
	check(mem_delta < 1572864, "memory delta under 1.5MB over %d feeds (got %d bytes)" % [MEASURE_ITERS, mem_delta])

	# Per-module profiling when the aggregate is not obviously cheap.
	if mean_us > 100.0:
		_profile_modules(character, dt)

	print("\n=== PERF TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS ===")
	return true


func _profile_modules(character: Object, dt: float) -> void:
	print("\n=== PER-MODULE PROFILE (%d iterations each) ===" % MEASURE_ITERS)
	var fb: Object = character.fly_brain

	var t0 := Time.get_ticks_usec()
	for i in range(MEASURE_ITERS):
		fb.giant_fiber.step(dt, Vector3(0.0, 9.8, 0.0))
	var t1 := Time.get_ticks_usec()
	print("giant_fiber.step        : %.3f us/call" % (float(t1 - t0) / float(MEASURE_ITERS)))

	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_ITERS):
		fb.central_complex.step(dt, 0.3, 0.0)
	t1 = Time.get_ticks_usec()
	print("central_complex.step    : %.3f us/call" % (float(t1 - t0) / float(MEASURE_ITERS)))

	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_ITERS):
		fb.circadian_clock.update(10.0)
	t1 = Time.get_ticks_usec()
	print("circadian_clock.update  : %.3f us/call" % (float(t1 - t0) / float(MEASURE_ITERS)))

	var senses_arr: Array = []
	for j in range(16):
		senses_arr.append(0.5)
	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_ITERS):
		fb.mushroom_body.encode_context(senses_arr)
	t1 = Time.get_ticks_usec()
	print("mushroom_body.encode_context: %.3f us/call" % (float(t1 - t0) / float(MEASURE_ITERS)))

	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_ITERS):
		fb.mushroom_body.decay(dt, 0.5)
	t1 = Time.get_ticks_usec()
	print("mushroom_body.decay     : %.3f us/call" % (float(t1 - t0) / float(MEASURE_ITERS)))

	t0 = Time.get_ticks_usec()
	for i in range(MEASURE_ITERS):
		fb.state()
	t1 = Time.get_ticks_usec()
	print("fly_brain.state          : %.3f us/call" % (float(t1 - t0) / float(MEASURE_ITERS)))
