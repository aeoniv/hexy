class_name HuohoutuData
extends RefCounted

## Canonical Huohoutu (火候圖) Data Engine from ix64-core
## Combines Head (Sun/Macrocosm: RAVE_WHEEL_64) and Body (Moon/Microcosm: BODY_64)

# All 64 Hexagrams Canonical Catalog
const HEXAGRAMS: Dictionary = {
	1: {"id": 1, "bits": 63, "bin": "111111", "name": "Force", "zh": "乾", "py": ""},
	2: {"id": 2, "bits": 0, "bin": "000000", "name": "Field", "zh": "坤", "py": ""},
	3: {"id": 3, "bits": 34, "bin": "100010", "name": "Sprouting", "zh": "屯", "py": ""},
	4: {"id": 4, "bits": 17, "bin": "010001", "name": "Enveloping", "zh": "蒙", "py": ""},
	5: {"id": 5, "bits": 58, "bin": "111010", "name": "Attending", "zh": "需", "py": ""},
	6: {"id": 6, "bits": 23, "bin": "010111", "name": "Arguing", "zh": "訟", "py": ""},
	7: {"id": 7, "bits": 16, "bin": "010000", "name": "Leading", "zh": "師", "py": ""},
	8: {"id": 8, "bits": 2, "bin": "000010", "name": "Grouping", "zh": "比", "py": ""},
	9: {"id": 9, "bits": 59, "bin": "111011", "name": "Small Accumulating", "zh": "小畜", "py": ""},
	10: {"id": 10, "bits": 55, "bin": "110111", "name": "Treading", "zh": "履", "py": ""},
	11: {"id": 11, "bits": 56, "bin": "111000", "name": "Pervading", "zh": "泰", "py": ""},
	12: {"id": 12, "bits": 7, "bin": "000111", "name": "Obstruction", "zh": "否", "py": ""},
	13: {"id": 13, "bits": 47, "bin": "101111", "name": "Concording People", "zh": "同人", "py": ""},
	14: {"id": 14, "bits": 61, "bin": "111101", "name": "Great Possessing", "zh": "大有", "py": ""},
	15: {"id": 15, "bits": 8, "bin": "001000", "name": "Humbling", "zh": "謙", "py": ""},
	16: {"id": 16, "bits": 4, "bin": "000100", "name": "Providing-For", "zh": "豫", "py": ""},
	17: {"id": 17, "bits": 38, "bin": "100110", "name": "Following", "zh": "隨", "py": ""},
	18: {"id": 18, "bits": 25, "bin": "011001", "name": "Corrupting", "zh": "蠱", "py": ""},
	19: {"id": 19, "bits": 48, "bin": "110000", "name": "Nearing", "zh": "臨", "py": ""},
	20: {"id": 20, "bits": 3, "bin": "000011", "name": "Viewing", "zh": "觀", "py": ""},
	21: {"id": 21, "bits": 37, "bin": "100101", "name": "Gnawing Bite", "zh": "噬嗑", "py": ""},
	22: {"id": 22, "bits": 41, "bin": "101001", "name": "Adorning", "zh": "賁", "py": ""},
	23: {"id": 23, "bits": 1, "bin": "000001", "name": "Stripping", "zh": "剝", "py": ""},
	24: {"id": 24, "bits": 32, "bin": "100000", "name": "Returning", "zh": "復", "py": ""},
	25: {"id": 25, "bits": 39, "bin": "100111", "name": "Without Embroiling", "zh": "無妄", "py": ""},
	26: {"id": 26, "bits": 57, "bin": "111001", "name": "Great Accumulating", "zh": "大畜", "py": ""},
	27: {"id": 27, "bits": 33, "bin": "100001", "name": "Swallowing", "zh": "頤", "py": ""},
	28: {"id": 28, "bits": 30, "bin": "011110", "name": "Great Exceeding", "zh": "大過", "py": ""},
	29: {"id": 29, "bits": 18, "bin": "010010", "name": "Gorge", "zh": "坎", "py": ""},
	30: {"id": 30, "bits": 45, "bin": "101101", "name": "Radiance", "zh": "離", "py": ""},
	31: {"id": 31, "bits": 14, "bin": "001110", "name": "Conjoining", "zh": "咸", "py": ""},
	32: {"id": 32, "bits": 28, "bin": "011100", "name": "Persevering", "zh": "恆", "py": ""},
	33: {"id": 33, "bits": 15, "bin": "001111", "name": "Retiring", "zh": "遯", "py": ""},
	34: {"id": 34, "bits": 60, "bin": "111100", "name": "Great Invigorating", "zh": "大壯", "py": ""},
	35: {"id": 35, "bits": 5, "bin": "000101", "name": "Prospering", "zh": "晉", "py": ""},
	36: {"id": 36, "bits": 40, "bin": "101000", "name": "Brightness Hiding", "zh": "明夷", "py": ""},
	37: {"id": 37, "bits": 43, "bin": "101011", "name": "Dwelling People", "zh": "家人", "py": ""},
	38: {"id": 38, "bits": 53, "bin": "110101", "name": "Polarising", "zh": "睽", "py": ""},
	39: {"id": 39, "bits": 10, "bin": "001010", "name": "Limping", "zh": "蹇", "py": ""},
	40: {"id": 40, "bits": 20, "bin": "010100", "name": "Taking-Apart", "zh": "解", "py": ""},
	41: {"id": 41, "bits": 49, "bin": "110001", "name": "Diminishing", "zh": "損", "py": ""},
	42: {"id": 42, "bits": 35, "bin": "100011", "name": "Augmenting", "zh": "益", "py": ""},
	43: {"id": 43, "bits": 62, "bin": "111110", "name": "Parting", "zh": "夬", "py": ""},
	44: {"id": 44, "bits": 31, "bin": "011111", "name": "Coupling", "zh": "姤", "py": ""},
	45: {"id": 45, "bits": 6, "bin": "000110", "name": "Clustering", "zh": "萃", "py": ""},
	46: {"id": 46, "bits": 24, "bin": "011000", "name": "Ascending", "zh": "升", "py": ""},
	47: {"id": 47, "bits": 22, "bin": "010110", "name": "Confining", "zh": "困", "py": ""},
	48: {"id": 48, "bits": 26, "bin": "011010", "name": "Welling", "zh": "井", "py": ""},
	49: {"id": 49, "bits": 46, "bin": "101110", "name": "Skinning", "zh": "革", "py": ""},
	50: {"id": 50, "bits": 29, "bin": "011101", "name": "Holding", "zh": "鼎", "py": ""},
	51: {"id": 51, "bits": 36, "bin": "100100", "name": "Shake", "zh": "震", "py": ""},
	52: {"id": 52, "bits": 9, "bin": "001001", "name": "Bound", "zh": "艮", "py": ""},
	53: {"id": 53, "bits": 11, "bin": "001011", "name": "Infiltrating", "zh": "漸", "py": ""},
	54: {"id": 54, "bits": 52, "bin": "110100", "name": "Converting The Maiden", "zh": "歸妹", "py": ""},
	55: {"id": 55, "bits": 44, "bin": "101100", "name": "Abounding", "zh": "豐", "py": ""},
	56: {"id": 56, "bits": 13, "bin": "001101", "name": "Sojourning", "zh": "旅", "py": ""},
	57: {"id": 57, "bits": 27, "bin": "011011", "name": "Ground", "zh": "巽", "py": ""},
	58: {"id": 58, "bits": 54, "bin": "110110", "name": "Open", "zh": "兌", "py": ""},
	59: {"id": 59, "bits": 19, "bin": "010011", "name": "Dispersing", "zh": "渙", "py": ""},
	60: {"id": 60, "bits": 50, "bin": "110010", "name": "Articulating", "zh": "節", "py": ""},
	61: {"id": 61, "bits": 51, "bin": "110011", "name": "Centre Confirming", "zh": "中孚", "py": ""},
	62: {"id": 62, "bits": 12, "bin": "001100", "name": "Small Exceeding", "zh": "小過", "py": ""},
	63: {"id": 63, "bits": 42, "bin": "101010", "name": "Already_Fording", "zh": "既濟", "py": ""},
	64: {"id": 64, "bits": 21, "bin": "010101", "name": "Not-Yet Fording", "zh": "未濟", "py": ""},
}

# HEAD 64-SEQUENCE: RAVE_WHEEL_64 (Macrocosm Sun-Pulse Oracle Wheel)
const HEAD_SEQUENCE: Array[int] = [
	41, 19, 13, 49, 30, 55, 37, 63, 22, 36, 25, 17, 21, 51, 42, 3,
	27, 24, 2, 23, 8, 20, 16, 35, 45, 12, 15, 52, 39, 53, 62, 56,
	31, 33, 7, 4, 29, 59, 40, 64, 47, 6, 46, 18, 48, 57, 32, 50,
	28, 44, 1, 43, 14, 34, 9, 5, 26, 11, 10, 58, 38, 54, 61, 60
]

# BODY 64-SEQUENCE: BODY_64 (Microcosm Polarity Cycle Squared - Body Tensegrity Wheel)
const BODY_SEQUENCE: Array[int] = [
	1, 57, 59, 53, 20, 42, 37, 61, 9, 50, 29, 39, 8, 3, 63, 60,
	5, 18, 4, 52, 23, 27, 22, 41, 26, 46, 48, 15, 2, 24, 36, 19,
	11, 32, 40, 62, 16, 51, 55, 54, 34, 7, 64, 56, 35, 21, 30, 38,
	14, 28, 47, 31, 45, 17, 49, 58, 43, 44, 6, 33, 12, 25, 13, 10
]

static func get_hex(id: int) -> Dictionary:
	return HEXAGRAMS.get(id, HEXAGRAMS[1])

static func get_by_bits(bits: int) -> Dictionary:
	for id in HEXAGRAMS:
		if HEXAGRAMS[id]["bits"] == bits:
			return HEXAGRAMS[id]
	return HEXAGRAMS[1]

static func get_head_hex(idx: int) -> Dictionary:
	var safe_idx: int = posmod(idx, HEAD_SEQUENCE.size())
	return get_hex(HEAD_SEQUENCE[safe_idx])

static func get_body_hex(idx: int) -> Dictionary:
	var safe_idx: int = posmod(idx, BODY_SEQUENCE.size())
	return get_hex(BODY_SEQUENCE[safe_idx])

static func find_head_index_by_id(id: int) -> int:
	var idx: int = HEAD_SEQUENCE.find(id)
	return idx if idx != -1 else 0

static func find_body_index_by_id(id: int) -> int:
	var idx: int = BODY_SEQUENCE.find(id)
	return idx if idx != -1 else 0
