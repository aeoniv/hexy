class_name FigureNet
extends RefCounted

## The smallest thing that can be called a net: where the walk on Q6 goes next.
##
## It keeps the last sixteen samples (bits plus the eight machine and eight
## human trigram scores) and a 64x6 table of how often each edge of the cube
## was taken. `predict()` reads the table with Laplace smoothing and then
## nudges the answer with score momentum: the line flips toward the trigram
## whose score is rising fastest.
##
## Everything here is deterministic and runs in a few microseconds. An
## MNN-exported GRU can replace the body of `predict()` later without moving
## the API: push the same samples in, get the same {bits, moving, confidence}
## dictionary out.

const RING: int = 16
const LINES: int = 6
const FIGURES: int = 64
const ALPHA: float = 0.5
const AGREE_PULL: float = 0.15
const DISAGREE_TRIM: float = 0.9
const SAVE_PATH: String = "user://figure_net.json"

var _counts: PackedFloat32Array = PackedFloat32Array()
var _ring: Array[Dictionary] = ([] as Array[Dictionary])


func _init() -> void:
	_counts.resize(FIGURES * LINES)
	clear()


func clear() -> void:
	for i in range(_counts.size()):
		_counts[i] = 0.0
	_ring.clear()


func samples() -> int:
	return _ring.size()


func count_of(bits: int, line: int) -> float:
	return _counts[(bits & 63) * LINES + clampi(line, 0, LINES - 1)]


# --- feeding ----------------------------------------------------------------

func push(bits: int, m_scores: Array, h_scores: Array) -> void:
	var b: int = bits & 63
	if not _ring.is_empty():
		var prev: int = int(_ring[_ring.size() - 1].get("bits", 0))
		var diff: int = prev ^ b
		if Q6.popcount(diff) == 1:
			for i in range(LINES):
				if (diff >> i) & 1 == 1:
					_counts[prev * LINES + i] += 1.0
					break
	_ring.append({
		"bits": b,
		"machine": _eight(m_scores),
		"human": _eight(h_scores),
	})
	while _ring.size() > RING:
		_ring.remove_at(0)


static func _eight(src: Array) -> Array[float]:
	var out: Array[float] = ([] as Array[float])
	for i in range(8):
		out.append(float(src[i]) if i < src.size() else 0.0)
	return out


# --- reading ----------------------------------------------------------------

## {bits:int, moving:int, confidence:float}. `from_bits` defaults to the last
## figure pushed.
func predict(from_bits: int = -1) -> Dictionary:
	var b: int = (from_bits & 63) if from_bits >= 0 else _last_bits()
	var best: int = 0
	var best_count: float = -1.0
	var total: float = 0.0
	for i in range(LINES):
		var c: float = _counts[b * LINES + i]
		total += c
		if c > best_count:
			best_count = c
			best = i
	var p: float = (best_count + ALPHA) / (total + ALPHA * float(LINES))
	var momentum: int = _momentum_line(b)
	var line: int = best
	var conf: float = p
	if momentum >= 0:
		if momentum == best:
			conf = minf(0.99, p + AGREE_PULL * (1.0 - p))
		elif total <= 0.0:
			line = momentum
			conf = p
		else:
			conf = p * DISAGREE_TRIM
	var moving: int = 1 << line
	return {
		"bits": (b ^ moving) & 63,
		"moving": moving,
		"confidence": conf,
	}


func _last_bits() -> int:
	if _ring.is_empty():
		return 0
	return int(_ring[_ring.size() - 1].get("bits", 0))


## The line the rising scores lean on, or -1 when nothing is moving yet.
func _momentum_line(bits: int) -> int:
	if _ring.size() < 2:
		return -1
	var a: Dictionary = _ring[_ring.size() - 2]
	var b: Dictionary = _ring[_ring.size() - 1]
	var mi: int = _fastest(a.get("machine", []), b.get("machine", []))
	var hi: int = _fastest(a.get("human", []), b.get("human", []))
	var mr: float = _rise(a.get("machine", []), b.get("machine", []), mi)
	var hr: float = _rise(a.get("human", []), b.get("human", []), hi)
	if mr <= 0.0 and hr <= 0.0:
		return -1
	if mr >= hr:
		return _toward((bits >> 3) & 7, mi, 3)
	return _toward(bits & 7, hi, 0)


static func _fastest(a: Array, b: Array) -> int:
	var best: int = 0
	var best_d: float = -INF
	for i in range(8):
		var av: float = float(a[i]) if i < a.size() else 0.0
		var bv: float = float(b[i]) if i < b.size() else 0.0
		var d: float = bv - av
		if d > best_d:
			best_d = d
			best = i
	return best


static func _rise(a: Array, b: Array, i: int) -> float:
	var av: float = float(a[i]) if i < a.size() else 0.0
	var bv: float = float(b[i]) if i < b.size() else 0.0
	return bv - av


## The first line of a trigram that would move `cur` toward `target`.
static func _toward(cur: int, target: int, offset: int) -> int:
	var diff: int = (cur ^ target) & 7
	if diff == 0:
		return -1
	for i in range(3):
		if (diff >> i) & 1 == 1:
			return offset + i
	return -1


# --- disk -------------------------------------------------------------------

func save(path: String = SAVE_PATH) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(dump()))
	f.close()
	return true


func load(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false
	restore(parsed as Dictionary)
	return true


func dump() -> Dictionary:
	var counts: Array[float] = ([] as Array[float])
	for v in _counts:
		counts.append(v)
	var ring: Array = []
	for s in _ring:
		ring.append({
			"bits": int(s.get("bits", 0)),
			"machine": Array(s.get("machine", [])),
			"human": Array(s.get("human", [])),
		})
	return {"counts": counts, "ring": ring}


func restore(d: Dictionary) -> void:
	clear()
	var counts: Variant = d.get("counts", [])
	if counts is Array:
		var arr: Array = counts as Array
		for i in range(mini(arr.size(), _counts.size())):
			_counts[i] = float(arr[i])
	var ring: Variant = d.get("ring", [])
	if ring is Array:
		for s in (ring as Array):
			if s is Dictionary:
				var sd: Dictionary = s as Dictionary
				_ring.append({
					"bits": int(sd.get("bits", 0)) & 63,
					"machine": _eight(Array(sd.get("machine", []))),
					"human": _eight(Array(sd.get("human", []))),
				})
	while _ring.size() > RING:
		_ring.remove_at(0)
