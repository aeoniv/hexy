class_name Q6Lattice
extends RefCounted
## THE SIX-BIT CUBE, AS PURE ARITHMETIC — 64 hexagrams laid out as the corners
## of Q6, the six-dimensional hypercube, where two hexagrams are neighbours
## exactly when one line differs.
##
## A distribution over the 64 corners moves by two forces and nothing else:
##
##   DIFFUSION — a heat step along the edges of the cube. Done in the Walsh
##   basis, where the graph Laplacian is diagonal: the Fast Walsh–Hadamard
##   transform turns the whole thing into one multiply per coefficient,
##   exp(-t * popcount(k)), because the Walsh function chi_k is an
##   eigenvector of the cube's Laplacian with eigenvalue popcount(k). The
##   zero coefficient is the total mass, and it is multiplied by exp(0) = 1,
##   so diffusion never creates or loses probability.
##
##   POTENTIAL — a per-line bias in [-1, 1], one entry per line, positive
##   favouring yang. It becomes a field U over the corners, and a Gibbs
##   reweighting exp(beta * U) pulls mass toward the corners the lines agree
##   with. Nothing else touches the distribution.
##
## THE SYMMETRIES ARE THE POINT. The cube has them and the dynamics must
## respect them, so the test can falsify a wrong implementation without any
## reference numbers to compare against:
##
##   FLIP (h -> h ^ 63, every line inverted) commutes with negating the bias.
##   REVERSE (bit order reversed, the hexagram turned upside down) commutes
##   with reversing the bias.
##
## This module has ZERO CALLERS and is not wired to anything — no UI, no
## model, no autoload. It is arithmetic with a test around it. It earns a
## caller only if real sensor traces make a distribution over six lines mean
## something; until then it stays a leaf.
##
## Bit i (0..5) is line i, and line 0 is the BOTTOM line — the same order
## `scripts/creature/hexagram.gd` reads its lines in. A set bit is yang.

const LINES := 6
const STATES := 64  # 1 << LINES
const ALL_LINES := 63  # STATES - 1


## The sign of line `i` in hexagram `h`: +1 for yang, -1 for yin.
static func line_sign(h: int, i: int) -> float:
	return 1.0 if (h & (1 << i)) != 0 else -1.0


## Number of set bits in `k`, over the six lines. The Walsh eigenvalue.
static func popcount(k: int) -> int:
	var n := 0
	for i in LINES:
		if (k & (1 << i)) != 0:
			n += 1
	return n


## THE FIELD OVER THE CORNERS. `bias` holds six numbers in [-1, 1], one per
## line; U[h] is their signed sum against h's own lines, so the corner that
## agrees with every bias sits at the top of the field.
static func potential_from_lines(bias: PackedFloat64Array) -> PackedFloat64Array:
	assert(bias.size() == LINES)
	var u := PackedFloat64Array()
	u.resize(STATES)
	for h in STATES:
		var s := 0.0
		for i in LINES:
			s += bias[i] * line_sign(h, i)
		u[h] = s
	return u


## FAST WALSH–HADAMARD, unnormalised. Its own inverse up to a factor of 64.
static func fwht(v: PackedFloat64Array) -> PackedFloat64Array:
	assert(v.size() == STATES)
	var w := v.duplicate()
	var span := 1
	while span < STATES:
		var i := 0
		while i < STATES:
			for j in range(i, i + span):
				var a := w[j]
				var b := w[j + span]
				w[j] = a + b
				w[j + span] = a - b
			i += span << 1
		span <<= 1
	return w


## ONE HEAT STEP ALONG THE EDGES. Transform, damp each coefficient by
## exp(-t * popcount(k)), transform back and divide by 64. The k = 0
## coefficient is the total mass and is left alone, so the sum is preserved
## exactly; large t drives everything toward uniform.
static func diffuse(p: PackedFloat64Array, t: float) -> PackedFloat64Array:
	assert(p.size() == STATES)
	var c := fwht(p)
	for k in STATES:
		c[k] = c[k] * exp(-t * float(popcount(k)))
	var out := fwht(c)
	for h in STATES:
		out[h] = out[h] / float(STATES)
	return out


## DIFFUSE, THEN LISTEN. The heat step spreads the distribution over the cube;
## the Gibbs factor exp(beta * U) pulls it back toward the corners the six
## lines point at. Renormalised to sum 1.
static func step(
	p: PackedFloat64Array, bias: PackedFloat64Array, t: float, beta: float
) -> PackedFloat64Array:
	var q := diffuse(p, t)
	var u := potential_from_lines(bias)
	var total := 0.0
	for h in STATES:
		var v: float = q[h] * exp(beta * u[h])
		q[h] = v
		total += v
	if total <= 0.0:
		return uniform()
	for h in STATES:
		q[h] = q[h] / total
	return q


## The corner holding the most mass. Ties go to the lowest index, so the
## answer is the state's and never chance's.
static func argmax(p: PackedFloat64Array) -> int:
	var best := 0
	for h in STATES:
		if p[h] > p[best]:
			best = h
	return best


## TENSION — normalised Shannon entropy in [0, 1]. 1 is a distribution with
## nothing to say; 0 is one that has made up its mind.
static func tension(p: PackedFloat64Array) -> float:
	var total := 0.0
	for h in STATES:
		total += p[h]
	if total <= 0.0:
		return 0.0
	var ent := 0.0
	for h in STATES:
		var q: float = p[h] / total
		if q > 0.0:
			ent -= q * log(q)
	return clampf(ent / log(float(STATES)), 0.0, 1.0)


## Every line inverted — the hexagram's opposite.
static func flip(h: int) -> int:
	return h ^ ALL_LINES


## The hexagram turned upside down: bit order reversed over six lines.
static func reverse(h: int) -> int:
	var r := 0
	for i in LINES:
		if (h & (1 << i)) != 0:
			r |= 1 << (LINES - 1 - i)
	return r


## Move a whole 64-vector by `flip`: the mass at h ends up at flip(h).
static func perm_flip(p: PackedFloat64Array) -> PackedFloat64Array:
	return _permute(p, true)


## Move a whole 64-vector by `reverse`.
static func perm_reverse(p: PackedFloat64Array) -> PackedFloat64Array:
	return _permute(p, false)


static func _permute(p: PackedFloat64Array, by_flip: bool) -> PackedFloat64Array:
	assert(p.size() == STATES)
	var out := PackedFloat64Array()
	out.resize(STATES)
	for h in STATES:
		out[flip(h) if by_flip else reverse(h)] = p[h]
	return out


## The six biases in the other order, to go with `perm_reverse`.
static func reverse_bias(bias: PackedFloat64Array) -> PackedFloat64Array:
	assert(bias.size() == LINES)
	var out := PackedFloat64Array()
	out.resize(LINES)
	for i in LINES:
		out[LINES - 1 - i] = bias[i]
	return out


## The six biases negated, to go with `perm_flip`.
static func negate_bias(bias: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(bias.size())
	for i in bias.size():
		out[i] = -bias[i]
	return out


## Mass spread evenly over all 64 corners.
static func uniform() -> PackedFloat64Array:
	var p := PackedFloat64Array()
	p.resize(STATES)
	p.fill(1.0 / float(STATES))
	return p


## All the mass on one corner.
static func delta(h: int) -> PackedFloat64Array:
	var p := PackedFloat64Array()
	p.resize(STATES)
	p.fill(0.0)
	p[h & ALL_LINES] = 1.0
	return p
