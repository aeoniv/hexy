extends SceneTree

const HuohoutuData = preload("res://scripts/huohoutu_data.gd")

func _init() -> void:
	print("\n--- TEST HUOHOUTU DUAL MANDALA ARCHITECTURE ---")

	# Test 1: Verify HuohoutuData contains all 64 canonical hexagrams
	assert(HuohoutuData.HEXAGRAMS.size() == 64, "HuohoutuData must contain 64 hexagrams")
	assert(HuohoutuData.HEAD_SEQUENCE.size() == 64, "HEAD_SEQUENCE must contain 64 hexagrams")
	assert(HuohoutuData.BODY_SEQUENCE.size() == 64, "BODY_SEQUENCE must contain 64 hexagrams")
	print("Test 1 Passed: HuohoutuData 64 hexagrams and dual 64-sequences verified.")

	# Test 2: Verify RAVE_WHEEL_64 Head Anchor (Gate 41) and BODY_64 Anchor (Gate 1)
	assert(HuohoutuData.HEAD_SEQUENCE[0] == 41, "Head sequence must start at Gate 41 (Rave New Year)")
	assert(HuohoutuData.BODY_SEQUENCE[0] == 1, "Body sequence must start at Gate 1 (Qian / Force)")
	print("Test 2 Passed: Canonical Head (Gate 41) and Body (Gate 1) anchors verified.")

	# Test 3: Test Head Hexagram Retrieval
	var head_h: Dictionary = HuohoutuData.get_head_hex(0)
	assert(head_h["id"] == 41, "Index 0 must return Hexagram 41")
	assert(head_h.has("bin"), "Hexagram 41 must have valid binary")
	print("Test 3 Passed: Head hexagram retrieval verified.")

	# Test 4: Test Body Hexagram Retrieval
	var body_h: Dictionary = HuohoutuData.get_body_hex(0)
	assert(body_h["id"] == 1, "Index 0 must return Hexagram 1")
	assert(body_h["bits"] == 0b111111, "Hexagram 1 must have bits 0b111111")
	print("Test 4 Passed: Body hexagram retrieval verified.")

	# Test 5: Verify Decoupled Head and Body Indexing
	var head_idx: int = HuohoutuData.find_head_index_by_id(19)
	var body_idx: int = HuohoutuData.find_body_index_by_id(19)
	assert(head_idx >= 0 and body_idx >= 0, "Both sequences must resolve Hexagram 19")
	print("Test 5 Passed: Dual decoupled Head and Body indexing verified.")

	print("--- ALL HUOHOUTU DUAL MANDALA TESTS PASSED PERFECTLY ---\n")
	quit(0)
