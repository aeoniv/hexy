extends SceneTree

## GROUP-EQUIVARIANCE for the pure GDScript cube (scripts/core/iching/q6_lattice.gd,
## wrapped by Q6Core(false)): Q6 is Z2^6, corners are the 64 hexagrams, edges are
## single line flips, and every line mask g in 0..63 acts on corners by
## x -> x XOR g -- a graph automorphism of the hypercube (XOR by a fixed g just
## relabels which corner is which, and preserves "differs in one line").
##
## THE BIAS TRANSFORM. q6_lattice.gd's potential is PER-LINE:
##   U[h] = sum_i bias[i] * line_sign(h, i),   line_sign(h,i) = +1 if bit i set.
## Flipping bit i of h negates line_sign(h,i), so line_sign(h^g, i) is
## line_sign(h,i) if g's bit i is 0, and -line_sign(h,i) if g's bit i is 1. That
## makes U[h^g] equal the potential of h computed against a bias with entry i
## negated wherever g's line i is set -- the SAME rule the file already documents
## for the g = 63 case (FLIP commutes with `negate_bias`, which negates every
## entry because every bit of 63 is set). So the general transform is:
##   bias'[i] = bias[i] * (g's bit i set ? -1 : +1)
## Diffusion is a heat kernel over the cube's own Cayley graph, which XOR-by-g
## leaves invariant (it's a translation of the group Z2^6), so it commutes with
## the relabelling for free; only the Gibbs term needed a transformed bias.
##
## WHAT TRANSFORMS AND HOW, given q6_relabelled = q6_original relabelled by g:
##   reset(bits), inject(bits), anchor(bits, amt) -> same op with bits ^ g
##   step(bias, t, beta)                          -> same op with bias' above
##   uniform()                                    -> uniform() (g fixes it)
##   state()[x]                                   -> equals original state()[x^g]
##   argmax()                                     -> equals original argmax() ^ g
##   tension()                                     -> UNCHANGED (entropy of a
##     relabelled distribution is the same multiset of masses)
##   best_neighbour(bits)                          -> equals original
##     best_neighbour(bits ^ g), returning the SAME LINE INDEX, not g-shifted:
##     (bits^g) ^ (1<<i) relabels to bits ^ (1<<i) under the same g, for every i,
##     so the six neighbour masses permute among themselves by index, not by
##     the line label i itself.

const Q6CoreScript = preload("res://scripts/logic/q6/q6_core.gd")

var failures: int = 0
var checks: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST Q6 GROUP-EQUIVARIANCE (x -> x XOR g on the Q6 cube) ---")

	var gs: Array[int] = [0, 1, 0b100000, 0b010101, 63]
	var seeds: Array[int] = [1, 2, 3]

	for g in gs:
		for sd in seeds:
			_test_g(g, sd)

	check(checks > len(gs) * len(seeds), "more than one assertion ran per case")

	# B8: FORCED TIES. Lowest-index tie-breaking is not XOR-equivariant; the
	# reference-corner rule must be, for every g including g = 63.
	var tie_gs: Array[int] = [0, 1, 0b000110, 0b100000, 0b010101, 0b101010, 63]
	var refs: Array[int] = [0, 5, 17, 42, 63]
	for g in tie_gs:
		for r in refs:
			_test_forced_ties(g, r)

	if failures == 0:
		print("--- ALL Q6 EQUIVARIANCE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- Q6 EQUIVARIANCE TESTS FAILED: ", failures, " ---\n")
		quit(1)


## bias'[i] = -bias[i] when line i of g is set, else bias[i] unchanged.
func transform_bias(bias: PackedFloat64Array, g: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(bias.size())
	for i in bias.size():
		out[i] = -bias[i] if ((g >> i) & 1) == 1 else bias[i]
	return out


func _random_bias(rng: RandomNumberGenerator) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(6)
	for i in 6:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


func _test_g(g: int, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd

	var a: Q6Core = Q6CoreScript.new(false)  # plain, no native
	var b: Q6Core = Q6CoreScript.new(false)  # relabelled by g throughout

	var label := "g=%d seed=%d" % [g, sd]

	# -- reset --------------------------------------------------------------
	var start_bits: int = rng.randi() % 64
	a.reset(start_bits)
	b.reset(start_bits ^ g)
	_check_relabelled(a, b, g, label + " after reset")

	# -- inject -------------------------------------------------------------
	var inj_bits: int = rng.randi() % 64
	a.inject(inj_bits)
	b.inject(inj_bits ^ g)
	_check_relabelled(a, b, g, label + " after inject")

	# -- anchor -------------------------------------------------------------
	var anc_bits: int = rng.randi() % 64
	var anc_amt: float = rng.randf_range(0.1, 0.9)
	a.anchor(anc_bits, anc_amt)
	b.anchor(anc_bits ^ g, anc_amt)
	_check_relabelled(a, b, g, label + " after anchor")

	# -- step (diffuse + Gibbs pull under a random bias) ---------------------
	for _i in range(3):
		var bias: PackedFloat64Array = _random_bias(rng)
		var t: float = rng.randf_range(0.05, 1.5)
		var beta: float = rng.randf_range(0.5, 4.0)
		a.step(bias, t, beta)
		b.step(transform_bias(bias, g), t, beta)
		_check_relabelled(a, b, g, label + " after step")

	# -- another anchor + inject to mix things up ----------------------------
	var anc2_bits: int = rng.randi() % 64
	a.anchor(anc2_bits, 0.5)
	b.anchor(anc2_bits ^ g, 0.5)
	_check_relabelled(a, b, g, label + " after second anchor")


## Assert that b's state, argmax and best_neighbour are exactly a's, relabelled
## by g, and that tension agrees with no transform at all.
func _check_relabelled(a: Q6Core, b: Q6Core, g: int, label: String) -> void:
	var pa: PackedFloat64Array = a.state()
	var pb: PackedFloat64Array = b.state()
	var worst: float = 0.0
	for h in range(64):
		var d: float = absf(pb[h ^ g] - pa[h])
		worst = maxf(worst, d)
	check(worst < 1e-9, label + ": state[x^g] matches (worst %s)" % worst)

	check(b.argmax() == (a.argmax() ^ g), label + ": argmax^g matches")

	check(is_equal_approx(a.tension(), b.tension()) or
			absf(a.tension() - b.tension()) < 1e-9,
			label + ": tension is unchanged by relabelling")

	# best_neighbour: same LINE INDEX for corresponding corners (see header note).
	var bits: int = 17  # any fixed corner; equivariance must hold at every one
	check(a.best_neighbour(bits) == b.best_neighbour(bits ^ g),
			label + ": best_neighbour(bits) == best_neighbour(bits^g), same line")


## A 64-vector with equal mass on every corner in `corners`, zero elsewhere.
func _tied(corners: Array[int]) -> PackedFloat64Array:
	var p := PackedFloat64Array()
	p.resize(64)
	p.fill(0.0)
	for c in corners:
		p[c & 63] = 1.0 / float(corners.size())
	return p


## FORCED TIES under relabelling by g, with the reference corner r (set by
## reset) moving to r ^ g. Every tie set below is relabelled corner by corner.
func _test_forced_ties(g: int, r: int) -> void:
	var label := "tie g=%d ref=%d" % [g, r]
	var a: Q6Core = Q6CoreScript.new(false)
	var b: Q6Core = Q6CoreScript.new(false)

	# 1. uniform: all 64 corners tie; the reference itself wins, on both sides.
	a.reset(r)
	b.reset(r ^ g)
	a.uniform()
	b.uniform()
	check(a.argmax() == r, label + " uniform: argmax is the reference corner")
	check(b.argmax() == (a.argmax() ^ g), label + " uniform: argmax^g matches")

	# 2. two corners at DIFFERENT Hamming distance from r: nearer one wins.
	var near: int = r ^ 0b000001
	var far: int = r ^ 0b000111
	a.reset(r)
	b.reset(r ^ g)
	a.set_state(_tied([far, near]))
	b.set_state(_tied([far ^ g, near ^ g]))
	check(a.argmax() == near, label + " near/far: nearest corner to ref wins")
	check(b.argmax() == (a.argmax() ^ g), label + " near/far: argmax^g matches")

	# 3. several corners at the SAME distance: the canonical offset breaks it.
	var same: Array[int] = [r ^ 0b110000, r ^ 0b000101, r ^ 0b000011, r ^ 0b011000]
	var same_g: Array[int] = []
	for c in same:
		same_g.append(c ^ g)
	a.reset(r)
	b.reset(r ^ g)
	a.set_state(_tied(same))
	b.set_state(_tied(same_g))
	check(a.argmax() == (r ^ 0b000011), label + " equidistant: lowest offset h^ref wins")
	check(b.argmax() == (a.argmax() ^ g), label + " equidistant: argmax^g matches")

	# 4. the pure lattice call, with the reference passed explicitly.
	var p: PackedFloat64Array = _tied([r ^ 0b100001, r ^ 0b010010, r ^ 0b001100])
	var pg := PackedFloat64Array()
	pg.resize(64)
	for h in 64:
		pg[h ^ g] = p[h]
	check(Q6CoreScript.Lattice.argmax(pg, r ^ g) == (Q6CoreScript.Lattice.argmax(p, r) ^ g),
			label + " Lattice.argmax(p^g, ref^g) == Lattice.argmax(p, ref) ^ g")

	# 5. a tie made by the dynamics: anchor splits mass between two corners.
	a.reset(r ^ 0b001001)
	b.reset(r ^ 0b001001 ^ g)
	a.anchor(r ^ 0b100100, 0.5)
	b.anchor(r ^ 0b100100 ^ g, 0.5)
	check(b.argmax() == (a.argmax() ^ g), label + " anchor tie: argmax^g matches")
