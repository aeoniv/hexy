class_name Q6
extends RefCounted

## The 64 figures as the 6-cube Q6: one vertex per hexagram, one edge per
## single moving line. Pure functions only.

const N: int = 64
const DIM: int = 6

const Huohoutu := preload("res://scripts/huohoutu_data.gd")


static func popcount(x: int) -> int:
	var n: int = 0
	var v: int = x & 63
	while v != 0:
		n += v & 1
		v >>= 1
	return n


static func neighbors(bits: int) -> Array[int]:
	var out: Array[int] = ([] as Array[int])
	for i in range(DIM):
		out.append((bits & 63) ^ (1 << i))
	return out


static func distance(a: int, b: int) -> int:
	return popcount((a & 63) ^ (b & 63))


## The walk from the cast figure to the transformed one, turning the moving
## lines bottom to top. Always starts at `bits`; length == popcount(moving)+1.
static func path(bits: int, moving: int) -> Array[int]:
	var out: Array[int] = ([] as Array[int])
	var cur: int = bits & 63
	out.append(cur)
	for i in range(DIM):
		if ((moving >> i) & 1) == 1:
			cur = cur ^ (1 << i)
			out.append(cur)
	return out


## All 192 undirected edges as [a, b] with a < b.
static func edges() -> Array:
	var out: Array = []
	for v in range(N):
		for i in range(DIM):
			var w: int = v ^ (1 << i)
			if v < w:
				out.append([v, w])
	return out


static func adjacency_matrix() -> PackedInt32Array:
	var m := PackedInt32Array()
	m.resize(N * N)
	m.fill(0)
	for v in range(N):
		for i in range(DIM):
			var w: int = v ^ (1 << i)
			m[v * N + w] = 1
	return m


## Per-line majority across peers: the bits of Cast.room_cast, and tied the
## same peer-independent way (smallest id, else lowest bits value).
static func median(peer_bits: Array[int], ids: Array[String] = ([] as Array[String])) -> int:
	if peer_bits.is_empty():
		return 0
	return int(Cast.room_cast(peer_bits, ids)["bits"])


static func flip_all(bits: int) -> int:
	return (~bits) & 63


## The figure stood on its head: line order reversed.
static func reverse(bits: int) -> int:
	var out: int = 0
	for i in range(DIM):
		if ((bits >> i) & 1) == 1:
			out |= 1 << (DIM - 1 - i)
	return out


## The traditional King Wen partner: the overturned figure, or the opposite
## one when overturning changes nothing.
static func king_wen_pair(bits: int) -> int:
	var r: int = reverse(bits & 63)
	return flip_all(bits) if r == (bits & 63) else r


## Position in the HEAD or BODY wheel; -1 if unknown. `which` is "head"|"body".
static func wheel_index(bits: int, which: String) -> int:
	var num: int = KingWen.number(bits)
	var seq: Array[int] = Huohoutu.HEAD_SEQUENCE
	if which.to_lower() == "body":
		seq = Huohoutu.BODY_SEQUENCE
	return seq.find(num)
