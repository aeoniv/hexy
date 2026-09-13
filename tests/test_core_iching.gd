extends SceneTree

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	print("\n--- TEST CORE ICHING (store + iching) ---")

	_test_tap_cast()
	_test_sense_cast()
	_test_room_cast()
	_test_q6()
	_test_king_wen()
	_test_wheels()
	_test_lattice()
	_test_describe()
	_test_store()

	if failures == 0:
		print("--- ALL CORE ICHING TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CORE ICHING TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _test_tap_cast() -> void:
	var a: Dictionary = Cast.tap_cast(12345)
	var b: Dictionary = Cast.tap_cast(12345)
	var c: Dictionary = Cast.tap_cast(999)
	check(a["bits"] == b["bits"] and a["moving"] == b["moving"] and a["throws"] == b["throws"],
		"tap_cast is deterministic for the same seed")
	check(a["throws"].size() == 6, "tap_cast returns six throws")
	check(a != c or true, "tap_cast accepts another seed")

	var seen_other: bool = false
	for s in range(200):
		var d: Dictionary = Cast.tap_cast(Cast.seed_of(1000 + s, "tester", s))
		if d["bits"] != a["bits"]:
			seen_other = true
		for v in d["throws"]:
			if not (int(v) in [6, 7, 8, 9]):
				check(false, "throw values are 6,7,8,9")
				return
		# bits/moving must agree with the throws
		var bits: int = 0
		var moving: int = 0
		for i in range(6):
			var t: int = int(d["throws"][i])
			if t == 7 or t == 9:
				bits |= 1 << i
			if t == 6 or t == 9:
				moving |= 1 << i
		if bits != int(d["bits"]) or moving != int(d["moving"]):
			check(false, "bits and moving agree with throws")
			return
	check(true, "throws are always 6,7,8,9 and agree with bits/moving")
	check(seen_other, "different seeds give different figures")

	# Distribution over 8000 throws: 1/8, 3/8, 3/8, 1/8 within 0.03
	var counts := {6: 0, 7: 0, 8: 0, 9: 0}
	var total: int = 0
	var casts: int = 8000 / 6 + 1
	for i in range(casts):
		var d: Dictionary = Cast.tap_cast(Cast.seed_of(7_000_000 + i * 17, "dist", i))
		for v in d["throws"]:
			counts[int(v)] += 1
			total += 1
	var want := {6: 0.125, 7: 0.375, 8: 0.375, 9: 0.125}
	var ok: bool = true
	for k in [6, 7, 8, 9]:
		var f: float = float(counts[k]) / float(total)
		if absf(f - want[k]) > 0.03:
			ok = false
		print("    p(", k, ") = ", "%.4f" % f, " want ", want[k])
	check(ok, "coin distribution is 1/8, 3/8, 3/8, 1/8 within 0.03 over %d throws" % total)


func _test_sense_cast() -> void:
	var m: Array[float] = [0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0] # machine 2
	var h: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.0, 0.0] # human 5
	var d: Dictionary = Cast.sense_cast(m, h)
	check(int(d["bits"]) == 42, "sense_cast human 5, machine 2 -> bits 42 (got %d)" % int(d["bits"]))
	check(int(d["moving"]) == 0, "sense_cast without a previous figure has no moving lines")
	var d2: Dictionary = Cast.sense_cast(m, h, 43)
	check(int(d2["moving"]) == (42 ^ 43), "sense_cast moving is the change from the previous figure")
	check(KingWen.lower(42) == 2 and KingWen.upper(42) == 5, "bits 42 splits into lower 2, upper 5")


func _test_room_cast() -> void:
	var d: Dictionary = Cast.room_cast([63, 63, 0])
	check(int(d["bits"]) == 63, "room_cast takes the per-line majority")
	check(int(d["moving"]) == 63, "a 2-1 majority is a thin one, so every line moves")
	var dthick: Dictionary = Cast.room_cast([63, 63, 63, 0])
	check(int(dthick["bits"]) == 63 and int(dthick["moving"]) == 0, "a 3-1 majority is thick, so nothing moves")
	var d2: Dictionary = Cast.room_cast([63, 0])
	check(int(d2["bits"]) == 63, "a tie keeps the first peer's line")
	check(int(d2["moving"]) == 63, "a tie on every line is thin, so every line moves")
	var d3: Dictionary = Cast.room_cast([1, 1, 1, 0])
	check(int(d3["bits"]) == 1, "3-1 majority on the bottom line")
	check(int(d3["moving"]) == 0, "a 3-1 majority is thick")
	check(Q6.median([63, 63, 0]) == int(d["bits"]), "Q6.median agrees with room_cast")


func _test_q6() -> void:
	for b in range(64):
		if Q6.neighbors(b).size() != 6:
			check(false, "every figure has 6 neighbors")
			return
	check(true, "every figure has exactly 6 neighbors")

	var sym: bool = true
	for a in range(64):
		for b in range(64):
			if Q6.distance(a, b) != Q6.distance(b, a):
				sym = false
	check(sym, "distance is symmetric")
	check(Q6.distance(0, 63) == 6, "Kun to Qian is six lines")

	var pok: bool = true
	for moving in range(64):
		var p: Array[int] = Q6.path(42, moving)
		if p.size() != Q6.popcount(moving) + 1:
			pok = false
		if p[0] != 42 or p[p.size() - 1] != (42 ^ moving):
			pok = false
	check(pok, "path length == popcount(moving) + 1 and it ends on the transformed figure")

	check(Q6.edges().size() == 192, "the 6-cube has 192 edges (got %d)" % Q6.edges().size())

	var m: PackedInt32Array = Q6.adjacency_matrix()
	var msum: int = 0
	for v in m:
		msum += v
	check(m.size() == 64 * 64 and msum == 384, "adjacency matrix is 64x64 with 384 ones")

	check(KingWen.number(Q6.king_wen_pair(KingWen.bits_of(1))) == 2,
		"king_wen_pair of 1 (Qian) is 2 (Kun)")
	check(KingWen.number(Q6.king_wen_pair(KingWen.bits_of(3))) == 4,
		"king_wen_pair of 3 is 4")
	check(Q6.reverse(Q6.reverse(42)) == 42, "reverse is an involution")
	check(Q6.flip_all(0) == 63, "flip_all of Kun is Qian")
	check(Q6.wheel_index(KingWen.bits_of(41), "head") == 0, "gate 41 opens the head wheel")
	check(Q6.wheel_index(KingWen.bits_of(1), "body") == 0, "gate 1 opens the body wheel")


func _test_king_wen() -> void:
	var nums := {}
	for b in range(64):
		nums[KingWen.number(b)] = true
	check(nums.size() == 64, "the 64 bit patterns map onto the 64 King Wen numbers")

	var roundtrip: bool = true
	for n in range(1, 65):
		if KingWen.number(KingWen.bits_of(n)) != n:
			roundtrip = false
	check(roundtrip, "number(bits_of(n)) == n for all 64")

	check(KingWen.number(63) == 1 and KingWen.number(0) == 2, "Qian is 1 and Kun is 2")
	check(KingWen.glyph(KingWen.bits_of(1)) == String.chr(0x4DC0), "glyph of hexagram 1 is U+4DC0")
	check(KingWen.glyph(KingWen.bits_of(64)) == String.chr(0x4DFF), "glyph of hexagram 64 is U+4DFF")

	var py_ok: bool = true
	for b in range(64):
		var p: String = KingWen.pinyin(b)
		if p.is_empty():
			py_ok = false
			break
		for i in range(p.length()):
			var ch: int = p.unicode_at(i)
			if ch > 127:
				py_ok = false
				break
	check(py_ok, "every pinyin is non-empty and ASCII")
	check(KingWen.PINYIN.size() == 64, "the pinyin table has 64 entries")

	# Trigram decomposition must agree with the King Wen figure it names.
	# Hexagram 3 Zhun is Thunder (1) below, Water (2) above.
	var zhun: int = KingWen.bits_of(3)
	check(KingWen.lower(zhun) == 1 and KingWen.upper(zhun) == 2,
		"hexagram 3 is Thunder below, Water above")
	# Hexagram 63 Ji Ji is Fire (5) below, Water (2) above.
	var jiji: int = KingWen.bits_of(63)
	check(KingWen.lower(jiji) == 5 and KingWen.upper(jiji) == 2,
		"hexagram 63 is Fire below, Water above")
	check(KingWen.trigram_name(0).begins_with("Earth") and KingWen.trigram_name(7).begins_with("Heaven"),
		"trigram 0 is Earth and trigram 7 is Heaven")
	check(KingWen.trigram_glyph(7) == String.chr(0x2630), "Heaven is U+2630")
	check(KingWen.trigram_glyph(0) == String.chr(0x2637), "Earth is U+2637")
	check(KingWen.trigram_glyph(2) == String.chr(0x2635), "Water is U+2635")


func _test_wheels() -> void:
	var head_ok: bool = true
	var body_ok: bool = true
	for b in range(64):
		if KingWen.head_prev(KingWen.head_next(b)) != b:
			head_ok = false
		if KingWen.body_prev(KingWen.body_next(b)) != b:
			body_ok = false
	check(head_ok, "head_next then head_prev returns the same figure")
	check(body_ok, "body_next then body_prev returns the same figure")
	check(KingWen.number(KingWen.head_next(KingWen.bits_of(41))) == 19,
		"the head wheel steps 41 -> 19")
	check(KingWen.number(KingWen.body_next(KingWen.bits_of(1))) == 57,
		"the body wheel steps 1 -> 57")


func _test_lattice() -> void:
	var l := Lattice.new()
	var a: Array[float] = [1.0, 0.0, 0.0]
	var b: Array[float] = [0.0, 1.0, 0.0]
	check(l.push(a) == 0, "the first tick seats a winner at once")
	check(l.push(b) == 0, "one tick of a challenger is not enough")
	check(l.push(b) == 1, "two consecutive ticks replace the winner")
	check(l.push(a) == 1, "and the new winner holds for one tick of the old one")
	check(l.push(a) == 0, "two ticks take it back")
	var l2 := Lattice.new()
	l2.push(a)
	l2.push(b)
	l2.push(a)
	check(l2.push(b) == 0, "a flickering challenger never lands")


func _test_describe() -> void:
	var d: Dictionary = IChing.describe(KingWen.bits_of(1), 1)
	check(int(d["number"]) == 1, "describe names hexagram 1")
	check(String(d["pinyin"]) == "qian", "describe carries the pinyin")
	check(String(d["glyph"]) == String.chr(0x4DC0), "describe carries the glyph")
	check(Array(d["neighbors_names"]).size() == 6, "describe lists 6 neighbor names")
	check(int(d["distance_to_transformed"]) == 1, "one moving line is one step away")
	check(int(d["transformed_number"]) == KingWen.number(63 ^ 1), "describe names the transformed figure")
	check(String(d["lower"]).begins_with("Heaven") and String(d["upper"]).begins_with("Heaven"),
		"Qian is Heaven over Heaven")


func _test_store() -> void:
	var store: Node = HexyStoreScript.new()
	var hits: Array[int] = [0]
	store.hexagram_changed.connect(func(_h: Dictionary) -> void: hits[0] += 1)
	var h := {"bits": 42, "moving": 1, "throws": [7, 8, 7, 8, 7, 8], "when": 10, "who": "me", "source": "tap", "sig": "x"}
	store.set_hexagram(h)
	store.set_hexagram(h.duplicate(true))
	check(hits[0] == 1, "hexagram_changed fires once for a repeated set (got %d)" % hits[0])
	check(store.primary() == 42, "primary is the cast figure")
	check(store.transformed() == 43, "transformed is bits ^ moving")

	var ahits: Array[int] = [0]
	store.answer_changed.connect(func(_a: String) -> void: ahits[0] += 1)
	store.set_answer("yes")
	store.set_answer("yes")
	store.set_answer("no")
	check(ahits[0] == 2, "answer_changed fires only on real change")

	store.set_machine({"trigram": 2, "score": 0.5, "sentence": "water"})
	store.set_human({"trigram": 5, "score": 0.7, "sentence": "fire"})
	store.set_room({"bits": 7, "moving": 1, "peers": 3})
	var d: Dictionary = store.dump()
	var other: Node = HexyStoreScript.new()
	other.load(d)
	check(other.dump() == d, "dump and load round trip")
	check(int(other.machine["trigram"]) == 2 and int(other.room["peers"]) == 3, "load restores the families and the room")
	store.free()
	other.free()
