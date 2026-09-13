class_name Cast
extends RefCounted

## The three ways a figure arrives: a tap (coins), the senses (two elections),
## the room (many peers). All pure and deterministic.
##
## Line values: 6 old yin (yin, moving), 7 young yang, 8 young yin,
##              9 old yang (yang, moving).
## Returned dictionaries: {bits:int, moving:int, throws:Array[int]}


static func seed_of(when_ms: int, who: String, index: int) -> int:
	var s: String = "%d|%s|%d" % [when_ms, who, index]
	return int(s.hash()) ^ (when_ms << 1) ^ (index * 2654435761)


## Three coins, six times. 6:1/8, 7:3/8, 8:3/8, 9:1/8.
static func tap_cast(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bits: int = 0
	var moving: int = 0
	var throws: Array[int] = ([] as Array[int])
	for i in range(6):
		var heads: int = 0
		for c in range(3):
			if rng.randi() & 1 == 1:
				heads += 1
		# 3 heads -> 9, 2 heads -> 8, 1 head -> 7, 0 heads -> 6
		var value: int = 6
		match heads:
			3: value = 9
			2: value = 8
			1: value = 7
			_: value = 6
		throws.append(value)
		if value == 7 or value == 9:
			bits |= 1 << i
		if value == 6 or value == 9:
			moving |= 1 << i
	return {"bits": bits, "moving": moving, "throws": throws}


## Two elections become one figure: machine is the lower (inner) trigram,
## human is the upper (outer) trigram.
static func sense_cast(machine_scores: Array[float], human_scores: Array[float], prev_bits: int = -1) -> Dictionary:
	var m: int = argmax(machine_scores)
	var h: int = argmax(human_scores)
	var bits: int = ((h << 3) | m) & 63
	var moving: int = 0
	if prev_bits >= 0:
		moving = (bits ^ (prev_bits & 63)) & 63
	return {"bits": bits, "moving": moving, "throws": throws_of(bits, moving)}


## Per-line majority across peers. A tie keeps the line of the first peer.
## A line whose majority is thin (margin <= 1) is moving.
static func room_cast(peer_bits: Array[int]) -> Dictionary:
	if peer_bits.is_empty():
		return {"bits": 0, "moving": 0, "throws": throws_of(0, 0)}
	var first: int = peer_bits[0] & 63
	var bits: int = 0
	var moving: int = 0
	for i in range(6):
		var yang: int = 0
		for p in peer_bits:
			if (int(p) >> i) & 1 == 1:
				yang += 1
		var yin: int = peer_bits.size() - yang
		var line: int = 0
		if yang > yin:
			line = 1
		elif yin > yang:
			line = 0
		else:
			line = (first >> i) & 1
		if line == 1:
			bits |= 1 << i
		if absi(yang - yin) <= 1:
			moving |= 1 << i
	return {"bits": bits, "moving": moving, "throws": throws_of(bits, moving)}


static func transform(bits: int, moving: int) -> int:
	return (bits ^ moving) & 63


static func argmax(scores: Array[float]) -> int:
	if scores.is_empty():
		return 0
	var best: int = 0
	for i in range(1, scores.size()):
		if scores[i] > scores[best]:
			best = i
	return best


## Line values implied by a (bits, moving) pair, bottom line first.
static func throws_of(bits: int, moving: int) -> Array[int]:
	var out: Array[int] = ([] as Array[int])
	for i in range(6):
		var yang: bool = ((bits >> i) & 1) == 1
		var mv: bool = ((moving >> i) & 1) == 1
		if yang:
			out.append(9 if mv else 7)
		else:
			out.append(6 if mv else 8)
	return out
