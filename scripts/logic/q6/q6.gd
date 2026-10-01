extends RefCounted

func vertex(lines: int) -> Dictionary:
	if lines < 0 or lines > 63:
		return {}
	return {"lines": lines, "dimension": 6}

func distance(a: Variant, b: Variant) -> Variant:
	if not (a is int and b is int) or a < 0 or a > 63 or b < 0 or b > 63:
		return null
	var bits: int = a ^ b
	var count: int = 0
	while bits != 0:
		count += bits & 1
		bits >>= 1
	return count

func judge(human: Variant, hexy: Variant) -> Dictionary:
	return {"H": human, "X": hexy, "d": distance(human, hexy)}
