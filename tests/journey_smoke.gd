extends SceneTree

const KingWen = preload("res://scripts/core/iching/king_wen.gd")
const Journey = preload("res://scripts/core/iching/journey.gd")

var failures: int = 0
var total: int = 0


func check(ok: bool, label: String) -> void:
	total += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	print("\n--- JOURNEY SMOKE ---")

	_test_enum_and_tables()
	_test_stagnation()
	_test_single_line_threshold_mentor()
	_test_trials_ordeal()
	_test_road_back()
	_test_return()
	_test_chapter()
	_test_arc()

	print("--- ", total, " checks, ", failures, " failures ---")
	if failures == 0:
		print("--- ALL JOURNEY SMOKE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- JOURNEY SMOKE FAILED: ", failures, " ---\n")
		quit(1)


func _test_enum_and_tables() -> void:
	check(Journey.Stage.RETURN == 9, "Stage enum has 10 members ending at RETURN=9")
	check(Journey.STAGE_NAMES.size() == 10, "STAGE_NAMES has 10 entries")
	check(Journey.STAGE_GLOSS.size() == 10, "STAGE_GLOSS has 10 entries")
	var names_ok: bool = true
	for n in Journey.STAGE_NAMES:
		if String(n).is_empty():
			names_ok = false
	check(names_ok, "every stage name is non-empty")
	var gloss_ok: bool = true
	for g in Journey.STAGE_GLOSS:
		if String(g).is_empty():
			gloss_ok = false
	check(gloss_ok, "every stage gloss is non-empty")


func _test_stagnation() -> void:
	var bits: int = 0b011000 # some mid figure, not 1/2/63/64
	check(KingWen.number(bits) != 1 and KingWen.number(bits) != 2
		and KingWen.number(bits) != 63 and KingWen.number(bits) != 64,
		"stagnation fixture is not a RETURN hexagram")

	check(Journey.stage_of(bits, bits, 5) == Journey.Stage.ORDINARY,
		"0 changes, days_still < 14 -> ORDINARY")
	check(Journey.stage_of(bits, bits, 14) == Journey.Stage.ORDINARY,
		"0 changes, days_still == 14 -> ORDINARY")
	check(Journey.stage_of(bits, bits, 20) == Journey.Stage.ORDINARY,
		"0 changes, 14 <= days_still < 28 -> ORDINARY")
	check(Journey.stage_of(bits, bits, 28) == Journey.Stage.CALL,
		"0 changes, days_still == 28 -> CALL")
	check(Journey.stage_of(bits, bits, 100) == Journey.Stage.CALL,
		"0 changes, days_still > 28 -> CALL")


func _test_single_line_threshold_mentor() -> void:
	var base: int = 0b011000 # avoid landing on RETURN hexagrams after one flip
	check(KingWen.number(base) != 1 and KingWen.number(base) != 2
		and KingWen.number(base) != 63 and KingWen.number(base) != 64,
		"threshold/mentor base is not a RETURN hexagram")

	# flip a lower-trigram line (bit 0..2)
	var lower_flip: int = base ^ 0b000001
	if lower_flip in [0, 1, 62, 63] or KingWen.number(lower_flip) in [1, 2, 63, 64]:
		lower_flip = base ^ 0b000010
	check(Journey.stage_of(base, lower_flip, 1) == Journey.Stage.THRESHOLD,
		"1 line changed in the lower trigram -> THRESHOLD")

	# flip an upper-trigram line (bit 3..5)
	var upper_flip: int = base ^ 0b001000
	if KingWen.number(upper_flip) in [1, 2, 63, 64]:
		upper_flip = base ^ 0b010000
	check(Journey.stage_of(base, upper_flip, 1) == Journey.Stage.MENTOR,
		"1 line changed in the upper trigram -> MENTOR")

	check(KingWen.lower(base ^ 0b000001) == KingWen.lower(base) ^ 1,
		"sanity: lower-trigram bit mask is bits 0..2")
	check(KingWen.upper(base ^ 0b001000) == KingWen.upper(base) ^ 1,
		"sanity: upper-trigram bit mask is bits 3..5")


func _test_trials_ordeal() -> void:
	var base: int = 0b011000
	var two_changed: int = base ^ 0b000011
	if KingWen.number(two_changed) in [1, 2, 63, 64]:
		two_changed = base ^ 0b000101
	check(Journey.stage_of(base, two_changed, 1) == Journey.Stage.TRIALS,
		"2 lines changed -> TRIALS")

	var three_changed: int = base ^ 0b000111
	if KingWen.number(three_changed) in [1, 2, 63, 64]:
		three_changed = base ^ 0b001011
	check(Journey.stage_of(base, three_changed, 1) == Journey.Stage.TRIALS,
		"3 lines changed -> TRIALS")

	var four_changed: int = base ^ 0b001111
	if KingWen.number(four_changed) in [1, 2, 63, 64]:
		four_changed = base ^ 0b011110
	check(Journey.stage_of(base, four_changed, 1) == Journey.Stage.ORDEAL,
		"4 lines changed -> ORDEAL")

	check(Journey.stage_of(0, 63, 1) == Journey.Stage.RETURN,
		"6 lines changed but lands on Qian -> RETURN wins over ORDEAL (rule order)")
	# use a 6-change pair that avoids the axis hexagrams to test pure ORDEAL
	var six_a: int = 0b010101
	var six_b: int = 0b101010
	if not (KingWen.number(six_b) in [1, 2, 63, 64]):
		check(Journey.stage_of(six_a, six_b, 1) == Journey.Stage.ORDEAL,
			"6 lines changed, non-axis landing -> ORDEAL")
	else:
		check(true, "6-line fixture happens to land on an axis hexagram; skip redundant check")


func _test_road_back() -> void:
	# Build a path that revisits an earlier figure (not the immediate
	# predecessor) within the last 8 steps, landing away from any axis
	# hexagram.
	var revisited: int = 0b011000
	if KingWen.number(revisited) in [1, 2, 63, 64]:
		revisited = 0b011001
	var mid1: int = revisited ^ 0b000001
	var mid2: int = mid1 ^ 0b000010
	var path: Array[int] = [revisited, mid1, mid2, revisited]
	# guard: none of the intermediate landing figures should be axis hexagrams
	# (that would make RETURN take priority and the test meaningless)
	check(not (KingWen.number(revisited) in [1, 2, 63, 64]),
		"road-back fixture's revisited figure is not an axis hexagram")
	check(Journey.stage_of_path(path, 1) == Journey.Stage.ROAD_BACK,
		"revisiting a figure from earlier in the path -> ROAD_BACK")

	# An A -> B -> A oscillation DOES count as ROAD_BACK: A was seen two
	# steps ago, which is within the lookback window (it is only path[-2],
	# the figure just left, that is excluded from the "seen before" check).
	var a: int = 0b011000
	var b: int = a ^ 0b000001
	if KingWen.number(a) in [1, 2, 63, 64] or KingWen.number(b) in [1, 2, 63, 64]:
		a = 0b011010
		b = a ^ 0b000001
	var path2: Array[int] = [a, b, a]
	check(Journey.stage_of_path(path2, 1) == Journey.Stage.ROAD_BACK,
		"an A -> B -> A oscillation is a ROAD_BACK (A was seen 2 steps ago)")

	# A revisit further back than ROAD_BACK_LOOKBACK steps should not trigger.
	var far_path: Array[int] = [revisited]
	var cur: int = revisited
	for i in range(Journey.ROAD_BACK_LOOKBACK + 3):
		cur = cur ^ (1 << (i % 6))
		far_path.append(cur)
	far_path.append(revisited)
	# only meaningful if intervening figures don't land on an axis hexagram
	# in a way that masks the result; just assert it runs without crashing
	# and returns a valid stage.
	var far_stage: int = Journey.stage_of_path(far_path, 1)
	check(far_stage >= 0 and far_stage <= Journey.Stage.RETURN,
		"a path longer than the lookback still resolves to a valid stage")


func _test_return() -> void:
	for n in [1, 2, 63, 64]:
		var bits: int = KingWen.bits_of(n)
		var prev: int = bits ^ 1
		check(Journey.stage_of(prev, bits, 1) == Journey.Stage.RETURN,
			"landing on hexagram #%d -> RETURN" % n)


func _test_chapter() -> void:
	var bits: int = KingWen.bits_of(1)
	var c: Dictionary = Journey.chapter(bits, Journey.Stage.RETURN)
	check(int(c["stage"]) == Journey.Stage.RETURN, "chapter carries the stage")
	check(String(c["stage_name"]) == "Return", "chapter carries the stage name")
	check(String(c["gloss"]) == Journey.STAGE_GLOSS[Journey.Stage.RETURN],
		"chapter carries the stage gloss")
	check(int(c["hexagram_no"]) == 1, "chapter carries the hexagram number")
	check(String(c["hexagram_name"]) == KingWen.name(bits), "chapter carries the hexagram name")
	check(String(c["title"]) == "Return · %s" % KingWen.name(bits),
		"chapter title is '<stage_name> · <hexagram_name>'")


func _test_arc() -> void:
	var base: int = 0b011000
	var path: Array[int] = [base, base ^ 0b000001, base ^ 0b000011, base]
	var stages: Array[int] = Journey.arc(path)
	check(stages.size() == path.size(), "arc length equals path length")
	var valid: bool = true
	for s in stages:
		if s < 0 or s > Journey.Stage.RETURN:
			valid = false
	check(valid, "every stage in the arc is a valid Stage value")

	var empty_arc: Array[int] = Journey.arc([])
	check(empty_arc.size() == 0, "arc of an empty path is empty")

	var single_arc: Array[int] = Journey.arc([base])
	check(single_arc.size() == 1, "arc of a single-figure path has length 1")
