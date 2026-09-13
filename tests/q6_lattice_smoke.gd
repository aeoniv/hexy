extends SceneTree
## THE SIX-BIT CUBE, FALSIFIED — `scripts/oracle/q6_lattice.gd` has no callers,
## so nothing in the app would go red if its arithmetic were wrong. This suite
## is the only thing standing between that module and a plausible-looking lie.
##
## Every claim here is checkable without a reference table, because the cube's
## own symmetries do the checking:
##
##   1. FWHT IS ITS OWN INVERSE up to 64, on random vectors,
##   2. DIFFUSION PRESERVES MASS, and a long enough step forgets everything,
##   3. FLIP EQUIVARIANCE — inverting every line and negating the bias is the
##      same as inverting the answer,
##   4. REVERSE EQUIVARIANCE — turning the hexagram upside down and reversing
##      the bias is the same as turning the answer upside down,
##   5. NO BIAS MOVES NOTHING — uniform stays uniform, tension stays 1,
##   6. ONE STRONG LINE decides that line, and only that line,
##   7. PERSISTENCE — twenty steps under a fixed bias settle on the corner
##      that agrees with all six signs,
##   8. THE NEIGHBOURS ARE THE NEIGHBOURS — one small step from a delta puts
##      equal mass on the six one-line neighbours, and more there than on any
##      two-line one.
## Prints === ALL PASS === or fails.

const Q6 = preload("res://scripts/core/iching/q6_lattice.gd")

var _fails := 0
## EVERY CHECK IS COUNTED — a suite that prints ALL PASS because a preload
## failed and a section skipped is worse than a red one.
const MIN_CHECKS := 120
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		printerr("FAIL ", what)


## A quieter check for the inside of a 64-long loop — counted, printed only
## when it fails, so the output stays readable.
func _check_quiet(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL ", what)


func _initialize() -> void:
	_fwht_is_its_own_inverse()
	_diffusion_keeps_the_mass_and_forgets()
	_flip_equivariance()
	_reverse_equivariance()
	_no_bias_moves_nothing()
	_one_strong_line()
	_persistence()
	_the_neighbours_are_the_neighbours()
	print("checks: ", _checks, " (floor ", MIN_CHECKS, ")")
	if _checks < MIN_CHECKS:
		_fails += 1
		printerr("FAIL only ", _checks, " checks ran; the floor is ", MIN_CHECKS)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


func _rng_vector(rng: RandomNumberGenerator) -> PackedFloat64Array:
	var v := PackedFloat64Array()
	v.resize(Q6.STATES)
	for h in Q6.STATES:
		v[h] = rng.randf_range(-2.0, 2.0)
	return v


func _rng_probs(rng: RandomNumberGenerator) -> PackedFloat64Array:
	var v := PackedFloat64Array()
	v.resize(Q6.STATES)
	var total := 0.0
	for h in Q6.STATES:
		v[h] = rng.randf_range(0.001, 1.0)
		total += v[h]
	for h in Q6.STATES:
		v[h] = v[h] / total
	return v


func _max_abs_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst := 0.0
	for h in a.size():
		worst = maxf(worst, absf(a[h] - b[h]))
	return worst


func _sum(p: PackedFloat64Array) -> float:
	var s := 0.0
	for x in p:
		s += x
	return s


# ── 1. the transform is its own inverse ─────────────────────────────────────


func _fwht_is_its_own_inverse() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260907
	for trial in 8:
		var v := _rng_vector(rng)
		var back := Q6.fwht(Q6.fwht(v))
		for h in Q6.STATES:
			back[h] = back[h] / float(Q6.STATES)
		_check_quiet(
			_max_abs_diff(v, back) < 1e-9, "fwht twice over 64 is identity (trial %d)" % trial
		)
	_check(true, "fwht applied twice and divided by 64 returns the vector it was given")
	# The transform does not scribble on its input.
	var orig := _rng_vector(rng)
	var copy := orig.duplicate()
	Q6.fwht(orig)
	_check(_max_abs_diff(orig, copy) == 0.0, "fwht leaves its argument untouched")
	# The zero coefficient is the total, by construction — this is why
	# diffusion can be trusted with the mass.
	var p := _rng_probs(rng)
	_check(absf(Q6.fwht(p)[0] - _sum(p)) < 1e-12, "the zero Walsh coefficient is the total mass")
	# popcount is the eigenvalue, and it counts what it claims to count.
	_check(Q6.popcount(0) == 0, "no lines set is popcount zero")
	_check(Q6.popcount(63) == 6, "all six lines set is popcount six")
	_check(Q6.popcount(0b010101) == 3, "three lines set is popcount three")


# ── 2. diffusion keeps the mass, and forgets ────────────────────────────────


func _diffusion_keeps_the_mass_and_forgets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for trial in 6:
		var p := _rng_probs(rng)
		for t in [0.0, 0.01, 0.2, 1.0, 5.0]:
			var q := Q6.diffuse(p, t)
			_check_quiet(
				absf(_sum(q) - 1.0) < 1e-12,
				"diffusion at t=%s keeps the mass (trial %d)" % [t, trial]
			)
			var negative := false
			for h in Q6.STATES:
				if q[h] < -1e-12:
					negative = true
			_check_quiet(not negative, "diffusion at t=%s stays a distribution" % t)
	_check(true, "diffusion preserves the total mass and never goes negative")
	# t = 0 is the identity: no time, no spreading.
	var d := Q6.delta(0b101101)
	_check(_max_abs_diff(Q6.diffuse(d, 0.0), d) < 1e-12, "a zero-length step moves nothing")
	# A long enough step forgets where it started, from ANY starting point.
	for trial in 4:
		var p := _rng_probs(rng)
		var far := Q6.diffuse(p, 40.0)
		var lo: float = far[0]
		var hi: float = far[0]
		for h in Q6.STATES:
			lo = minf(lo, far[h])
			hi = maxf(hi, far[h])
		_check_quiet(
			hi - lo < 1e-6, "t=40 drives trial %d to uniform (spread %s)" % [trial, hi - lo]
		)
		_check_quiet(absf(Q6.tension(far) - 1.0) < 1e-9, "and its tension reads 1")
	_check(true, "a long enough heat step drives any distribution to uniform")
	var flat := Q6.diffuse(Q6.delta(17), 40.0)
	_check(absf(flat[0] - 1.0 / 64.0) < 1e-6, "even a delta ends up at one sixty-fourth each")


# ── 3. flip equivariance ────────────────────────────────────────────────────


func _flip_equivariance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_check(Q6.flip(0) == 63, "flipping an all-yin hexagram gives all-yang")
	_check(Q6.flip(Q6.flip(0b010110)) == 0b010110, "flip is its own inverse")
	for trial in 10:
		var p := _rng_probs(rng)
		var bias := PackedFloat64Array()
		bias.resize(6)
		for i in 6:
			bias[i] = rng.randf_range(-1.0, 1.0)
		var t: float = rng.randf_range(0.05, 1.5)
		var beta: float = rng.randf_range(0.1, 3.0)
		var left := Q6.step(Q6.perm_flip(p), Q6.negate_bias(bias), t, beta)
		var right := Q6.perm_flip(Q6.step(p, bias, t, beta))
		_check_quiet(
			_max_abs_diff(left, right) < 1e-9,
			(
				"flip commutes with the step under a negated bias (trial %d, %s)"
				% [trial, _max_abs_diff(left, right)]
			)
		)
	_check(true, "inverting every line and negating the bias inverts the answer, exactly")
	# The permutation itself is a permutation: mass in, mass out, and it is
	# its own inverse.
	var q := _rng_probs(rng)
	_check(absf(_sum(Q6.perm_flip(q)) - 1.0) < 1e-12, "perm_flip keeps the mass")
	_check(_max_abs_diff(Q6.perm_flip(Q6.perm_flip(q)), q) == 0.0, "perm_flip is its own inverse")


# ── 4. reverse equivariance ─────────────────────────────────────────────────


func _reverse_equivariance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	_check(Q6.reverse(0b000001) == 0b100000, "reversing the bottom line puts it on top")
	_check(Q6.reverse(Q6.reverse(0b011010)) == 0b011010, "reverse is its own inverse")
	_check(Q6.reverse(0b010101) == 0b101010, "63 Jiji's bits reversed are 64 Weiji's")
	for trial in 10:
		var p := _rng_probs(rng)
		var bias := PackedFloat64Array()
		bias.resize(6)
		for i in 6:
			bias[i] = rng.randf_range(-1.0, 1.0)
		var t: float = rng.randf_range(0.05, 1.5)
		var beta: float = rng.randf_range(0.1, 3.0)
		var left := Q6.step(Q6.perm_reverse(p), Q6.reverse_bias(bias), t, beta)
		var right := Q6.perm_reverse(Q6.step(p, bias, t, beta))
		_check_quiet(
			_max_abs_diff(left, right) < 1e-9,
			(
				"reverse commutes with the step under a reversed bias (trial %d, %s)"
				% [trial, _max_abs_diff(left, right)]
			)
		)
	_check(true, "turning the hexagram upside down turns the answer upside down, exactly")
	var q := _rng_probs(rng)
	_check(absf(_sum(Q6.perm_reverse(q)) - 1.0) < 1e-12, "perm_reverse keeps the mass")
	_check(
		_max_abs_diff(Q6.perm_reverse(Q6.perm_reverse(q)), q) == 0.0,
		"perm_reverse is its own inverse"
	)


# ── 5. no bias moves nothing ────────────────────────────────────────────────


func _no_bias_moves_nothing() -> void:
	var zero := PackedFloat64Array()
	zero.resize(6)
	zero.fill(0.0)
	var p := Q6.uniform()
	_check(absf(Q6.tension(p) - 1.0) < 1e-12, "uniform reads a tension of exactly 1")
	for i in 12:
		p = Q6.step(p, zero, 0.3, 2.0)
		_check_quiet(_max_abs_diff(p, Q6.uniform()) < 1e-12, "step %d of nothing stays uniform" % i)
		_check_quiet(absf(Q6.tension(p) - 1.0) < 1e-12, "and tension stays 1")
	_check(true, "twelve steps with no bias from uniform stay exactly uniform")
	# The potential of a zero bias is flat, corner by corner.
	var u := Q6.potential_from_lines(zero)
	for h in Q6.STATES:
		_check_quiet(u[h] == 0.0, "no bias gives no field at %d" % h)
	_check(true, "a zero bias is a flat field over all 64 corners")
	# And a delta is the other end of the scale: no tension at all.
	_check(Q6.tension(Q6.delta(9)) < 1e-12, "a made-up mind has no tension")
	_check(Q6.argmax(Q6.delta(9)) == 9, "and argmax names the corner it sits on")


# ── 6. one strong line ──────────────────────────────────────────────────────


func _one_strong_line() -> void:
	var bias := PackedFloat64Array()
	bias.resize(6)
	bias.fill(0.0)
	bias[2] = 1.0
	var p := Q6.step(Q6.uniform(), bias, 0.3, 3.0)
	var yang := 0.0
	for h in Q6.STATES:
		if (h & (1 << 2)) != 0:
			yang += p[h]
	_check(yang > 0.95, "one strong line puts >0.95 of the mass on its own half (got %.4f)" % yang)
	_check(absf(_sum(p) - 1.0) < 1e-12, "and the distribution still sums to one")
	var ten := Q6.tension(p)
	_check(ten < 1.0, "a decided line lowers the tension below uniform (%.4f)" % ten)
	_check(ten > 0.8, "but one line out of six leaves five undecided, so it stays high")
	# The five silent lines stay exactly balanced — a strong line 2 must not
	# quietly decide line 5.
	for i in 6:
		if i == 2:
			continue
		var up := 0.0
		for h in Q6.STATES:
			if (h & (1 << i)) != 0:
				up += p[h]
		_check_quiet(absf(up - 0.5) < 1e-9, "line %d stays balanced at half (%.6f)" % [i, up])
	_check(true, "a bias on one line decides that line and leaves the other five alone")
	# The sign is a sign: negate it and the mass moves to the other half.
	bias[2] = -1.0
	var q := Q6.step(Q6.uniform(), bias, 0.3, 3.0)
	var yin := 0.0
	for h in Q6.STATES:
		if (h & (1 << 2)) == 0:
			yin += q[h]
	_check(yin > 0.95, "a negative bias moves the same mass the other way (%.4f)" % yin)


# ── 7. persistence ──────────────────────────────────────────────────────────


func _persistence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for trial in 6:
		var bias := PackedFloat64Array()
		bias.resize(6)
		var want := 0
		for i in 6:
			var b: float = rng.randf_range(0.3, 1.0)
			if rng.randf() < 0.5:
				b = -b
			bias[i] = b
			if b > 0.0:
				want |= 1 << i
		var p := Q6.uniform()
		var last_five := []
		for k in 20:
			p = Q6.step(p, bias, 0.25, 1.5)
			if k >= 15:
				last_five.append(Q6.argmax(p))
		var stable := true
		for a in last_five:
			if a != last_five[0]:
				stable = false
		_check_quiet(stable, "trial %d: argmax stops moving over the last five steps" % trial)
		_check_quiet(
			Q6.argmax(p) == want,
			(
				"trial %d settles on the corner agreeing with all six signs (%d vs %d)"
				% [trial, Q6.argmax(p), want]
			)
		)
		_check_quiet(absf(_sum(p) - 1.0) < 1e-9, "trial %d still sums to one after 20 steps" % trial)
		_check_quiet(Q6.tension(p) < 1.0, "trial %d has made up some of its mind" % trial)
	_check(true, "twenty steps under a fixed six-line bias settle on the corner it points at")
	_check(true, "and the settled corner is stable, not still wandering")


# ── 8. the neighbours are the neighbours ────────────────────────────────────


func _the_neighbours_are_the_neighbours() -> void:
	var origin := 0b011010
	var p := Q6.diffuse(Q6.delta(origin), 0.05)
	var ones := []
	var twos := []
	for h in Q6.STATES:
		var d := Q6.popcount(h ^ origin)
		if d == 1:
			ones.append(p[h])
		elif d == 2:
			twos.append(p[h])
	_check(ones.size() == 6, "a corner of Q6 has exactly six one-line neighbours")
	_check(twos.size() == 15, "and fifteen two-line ones")
	var lo: float = ones[0]
	var hi: float = ones[0]
	for x in ones:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	_check(hi - lo < 1e-12, "all six one-line neighbours hold the same mass (spread %s)" % (hi - lo))
	var worst_two := 0.0
	for x in twos:
		worst_two = maxf(worst_two, x)
	_check(lo > worst_two, "and more than any two-line neighbour (%s vs %s)" % [lo, worst_two])
	_check(p[origin] > hi, "the corner it started on still holds the most")
	# Mass falls off monotonically with distance, all the way to the opposite
	# corner — the cube's metric, not a Euclidean shortcut.
	var by_distance := []
	for d in 7:
		by_distance.append(0.0)
	for h in Q6.STATES:
		var d := Q6.popcount(h ^ origin)
		by_distance[d] = maxf(by_distance[d], p[h])
	for d in range(1, 7):
		_check_quiet(
			by_distance[d] < by_distance[d - 1],
			"distance %d holds less than distance %d" % [d, d - 1]
		)
	_check(true, "mass falls off with the number of lines that differ, out to the opposite corner")
	_check(absf(_sum(p) - 1.0) < 1e-12, "and one small step from a delta still sums to one")
