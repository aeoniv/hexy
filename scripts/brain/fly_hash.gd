class_name FlyHash
extends RefCounted

## SPARSE RANDOM PROJECTION HASH — the mushroom body's trick, over text.
##
## The fly projects ~50 glomeruli into ~2000 Kenyon cells through a sparse,
## fixed, random wiring, then keeps only the few percent that fired hardest.
## Two odours that smell alike light the same cells; two that do not, do not.
## That is a locality sensitive hash, and it works just as well over a 768-dim
## sentence embedding as it does over antennal lobe activity.
##
## The wiring is drawn once from a seed and never changes, so the same vector
## always lands on the same cells, on this install and on the next session.
##
## hash() allocates nothing but the 64-word output: every scratch buffer is a
## member, sized once in _init.

const SAMPLES_PER_CELL := 8   ## claws per Kenyon cell, as in the animal (~6-8)
const BINS := 512             ## histogram buckets for the top-K threshold

var input_dim: int = 768
var cells: int = 2048
var active: int = 102
var seed: int = 0

## Flat cells*SAMPLES_PER_CELL wiring: which input each claw reads, and whether
## the synapse is excitatory (+1) or inhibitory (-1).
var _idx: PackedInt32Array = PackedInt32Array()
var _sign: PackedFloat32Array = PackedFloat32Array()

# Scratch, allocated once.
var _scores: PackedFloat32Array = PackedFloat32Array()
var _binof: PackedInt32Array = PackedInt32Array()
var _bins: PackedInt32Array = PackedInt32Array()

var _words: int = 64


func _init(p_input_dim: int = 768, p_cells: int = 2048, p_active: int = 102, p_seed: int = 0x64_46_46_42) -> void:
	input_dim = maxi(1, p_input_dim)
	cells = maxi(32, p_cells)
	active = clampi(p_active, 1, cells)
	seed = p_seed
	_words = int(ceil(float(cells) / 32.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = cells * SAMPLES_PER_CELL
	_idx.resize(n)
	_sign.resize(n)
	for i in range(n):
		_idx[i] = rng.randi_range(0, input_dim - 1)
		_sign[i] = 1.0 if rng.randf() < 0.5 else -1.0

	_scores.resize(cells)
	_binof.resize(cells)
	_bins.resize(BINS)


func word_count() -> int:
	return _words


## Projects a vector onto the Kenyon cells and returns the top-`active` cells as
## a packed bitmask (`word_count()` words of 32 bits).
func hash(vec: PackedFloat32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(_words)
	if vec.size() < input_dim:
		out.fill(0)
		return out

	var mn: float = INF
	var mx: float = -INF
	var b: int = 0
	# Local aliases: packed arrays are copy-on-write, and reading through a
	# local is measurably cheaper than reading through a member every claw.
	var idx: PackedInt32Array = _idx
	var sgn: PackedFloat32Array = _sign
	for c in range(cells):
		var s: float = (
			vec[idx[b]] * sgn[b]
			+ vec[idx[b + 1]] * sgn[b + 1]
			+ vec[idx[b + 2]] * sgn[b + 2]
			+ vec[idx[b + 3]] * sgn[b + 3]
			+ vec[idx[b + 4]] * sgn[b + 4]
			+ vec[idx[b + 5]] * sgn[b + 5]
			+ vec[idx[b + 6]] * sgn[b + 6]
			+ vec[idx[b + 7]] * sgn[b + 7]
		)
		_scores[c] = s
		if s < mn:
			mn = s
		if s > mx:
			mx = s
		b += SAMPLES_PER_CELL

	out.fill(0)
	if mx <= mn:
		# Degenerate input: fire the first `active` cells so the shape is right.
		for c in range(active):
			out[c >> 5] = out[c >> 5] | (1 << (c & 31))
		return out

	# Top-K by histogram: cheaper than a sort and allocates nothing.
	var scale: float = float(BINS - 1) / (mx - mn)
	_bins.fill(0)
	for c in range(cells):
		var bi: int = int((_scores[c] - mn) * scale)
		_binof[c] = bi
		_bins[bi] = _bins[bi] + 1

	var acc: int = 0
	var cut: int = 0
	for bi in range(BINS - 1, -1, -1):
		acc += _bins[bi]
		if acc >= active:
			cut = bi
			break
	# Cells strictly above the cut bin all fire; the cut bin fills the remainder.
	var above: int = acc - _bins[cut]
	var remaining: int = active - above
	for c in range(cells):
		var bi2: int = _binof[c]
		if bi2 > cut:
			out[c >> 5] = out[c >> 5] | (1 << (c & 31))
		elif bi2 == cut and remaining > 0:
			out[c >> 5] = out[c >> 5] | (1 << (c & 31))
			remaining -= 1
	return out


## Bits that differ between two hashes. 0 = identical context.
static func hamming(a: PackedInt32Array, b: PackedInt32Array) -> int:
	var n: int = mini(a.size(), b.size())
	var dist: int = 0
	for i in range(n):
		var u: int = (a[i] ^ b[i]) & 0xFFFFFFFF
		while u != 0:
			u = u & (u - 1)
			dist += 1
	return dist


## 1.0 = same cells, 0.0 = disjoint cells.
func similarity(a: PackedInt32Array, b: PackedInt32Array) -> float:
	return clampf(1.0 - float(hamming(a, b)) / float(2 * active), 0.0, 1.0)
