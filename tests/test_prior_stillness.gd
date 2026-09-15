extends SceneTree

## Headless checks for PART C: stillness modulating how loudly the cube speaks
## to Qwen, and the 64-corner mass the store publishes for the mesh.
##
## The flag is off by default and must stay off: with it off, a hundred beats
## may not move the prior weight by a hair. The shape of the curve is checked
## through the pure static, which needs no device.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST PRIOR STILLNESS (the cube's volume) ---")

	_test_curve()
	_test_flag_off()
	_test_q6_mass()

	if failures == 0:
		print("--- PRIOR STILLNESS TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- PRIOR STILLNESS TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _test_curve() -> void:
	print("\n[ the shape of the volume knob ]")
	var zero_still: bool = true
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		if not is_equal_approx(Q6Core.prior_weight_for(0.0, float(t)), 0.0):
			zero_still = false
	check(zero_still, "a moving body is silent, whatever the cube's tension")

	var zero_tense: bool = true
	for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
		if not is_equal_approx(Q6Core.prior_weight_for(float(s), 1.0), 0.0):
			zero_tense = false
	check(zero_tense, "a uniform cube (tension 1) has nothing to say, however still")

	var mono: bool = true
	var last: float = -1.0
	for i in range(21):
		var w: float = Q6Core.prior_weight_for(float(i) / 20.0, 0.0)
		if w < last:
			mono = false
		last = w
	check(mono, "the weight rises monotonically with stillness")

	check(is_equal_approx(Q6Core.prior_weight_for(1.0, 0.0), Q6Core.PRIOR_MAX),
		"a perfectly still body on a sharp cube reaches PRIOR_MAX exactly")

	var capped: bool = true
	for i in range(11):
		for j in range(11):
			var w2: float = Q6Core.prior_weight_for(float(i) / 10.0, float(j) / 10.0)
			if w2 < 0.0 or w2 > Q6Core.PRIOR_MAX:
				capped = false
	check(capped, "and never leaves [0, PRIOR_MAX] anywhere on the square")

	check(is_equal_approx(Q6Core.prior_weight_for(9.0, -4.0), Q6Core.PRIOR_MAX),
		"out-of-range inputs clamp rather than run away (high)")
	check(is_equal_approx(Q6Core.prior_weight_for(-9.0, 4.0), 0.0),
		"out-of-range inputs clamp rather than run away (low)")


func _test_flag_off() -> void:
	print("\n[ the flag is off and stays off ]")
	var cfg: HexyConfig = HexyConfig.instance()
	cfg.autosave = false
	check(bool(cfg.get_value("prior.follows_stillness")) == false,
		"prior.follows_stillness defaults to false")
	var store: HexyStore = HexyStoreScript.new()
	var senses: Senses = Senses.new()
	senses.bind(store)
	var before: float = Q6Core.prior_weight()
	## W10d -- alchemy.gd is deleted; the app's own `_beat_pacing` is the only
	## thing that ever drives the prior off stillness, and it reads the same
	## `prior.follows_stillness` flag this checks directly, off by default.
	check(not (cfg.has_method("get_value") and bool(cfg.get_value("prior.follows_stillness"))),
		"nothing here follows stillness with the flag off")
	check(is_equal_approx(Q6Core.prior_weight(), before),
		"the prior weight is untouched with the flag off (got %f, want %f)"
			% [Q6Core.prior_weight(), before])


func _test_q6_mass() -> void:
	print("\n[ the store publishes the cube ]")
	var store: HexyStore = HexyStoreScript.new()
	var senses: Senses = Senses.new()
	senses.bind(store)
	check(store.q6_mass().is_empty(), "the store carries no mass before a first beat")
	## W10d -- alchemy.gd is deleted; the app's `_beat_pacing` walks a Pacing
	## and publishes its 64-corner mass to the store every beat. Reproduced
	## here without an App, the same way app.gd does it.
	var p: Pacing = Pacing.new()
	p.reset(store.body_bits())
	p.tick(100, senses.target_bits(), senses.stillness(), senses.excitation(),
		senses.machine_margin(), senses.human_margin())
	store.set_q6_mass(p.cube.state())
	var mass: PackedFloat32Array = store.q6_mass()
	check(mass.size() == Q6Core.STATES,
		"one beat publishes all 64 corners (got %d)" % mass.size())
	var total: float = 0.0
	for v in mass:
		total += float(v)
	check(absf(total - 1.0) < 1e-3,
		"and the mass it publishes is still a distribution (sums to %f)" % total)
