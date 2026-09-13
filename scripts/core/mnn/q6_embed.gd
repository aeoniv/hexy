class_name Q6Embed
extends RefCounted

## A figure as a point in R^32, with no model needed.
##
## The vector is pure geometry: the six lines as +-1, the two trigrams as
## one-hot corners, and four scalars that place the figure on the King Wen
## number line and on the two wheels. Nothing here is learned, so it is the
## same on every device and in every build.
##
## Layout (32 floats):
##   [0..5]   six lines, bit i = line i+1 from the bottom, yang +1 / yin -1
##   [6..13]  lower trigram one-hot (8)
##   [14..21] upper trigram one-hot (8)
##   [22]     king wen number / 64
##   [23]     head wheel index / 64
##   [24]     body wheel index / 64
##   [25]     popcount / 6
##   [26..31] reserved, zero

const DIM: int = 32


static func vec(bits: int) -> PackedFloat32Array:
	var b: int = bits & 63
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(DIM)
	for i in range(6):
		out[i] = 1.0 if ((b >> i) & 1) == 1 else -1.0
	var lower: int = b & 7
	var upper: int = (b >> 3) & 7
	out[6 + lower] = 1.0
	out[14 + upper] = 1.0
	out[22] = float(KingWen.number(b)) / 64.0
	out[23] = float(maxi(Q6.wheel_index(b, "head"), 0)) / 64.0
	out[24] = float(maxi(Q6.wheel_index(b, "body"), 0)) / 64.0
	out[25] = float(Q6.popcount(b)) / 6.0
	return out


## Cosine DISTANCE in [0, 2]: 0 is the same point, larger is further apart.
static func dist(a_bits: int, b_bits: int) -> float:
	return 1.0 - cosine(vec(a_bits), vec(b_bits))


static func cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var dot: float = 0.0
	var na: float = 0.0
	var nb: float = 0.0
	for i in range(a.size()):
		dot += a[i] * b[i]
		na += a[i] * a[i]
		nb += b[i] * b[i]
	var denom: float = sqrt(na) * sqrt(nb)
	return dot / denom if denom > 0.00001 else 0.0


## Glue a figure vector to a text vector and give the pair unit length, so a
## long text embedding cannot drown out the six lines.
static func fuse(q6_vec: PackedFloat32Array, text_vec: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(q6_vec.size() + text_vec.size())
	var i: int = 0
	for v in q6_vec:
		out[i] = v
		i += 1
	for v in text_vec:
		out[i] = v
		i += 1
	return normalise(out)


static func normalise(v: PackedFloat32Array) -> PackedFloat32Array:
	var sum_sq: float = 0.0
	for x in v:
		sum_sq += x * x
	var n: float = sqrt(sum_sq)
	if n <= 0.00001:
		return v
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(v.size())
	for i in range(v.size()):
		out[i] = v[i] / n
	return out
