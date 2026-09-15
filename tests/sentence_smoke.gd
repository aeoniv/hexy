extends SceneTree

## SENTENCE IS PURE, SO IT IS TESTED WITHOUT A PHONE.
##
## Same inputs -> same string, every line has a non-empty word at both bits
## and at strong leanings either way, the room phrase's four shapes, and a
## sweep of every body against every day phase that never crashes, never
## capitalises, and never runs past 48 characters.

const SentenceScript := preload("res://scripts/core/sentence.gd")

var passes := 0
var failures := 0


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func _init() -> void:
	print("HEXY_TEST: Sentence pure smoke...")
	_test_word_tables()
	_test_room_phrase()
	_test_determinism()
	_test_day_word()
	_test_missing_keys()
	_test_sweep()
	print("\n=== SENTENCE RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Sentence verified)")
	quit(0 if failures == 0 else 1)


func _test_word_tables() -> void:
	print("\n- word_for_line: every line has a word at 0, at 1, and at both leanings")
	for line in range(6):
		var w0 := SentenceScript.word_for_line(line, 0, 0.0)
		var w1 := SentenceScript.word_for_line(line, 1, 0.0)
		check(w0 != "", "line %d has a non-empty word at value 0" % line)
		check(w1 != "", "line %d has a non-empty word at value 1" % line)
		check(w0 != w1, "line %d's word at 0 differs from its word at 1" % line)

		var wp := SentenceScript.word_for_line(line, 0, 0.5)
		var wm := SentenceScript.word_for_line(line, 1, -0.5)
		check(wp != "", "line %d has a non-empty word at leaning +0.5" % line)
		check(wm != "", "line %d has a non-empty word at leaning -0.5" % line)
		## A LOUD MARK OVERRULES THE BIT: leaning +0.5 on a nominally-yin line
		## still reads as the yang word, and the reverse.
		check(wp == SentenceScript.word_for_line(line, 1, 0.0),
			"line %d: +0.5 leaning overrides value 0 to read as value 1" % line)
		check(wm == SentenceScript.word_for_line(line, 0, 0.0),
			"line %d: -0.5 leaning overrides value 1 to read as value 0" % line)

		var wu := SentenceScript.word_for_line(line, -1, 0.0)
		check(wu != "", "line %d has a non-empty neutral word for an unknown bit" % line)
		var words := "%s%s%s" % [w0, w1, wu]
		check(words == words.to_lower(), "line %d's words are already lowercase" % line)


func _test_room_phrase() -> void:
	print("\n- room_phrase: alone / one near / n near / in phase")
	check(SentenceScript.room_phrase([]) == "alone", "no peers is alone")
	check(SentenceScript.room_phrase([{"who": "a"}]) == "one near", "one peer is one near")
	check(SentenceScript.room_phrase([{"who": "a"}, {"who": "b"}, {"who": "c"}]) == "3 near",
		"three peers count themselves")
	check(SentenceScript.room_phrase([{"who": "a", "in_phase": true}]) == "one in phase",
		"an explicit in_phase peer is heard over the head count")
	check(SentenceScript.room_phrase([{"who": "a"}, {"who": "b", "in_phase": true}]) == "one in phase",
		"one in-phase peer among several still says in phase")
	check(SentenceScript.room_phrase(
		[{"who": "a", "own_phase": 0.50, "phase": 0.52}]) == "one in phase",
		"a phase within 0.08 of the caller's own reads as in phase")
	check(SentenceScript.room_phrase(
		[{"who": "a", "own_phase": 0.50, "phase": 0.80}]) == "one near",
		"a phase far from the caller's own is merely near")


func _test_determinism() -> void:
	print("\n- same inputs, same string")
	var bits := 0b101101
	var cast := {"bits": bits, "source": "tap"}
	var peers := [{"who": "a", "phase": 0.5}, {"who": "b", "phase": 0.9}]
	var day := {"phase_name": "Morning Dawn (晨曦)", "hour": 7.2, "offset_h": 0.5, "confidence": 0.6}
	var marks: Array = [0.1, -0.2, 0.05, 0.0, 0.9, -0.1]
	var chapter := {"stage_name": "Crossing the Threshold"}
	var a := SentenceScript.of(bits, cast, peers, day, marks, chapter)
	var b := SentenceScript.of(bits, cast, peers, day, marks, chapter)
	check(a == b, "two calls with identical inputs return the identical string (got '%s' and '%s')" % [a, b])
	check(a.length() <= 48, "the deterministic sample stays within 48 chars (got %d: '%s')" % [a.length(), a])
	check(a == a.to_lower(), "the deterministic sample is lowercase")
	check(not a.ends_with("."), "the deterministic sample has no trailing period")
	check(a.find(" · ") != -1, "the deterministic sample joins clauses with the middle dot")

	## THE STRONGEST MARK WINS. Line 4's mark (0.9) is the loudest, so its
	## yang word ("opening") should be the body clause.
	check(a.begins_with("opening"), "line 4's loud yang mark names the body clause (got '%s')" % a)


func _test_day_word() -> void:
	print("\n- the day shortens to one word")
	var bits := 0
	var no_marks: Array = []
	var d1 := SentenceScript.of(bits, {}, [], {"phase_name": "Morning Dawn (晨曦)"}, no_marks)
	var d2 := SentenceScript.of(bits, {}, [], {"phase_name": "Evening Twilight (黄昏)"}, no_marks)
	var d3 := SentenceScript.of(bits, {}, [], {"phase_name": "Night Torpor (夜伏)"}, no_marks)
	var d4 := SentenceScript.of(bits, {}, [], {"phase_name": "Midday Siesta (午歇)"}, no_marks)
	var d5 := SentenceScript.of(bits, {}, [], {"phase_name": "Day"}, no_marks)
	check(d1.find("dawn") != -1, "morning dawn shortens to dawn (got '%s')" % d1)
	check(d2.find("dusk") != -1, "evening twilight shortens to dusk (got '%s')" % d2)
	check(d3.find("night") != -1, "night torpor shortens to night (got '%s')" % d3)
	check(d4.find("siesta") != -1, "midday siesta shortens to siesta (got '%s')" % d4)
	check(d5.find("day") != -1, "plain Day shortens to day (got '%s')" % d5)

	var with_stage := SentenceScript.of(bits, {}, [],
		{"phase_name": "Day"}, no_marks, {"stage_name": "The Road Back"})
	check(with_stage.find("the road back") != -1,
		"a non-ordinary stage name rides beside the day (got '%s')" % with_stage)
	var ordinary := SentenceScript.of(bits, {}, [],
		{"phase_name": "Day"}, no_marks, {"stage_name": "Ordinary World"})
	check(ordinary.find("ordinary") == -1,
		"the Ordinary World stage adds nothing to the day clause (got '%s')" % ordinary)


func _test_missing_keys() -> void:
	print("\n- missing keys never crash")
	var s1 := SentenceScript.of(0, {}, [], {})
	check(s1 != "", "every argument empty still returns a sentence (got '%s')" % s1)
	check(s1.length() <= 48, "the all-empty sentence stays within 48 chars")

	var s2 := SentenceScript.of(63, {"bits": 1}, [{"who": "a"}], {"hour": 5.0})
	check(s2 != "", "a day dict with no phase_name still returns a sentence (got '%s')" % s2)

	var s3 := SentenceScript.of(-1, {}, [], {"phase_name": null})
	check(s3 != "", "a negative body_bits and a null phase_name still return a sentence")

	var s4 := SentenceScript.of(0, {}, [{"who": "a", "phase": null}], {"phase_name": "Day"})
	check(s4 != "", "a peer with a null phase still returns a sentence (got '%s')" % s4)


func _test_sweep() -> void:
	print("\n- every body x every day phase stays lowercase, unpunctuated, <= 48 chars")
	var phases := ["Morning Dawn (晨曦)", "Evening Twilight (黄昏)", "Night Torpor (夜伏)", "Day"]
	var bad := 0
	var checked := 0
	for bits in range(64):
		for phase in phases:
			var day := {"phase_name": phase, "hour": 10.0, "offset_h": 0.0, "confidence": 0.5}
			var peers: Array = [] if (bits % 2 == 0) else [{"who": "p", "phase": 0.3}]
			var marks: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			var s: String = SentenceScript.of(bits, {}, peers, day, marks, {"stage_name": "Ordinary World"})
			checked += 1
			if s.length() > 48 or s != s.to_lower() or s.ends_with("."):
				bad += 1
	check(bad == 0, "%d/%d sweep sentences violated length/case/period (0 expected)" % [bad, checked])
