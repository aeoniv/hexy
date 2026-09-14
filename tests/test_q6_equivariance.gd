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

const Q6CoreScript = preload("res://scripts/core/iching/q6.gd")

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
