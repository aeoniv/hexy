class_name IChingData
extends RefCounted

const TRIGRAMS = [
	{"name": "Earth", "zh": "坤", "bits": 0b000, "nature": "Receptive"},
	{"name": "Thunder", "zh": "震", "bits": 0b001, "nature": "Arousing"},
	{"name": "Water", "zh": "坎", "bits": 0b010, "nature": "Abysmal"},
	{"name": "Lake", "zh": "兌", "bits": 0b011, "nature": "Joyous"},
	{"name": "Mountain", "zh": "艮", "bits": 0b100, "nature": "Stillness"},
	{"name": "Fire", "zh": "離", "bits": 0b101, "nature": "Clinging"},
	{"name": "Wind", "zh": "巽", "bits": 0b110, "nature": "Gentle"},
	{"name": "Heaven", "zh": "乾", "bits": 0b111, "nature": "Creative"}
]

const HEXAGRAMS: Array = [
	{"num": 1, "bits": 0b111111, "zh": "乾", "name": "The Creative", "judgment": "Supreme success through active creative force."},
	{"num": 2, "bits": 0b000000, "zh": "坤", "name": "The Receptive", "judgment": "Supreme success through quiet perseverance."},
	{"num": 3, "bits": 0b010001, "zh": "屯", "name": "Difficulty at the Beginning", "judgment": "Initial struggle; supreme success through steadfast perseverance."},
	{"num": 4, "bits": 0b100010, "zh": "蒙", "name": "Youthful Folly", "judgment": "Inexperience transformed through disciplined learning."},
	{"num": 5, "bits": 0b111010, "zh": "需", "name": "Waiting", "judgment": "Patience in nourishment; light and success follow perseverance."},
	{"num": 6, "bits": 0b010111, "zh": "訟", "name": "Conflict", "judgment": "Cautious moderation; seek mediator rather than prolong struggle."},
	{"num": 7, "bits": 0b000010, "zh": "師", "name": "The Army", "judgment": "Discipline, unity, and experienced leadership ensure good fortune."},
	{"num": 8, "bits": 0b010000, "zh": "比", "name": "Holding Together", "judgment": "Union brings good fortune; mutual trust creates harmony."},
	{"num": 9, "bits": 0b111110, "zh": "小畜", "name": "Small Taming", "judgment": "Gentle restraint prepares substantial progress."},
	{"num": 10, "bits": 0b011111, "zh": "履", "name": "Treading", "judgment": "Careful action through danger leads to success."},
	{"num": 11, "bits": 0b111000, "zh": "泰", "name": "Peace", "judgment": "Harmony between heaven and earth; small departs, great approaches."},
	{"num": 12, "bits": 0b000111, "zh": "否", "name": "Standstill", "judgment": "Stagnation and obstruction; the wise person preserves inner virtue."},
	{"num": 13, "bits": 0b111101, "zh": "同人", "name": "Fellowship", "judgment": "Fellowship with others in open clarity."},
	{"num": 14, "bits": 0b101111, "zh": "大有", "name": "Great Possession", "judgment": "Great abundance guided by virtue and clarity."},
	{"num": 15, "bits": 0b000100, "zh": "謙", "name": "Modesty", "judgment": "Modesty brings progress; fullness yields to humility."},
	{"num": 16, "bits": 0b001000, "zh": "豫", "name": "Enthusiasm", "judgment": "Inspiring harmony; movement aligned with purpose."},
	{"num": 17, "bits": 0b011001, "zh": "隨", "name": "Following", "judgment": "Adapting to the time brings great success."},
	{"num": 18, "bits": 0b100110, "zh": "蠱", "name": "Work on Decay", "judgment": "Restoring order from neglect; renewal through resolve."},
	{"num": 19, "bits": 0b110000, "zh": "臨", "name": "Approach", "judgment": "Power approaches; vigilant cultivation ensures longevity."},
	{"num": 20, "bits": 0b000011, "zh": "觀", "name": "Contemplation", "judgment": "Profound observation inspires trust and clarity."},
	{"num": 21, "bits": 0b101001, "zh": "噬嗑", "name": "Biting Through", "judgment": "Penetrating obstacles; justice and clarity resolve deadlock."},
	{"num": 22, "bits": 0b100101, "zh": "賁", "name": "Grace", "judgment": "Inner substance illuminated by beauty and simplicity."},
	{"num": 23, "bits": 0b000001, "zh": "剝", "name": "Splitting Apart", "judgment": "Yield calmly to cyclical decline; await natural renewal."},
	{"num": 24, "bits": 0b100000, "zh": "復", "name": "Return", "judgment": "The turning point; light returns from below; natural renewal."},
	{"num": 25, "bits": 0b111001, "zh": "無妄", "name": "Innocence", "judgment": "Natural truth without calculation; spontaneous action."},
	{"num": 26, "bits": 0b100111, "zh": "大畜", "name": "Great Taming", "judgment": "Accumulation of wisdom; strength held in reserve."},
	{"num": 27, "bits": 0b100001, "zh": "頤", "name": "Nourishment", "judgment": "Careful nourishment of body and spirit."},
	{"num": 28, "bits": 0b011110, "zh": "大過", "name": "Preponderance of Great", "judgment": "Exceptional courage needed to cross difficult thresholds."},
	{"num": 29, "bits": 0b010010, "zh": "坎", "name": "The Abysmal", "judgment": "Flowing through danger without losing sincerity."},
	{"num": 30, "bits": 0b101101, "zh": "離", "name": "The Clinging", "judgment": "Lucid fire clinging to fuel; clarity rooted in perseverance."},
	{"num": 53, "bits": 0b110100, "zh": "漸", "name": "Development", "judgment": "Gradual progress like a tree growing on the mountain."},
	{"num": 63, "bits": 0b101010, "zh": "既濟", "name": "After Completion", "judgment": "Order achieved; vigilance maintains balance."},
	{"num": 64, "bits": 0b010101, "zh": "未濟", "name": "Before Completion", "judgment": "The cycle begins anew; boundless potential unfolds."}
]

static func cast_coins() -> Dictionary:
	var lines: Array[int] = []
	var moving_lines: Array[int] = []
	var hex_bits: int = 0
	
	for i in range(6):
		var coin_sum = 0
		for c in range(3):
			coin_sum += 3 if randf() > 0.5 else 2
		lines.append(coin_sum)
		
		var is_yang = (coin_sum == 7 or coin_sum == 9)
		if is_yang:
			hex_bits |= (1 << i)
		
		if coin_sum == 6 or coin_sum == 9:
			moving_lines.append(i + 1)
	
	return {
		"lines": lines,
		"bits": hex_bits,
		"moving": moving_lines
	}

static func find_by_bits(bits: int) -> Dictionary:
	for h in HEXAGRAMS:
		if h["bits"] == bits:
			return h
	return {"num": 1, "bits": bits, "zh": "卦", "name": "Hexagram %d" % bits, "judgment": "Balance through continuous transformation."}
