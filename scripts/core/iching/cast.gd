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


## Per-line majority across peers, read the same way on every phone.
##
## A tie cannot be broken by "the first peer": each phone lists itself first,
## so first is a different person on every device and the room would disagree
## with itself. The anchor is therefore a property of the SET -- the peer with
## the smallest `who` when ids are passed, otherwise the numerically lowest
## bits value -- which every phone computes identically.
##
## A line whose majority is thin (margin <= 1) is moving. One voice alone has
## no margin to be thin: a room of one is not a room arguing with itself, so
## nothing moves.
static func room_cast(peer_bits: Array[int], ids: Array[String] = ([] as Array[String])) -> Dictionary:
	if peer_bits.is_empty():
		return {"bits": 0, "moving": 0, "throws": throws_of(0, 0)}
	var anchor: int = int(peer_bits[anchor_index(peer_bits, ids)]) & 63
	var alone: bool = peer_bits.size() <= 1
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
			line = (anchor >> i) & 1
		if line == 1:
			bits |= 1 << i
		if not alone and absi(yang - yin) <= 1:
			moving |= 1 << i
	return {"bits": bits, "moving": moving, "throws": throws_of(bits, moving)}


## Which peer a tied line is read from: smallest id when ids line up with the
## bits, else the lowest bits value. Never the caller's own position.
static func anchor_index(peer_bits: Array[int], ids: Array[String] = ([] as Array[String])) -> int:
	if peer_bits.is_empty():
		return 0
	var best: int = 0
	var by_id: bool = ids.size() == peer_bits.size()
	for i in range(1, peer_bits.size()):
		if by_id:
			if String(ids[i]) < String(ids[best]):
				best = i
		elif (int(peer_bits[i]) & 63) < (int(peer_bits[best]) & 63):
			best = i
	return best


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
