class_name IChing
extends RefCounted

## One door onto the oracle: naming (KingWen), casting (Cast), and the
## shape of the 64 (Q6).

# --- naming -----------------------------------------------------------------

static func number(bits: int) -> int:
	return KingWen.number(bits)


static func bits_of(num: int) -> int:
	return KingWen.bits_of(num)


static func name_of(bits: int) -> String:
	return KingWen.name(bits)


static func pinyin(bits: int) -> String:
	return KingWen.pinyin(bits)


static func glyph(bits: int) -> String:
	return KingWen.glyph(bits)


static func trigram_name(t: int) -> String:
	return KingWen.trigram_name(t)


static func trigram_glyph(t: int) -> String:
	return KingWen.trigram_glyph(t)


# --- casting ----------------------------------------------------------------

static func tap_cast(seed: int) -> Dictionary:
	return Cast.tap_cast(seed)


static func sense_cast(machine_scores: Array[float], human_scores: Array[float], prev_bits: int = -1) -> Dictionary:
	return Cast.sense_cast(machine_scores, human_scores, prev_bits)


static func room_cast(peer_bits: Array[int]) -> Dictionary:
	return Cast.room_cast(peer_bits)


static func transform(bits: int, moving: int) -> int:
	return Cast.transform(bits, moving)


# --- shape ------------------------------------------------------------------

static func neighbors(bits: int) -> Array[int]:
	return Q6.neighbors(bits)


static func distance(a: int, b: int) -> int:
	return Q6.distance(a, b)


static func path(bits: int, moving: int) -> Array[int]:
	return Q6.path(bits, moving)


# --- the sentence a figure can say about itself -----------------------------

static func describe(bits: int, moving: int) -> Dictionary:
	var b: int = bits & 63
	var t: int = Cast.transform(b, moving)
	var names: Array[String] = ([] as Array[String])
	for n in Q6.neighbors(b):
		names.append(KingWen.name(n))
	return {
		"number": KingWen.number(b),
		"name": KingWen.name(b),
		"pinyin": KingWen.pinyin(b),
		"glyph": KingWen.glyph(b),
		"upper": KingWen.trigram_name(KingWen.upper(b)),
		"lower": KingWen.trigram_name(KingWen.lower(b)),
		"transformed_number": KingWen.number(t),
		"transformed_name": KingWen.name(t),
		"neighbors_names": names,
		"distance_to_transformed": Q6.distance(b, t),
	}
