class_name KingWen
extends RefCounted

## King Wen naming / numbering for the 64 figures.
##
## BIT CONVENTION (the core's own, shared with SensorOracle):
##   bit i = line i+1 counted from the BOTTOM, yang = 1.
##   lower (inner) trigram = bits & 7
##   upper (outer) trigram = bits >> 3
##   trigram code: 0 Earth, 1 Thunder, 2 Water, 3 Lake,
##                 4 Mountain, 5 Fire, 6 Wind, 7 Heaven
##
## NOTE: scripts/huohoutu_data.gd stores its "bits" with the opposite line
## order (its bit 5 is the bottom line). KingWen is the single place that
## converts, via _mirror(); nothing outside this file needs to know.

const Huohoutu := preload("res://scripts/huohoutu_data.gd")

const TRIGRAM_NAMES: Array[String] = [
	"Earth Kun", "Thunder Zhen", "Water Kan", "Lake Dui",
	"Mountain Gen", "Fire Li", "Wind Xun", "Heaven Qian"
]

## U+2630..U+2637 indexed by trigram code above.
## Heaven 7 = U+2630, Lake 3 = U+2631, Fire 5 = U+2632, Thunder 1 = U+2633,
## Wind 6 = U+2634, Water 2 = U+2635, Mountain 4 = U+2636, Earth 0 = U+2637.
const TRIGRAM_GLYPH_OFFSET: Array[int] = [7, 3, 5, 1, 6, 2, 4, 0]

const HEXAGRAM_GLYPH_BASE: int = 0x4DC0

## ASCII pinyin (no tone marks) in King Wen order, index 0 == hexagram 1.
const PINYIN: Array[String] = [
	"qian", "kun", "zhun", "meng", "xu", "song", "shi", "bi",
	"xiao xu", "lu", "tai", "pi", "tong ren", "da you", "qian", "yu",
	"sui", "gu", "lin", "guan", "shi he", "bi", "bo", "fu",
	"wu wang", "da xu", "yi", "da guo", "kan", "li", "xian", "heng",
	"dun", "da zhuang", "jin", "ming yi", "jia ren", "kui", "jian", "xie",
	"sun", "yi", "guai", "gou", "cui", "sheng", "kun", "jing",
	"ge", "ding", "zhen", "gen", "jian", "gui mei", "feng", "lu",
	"xun", "dui", "huan", "jie", "zhong fu", "xiao guo", "ji ji", "wei ji"
]


## Reverse the six line bits: core order <-> huohoutu order.
static func _mirror(bits: int) -> int:
	var out: int = 0
	for i in range(6):
		if (bits >> i) & 1 == 1:
			out |= 1 << (5 - i)
	return out


static func entry(bits: int) -> Dictionary:
	return Huohoutu.get_by_bits(_mirror(bits & 63))


static func number(bits: int) -> int:
	return int(entry(bits).get("id", 1))


static func bits_of(num: int) -> int:
	var n: int = clampi(num, 1, 64)
	return _mirror(int(Huohoutu.get_hex(n).get("bits", 63)))


static func name(bits: int) -> String:
	return String(entry(bits).get("name", ""))


static func zh(bits: int) -> String:
	return String(entry(bits).get("zh", ""))


static func pinyin(bits: int) -> String:
	return PINYIN[number(bits) - 1]


static func glyph(bits: int) -> String:
	return String.chr(HEXAGRAM_GLYPH_BASE + number(bits) - 1)


static func lower(bits: int) -> int:
	return (bits & 63) & 7


static func upper(bits: int) -> int:
	return (bits & 63) >> 3


static func trigram_name(t: int) -> String:
	return TRIGRAM_NAMES[clampi(t, 0, 7)]


static func trigram_glyph(t: int) -> String:
	return String.chr(0x2630 + TRIGRAM_GLYPH_OFFSET[clampi(t, 0, 7)])


## The eight wedges of the fly's ellipsoid-body radar, in the order they sit
## round the dial (坤 艮 坎 巽 震 离 兑 乾), as trigram codes above. One table so
## the radar and the peers door name a heading with the same glyph.
const WEDGE_TRIGRAM: Array[int] = [0, 4, 2, 6, 1, 5, 3, 7]


## Which wedge a heading in radians falls in: round(heading / (TAU/8)) mod 8.
static func wedge_of(heading_rad: float) -> int:
	return posmod(int(round(heading_rad / (TAU / 8.0))), 8)


static func heading_glyph(heading_rad: float) -> String:
	return trigram_glyph(WEDGE_TRIGRAM[wedge_of(heading_rad)])


static func lines(bits: int) -> Array[int]:
	## Bottom line first.
	var out: Array[int] = ([] as Array[int])
	for i in range(6):
		out.append((bits >> i) & 1)
	return out


# --- wheels -----------------------------------------------------------------

static func _step(bits: int, seq: Array[int], delta: int) -> int:
	var idx: int = seq.find(number(bits))
	if idx == -1:
		idx = 0
	return bits_of(seq[posmod(idx + delta, seq.size())])


static func head_next(bits: int) -> int:
	return _step(bits, Huohoutu.HEAD_SEQUENCE, 1)


static func head_prev(bits: int) -> int:
	return _step(bits, Huohoutu.HEAD_SEQUENCE, -1)


static func body_next(bits: int) -> int:
	return _step(bits, Huohoutu.BODY_SEQUENCE, 1)


static func body_prev(bits: int) -> int:
	return _step(bits, Huohoutu.BODY_SEQUENCE, -1)
