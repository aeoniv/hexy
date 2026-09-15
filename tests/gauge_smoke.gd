extends SceneTree

## GAUGE SMOKE — scripts/core/gauge.gd (W8b, "the one mutable thing").
##
## THREE THINGS ARE BEING PROVED HERE:
##   1. The DEFAULT gauge reproduces today's behaviour — the same phase band
##      Entrain names, the same chapter Journey names, the same word Sentence
##      reaches for, the same threshold Alchemy turns a line on.
##   2. A SECOND GAUGE FILE is a different interpretation of the same
##      organism: different words, different lean, same lines. Bias is a file
##      you can diff, and the diff never reaches the body.
##   3. The file round-trips: unknown fields written by a newer build survive
##      a load/save here, and the glass wall holds in the source text.
##
## Prints === ALL PASS === or fails.

const KingWen = preload("res://scripts/core/iching/king_wen.gd")

const TEST_PATH: String = "user://gauge_test.json"
const MAIN_PATH: String = "user://gauge_smoke_main.json"

## SNAPSHOTTED FROM THE SOURCE AT THE START OF W8b, so this test still means
## something if W8c reduces Entrain/Journey/Sentence out from under it.
const WANT_BANDS: Array = [
	[1.0, "night"], [5.5, "dawn"], [8.0, "morning"], [12.0, "midday"],
	[15.0, "afternoon"], [18.0, "dusk"], [20.0, "evening"], [23.0, "night"],
]
const WANT_LEAN_THRESHOLD: float = 0.6
const WANT_LEAN_STEP: float = 0.25
const WANT_FLIP_DAYS: int = 3
const WANT_DECAY_DAYS: float = 14.0
const WANT_CALL_DAYS: int = 28
const WANT_ORDINARY_DAYS: int = 14

var _fails := 0
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		_fails += 1


func _near(a: float, b: float, eps: float, what: String) -> void:
	_check(absf(a - b) <= eps, "%s (got %.4f, want %.4f +-%.4f)" % [what, a, b, eps])


func _initialize() -> void:
	_cleanup()
	_defaults_and_file()
	_phase_bands()
	_chapters()
	_words()
	_alchemy_numbers()
	_bits_of()
	_second_gauge()
	_round_trip_unknown()
	_correct()
	_fit()
	_glass_wall()
	_cleanup()

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


func _cleanup() -> void:
	for p in [TEST_PATH, MAIN_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## --- 1. a missing file is the default interpretation, not an error --------
func _defaults_and_file() -> void:
	print("\n- defaults, load, save, reset")
	var g := HexyGauge.new(MAIN_PATH)
	_check(not g.load(), "a missing gauge.json loads as the defaults, not an error")
	_check(int(g.get_field("version", 0)) == HexyGauge.VERSION,
		"the defaults carry a version field")
	_check(g.save(), "the gauge writes itself to disk")
	_check(FileAccess.file_exists(MAIN_PATH), "and the file is there afterwards")

	var g2 := HexyGauge.new(MAIN_PATH)
	_check(g2.load(), "a second gauge reads the file back")
	_check(g2.data.hash() == g.data.hash(), "and gets the same interpretation")

	g2.correct("lean_threshold", 0.9)
	g2.reset()
	_near(float(g2.get_field("lean_threshold", 0.0)), WANT_LEAN_THRESHOLD, 0.0001,
		"reset puts a corrected field back to today's number")


## --- 2. the seven bands Entrain hands out --------------------------------
func _phase_bands() -> void:
	print("\n- phase bands reproduce Entrain.phase_name")
	var g := HexyGauge.new(MAIN_PATH)
	for row in WANT_BANDS:
		var h: float = float(row[0])
		var want: String = String(row[1])
		_check(g.phase_name(h) == want,
			"internal hour %.1f is %s (got %s)" % [h, want, g.phase_name(h)])
	_check(g.phase_name(25.0) == "night", "the hour wraps rather than falling off the table")
	_check(g.phase_name(-1.0) == "night", "and wraps backwards too")
	_check(g.phase_of_frac(0.5) == "midday", "a day fraction reads as a band too")

	var known := ["night", "dawn", "morning", "midday", "afternoon", "dusk", "evening"]
	var all_known := true
	for i in range(240):
		if not known.has(g.phase_name(float(i) * 0.1)):
			all_known = false
	_check(all_known, "every hour of the day names a band the sentence knows")

	## The one place the gauge slides the sun: a +4h owl reads 23:00 as 19:00.
	g.data["clock_offset_h"] = 4.0
	_near(g.internal_hour(23.0), 19.0, 0.0001, "internal_hour slides the wall hour by the offset")
	g.data["clock_offset_h"] = 0.0


## --- 3. the ten stages, as a data table ----------------------------------
func _chapters() -> void:
	print("\n- chapter_rules reproduce Journey.stage_of_path")
	var g := HexyGauge.new(MAIN_PATH)

	## A grid of paths wide enough to hit every rule row that bits can reach.
	var paths: Array = [
		[0b000100, 0b000101],            # one lower line: THRESHOLD
		[0b000100, 0b001100],            # one upper line: MENTOR
		[0b000100, 0b010101],            # three lines: TRIALS
		[0b000100, 0b111011],            # many lines: ORDEAL
		[0b000100, 0b000100],            # nothing moved
		[0b010101, 0b001100, 0b010101],  # old ground
		[0b000100, 0b111111],            # Qian: RETURN
		[0b000100, 0b000000],            # Kun: RETURN
		[0b101010],                      # no predecessor at all
	]
	for days in [0, 14, 28]:
		for p in paths:
			var typed: Array[int] = ([] as Array[int])
			for b in p:
				typed.append(int(b))
			var got: int = g.stage_of(typed, days)
			var want: int = Journey.stage_of_path(typed, days)
			_check(got == want, "path %s at %d days still is stage %d (got %d)"
				% [str(p), days, want, got])

	_check(g.stage_name(0) == "Ordinary World", "stage 0 is named the ordinary world")
	_check(g.stage_name(9) == "Return", "stage 9 is named the return")
	_check(g.stage_gloss(6) != "", "and every stage carries a gloss")
	_check(int(g.get_field("chapter_rules.call_days", 0)) == WANT_CALL_DAYS,
		"four weeks still is a call (%d days)" % WANT_CALL_DAYS)
	_check(int(g.get_field("chapter_rules.ordinary_days", 0)) == WANT_ORDINARY_DAYS,
		"two weeks still is the ordinary world (%d days)" % WANT_ORDINARY_DAYS)
	_check(g.stage_of(([] as Array[int]), 0) == 0, "an empty path is the ordinary world")


## --- 4. the word tables --------------------------------------------------
func _words() -> void:
	print("\n- word tables reproduce Sentence")
	var g := HexyGauge.new(MAIN_PATH)
	for line in range(6):
		var ok := true
		for value in [-1, 0, 1]:
			for lean in [-0.9, -0.2, 0.0, 0.2, 0.9]:
				if g.word_for_line(line, value, lean) != Sentence.word_for_line(line, value, lean):
					ok = false
		_check(ok, "line %d says the same word Sentence does, for every bit and lean" % line)

	_check(g.day_word("dawn") == "dawn", "a dawn phase is one word")
	_check(g.day_word("midday") == "midday", "and midday is its own")
	_check(g.day_word("twilight blue") == "dusk", "twilight reads as dusk")
	_check(g.day_word("Xanadu") == "day", "and an unknown phase falls through to day")

	_check(g.room_phrase([]) == "alone", "an empty room is alone")
	_check(g.room_phrase([{}]) == "one near", "one peer is one near")
	_check(g.room_phrase([{}, {}, {}]) == "3 near", "three peers count themselves")
	_check(g.room_phrase([{"in_phase": true}]) == "one in phase", "a peer in phase says so")
	_check(g.room_phrase([{"own_phase": 0.5, "phase": 0.52}]) == "one in phase",
		"and a peer close enough in phase counts too")

	_check(g.advice_clause("light_advances") == "light now shifts you earlier",
		"an advancing PRC reads as a short lowercase clause")
	_check(g.advice_clause("light_delays") == "light now shifts you later",
		"a delaying one says the other direction")
	_check(g.advice_clause("none") == "", "and silence when the light says nothing")

	_check(g.dominant_line([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) == 5,
		"with no mark loud, the top line speaks for the body")
	_check(g.dominant_line([0.0, 0.9, 0.0, 0.0, 0.0, 0.0]) == 1,
		"and the loudest mark speaks when there is one")
	_check(g.day_clause("morning", "Ordinary World") == "morning",
		"the ordinary world adds nothing to the day clause")
	_check(g.day_clause("morning", "Ordeal") == "morning ordeal",
		"and a real chapter does")


## --- 5. the numbers the deleted alchemy.gd used to turn a line on --------
##
## W10d -- alchemy.gd is gone; these are SNAPSHOTTED LITERALS, the same
## numbers that file's own consts used to carry (MARK_THRESHOLD_DEFAULT,
## MARK_STEP, MS_PER_DAY), so the gauge's own fields still mean the same
## thing they always did.
const WANT_MARK_THRESHOLD: float = 0.6
const WANT_MARK_STEP: float = 0.25
const WANT_MS_PER_DAY: int = 86_400_000

func _alchemy_numbers() -> void:
	print("\n- alchemy constants survive as fields")
	var g := HexyGauge.new(MAIN_PATH)
	_near(float(g.get_field("lean_threshold", 0.0)), WANT_MARK_THRESHOLD, 0.0001,
		"lean_threshold is the old mark threshold")
	_near(float(g.get_field("lean_step", 0.0)), WANT_MARK_STEP, 0.0001,
		"lean_step is one nudge's worth of mark")
	_near(float(g.get_field("mark_decay_days", 0.0)), WANT_DECAY_DAYS, 0.0001,
		"the leak is still a fortnight")
	_check(int(g.get_field("flip_days", 0)) == WANT_FLIP_DAYS,
		"flip_days is still three distinct days")
	_check(int(g.get_field("ms_per_day", 0)) == WANT_MS_PER_DAY,
		"the fortnight's own unit came along")
	_check((g.get_field("line_lean", []) as Array).size() == 6,
		"there is one lean per line, and it starts at zero")


## --- 6. the reading layer over the six fills -----------------------------
func _bits_of() -> void:
	print("\n- bits_of reads the six fills through the lean")
	var g := HexyGauge.new(MAIN_PATH)
	_check(g.bits_of([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) == 0, "six empty needs read as Kun")
	_check(g.bits_of([1.0, 1.0, 1.0, 1.0, 1.0, 1.0]) == 63, "six full ones read as Qian")
	_check(g.bits_of([0.7, 0.2, 0.7, 0.2, 0.2, 0.2]) == 0b000101,
		"and a mixed body reads line by line, bottom first")
	_check(g.bits_of([0.59, 0.0, 0.0, 0.0, 0.0, 0.0]) == 0,
		"a fill just under the threshold is still yin")
	_check(g.bits_of([0.6, 0.0, 0.0, 0.0, 0.0, 0.0]) == 1,
		"and one exactly on it has turned")
	_check(g.bits_of([0.3]) == 0, "a short lines array does not throw")


## --- 7. A DIFFERENT GAUGE FILE IS A DIFFERENT INTERPRETATION -------------
func _second_gauge() -> void:
	print("\n- a second gauge file: same lines, different reading")
	var lines: Array = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
	var before: Array = lines.duplicate()

	var plain := HexyGauge.new(MAIN_PATH)
	var plain_bits: int = plain.bits_of(lines)
	var plain_word: String = plain.word_for_line(0, 1, 0.0)

	## Hand-written second interpretation: a thumb on every line and a
	## vocabulary of its own.
	var other := HexyGauge.defaults()
	other["line_lean"] = [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
	(other["words"] as Dictionary)["line_words"] = [
		["low", "mid", "high"], ["low", "mid", "high"], ["low", "mid", "high"],
		["low", "mid", "high"], ["low", "mid", "high"], ["low", "mid", "high"],
	]
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(other, "\t"))
	f.close()

	var biased := HexyGauge.new(TEST_PATH)
	_check(biased.load(), "the second gauge file loads")
	_check(biased.bits_of(lines) != plain_bits,
		"it reads the same six fills as a different hexagram (%d vs %d)"
		% [biased.bits_of(lines), plain_bits])
	_check(biased.word_for_line(0, 1, 0.0) == "high" and plain_word != "high",
		"and it says a different word about the same line")
	_check(lines == before, "THE LINES THEMSELVES ARE UNTOUCHED by either reading")
	_check(biased.stage_of(([0b000100, 0b000101] as Array[int]), 0)
		== plain.stage_of(([0b000100, 0b000101] as Array[int]), 0),
		"a gauge that only changed words and lean tells the same chapter")


## --- 8. round-trip keeps what it does not understand ---------------------
func _round_trip_unknown() -> void:
	print("\n- round-trip preserves unknown fields")
	var raw := HexyGauge.defaults()
	raw["from_a_newer_build"] = {"nested": [1, 2, 3], "why": "forward compatibility"}
	raw["version"] = 99
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw, "\t"))
	f.close()

	var g := HexyGauge.new(TEST_PATH)
	g.load()
	_check(g.data.has("from_a_newer_build"), "a field this build never heard of survives the load")
	g.save()
	var g2 := HexyGauge.new(TEST_PATH)
	g2.load()
	_check(g2.data.has("from_a_newer_build"), "and survives the save back out")
	_check(int(g2.get_field("from_a_newer_build.nested.1", 0)) == 2,
		"with its nested contents intact")
	_check(int(g2.get_field("version", 0)) == 99, "the file's own version is not overwritten")

	## And a file MISSING a field this build knows about still reads.
	var thin := {"version": 1, "lean_threshold": 0.8}
	var f2 := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f2.store_string(JSON.stringify(thin, "\t"))
	f2.close()
	var g3 := HexyGauge.new(TEST_PATH)
	g3.load()
	_near(float(g3.get_field("lean_threshold", 0.0)), 0.8, 0.0001, "a thin file's own value wins")
	_check((g3.get_field("words.line_words", []) as Array).size() == 6,
		"and everything it left out falls back to today's default")


## --- 9. the glass correction, clamped ------------------------------------
func _correct() -> void:
	print("\n- correct(): the user's thumb, clamped and saved")
	var g := HexyGauge.new(TEST_PATH)
	g.reset()
	_check(g.correct("lean_threshold", 0.42), "a known field takes a correction")
	_near(float(g.get_field("lean_threshold", 0.0)), 0.42, 0.0001, "and holds the new value")
	_check(g.correct("lean_threshold", 9.0), "an out-of-range correction is accepted")
	_near(float(g.get_field("lean_threshold", 0.0)), 1.0, 0.0001, "but clamped to the field's range")
	_check(g.correct("line_lean.2", -0.5), "one line's lean is correctable on its own")
	_near(float(g.get_field("line_lean.2", 0.0)), -0.5, 0.0001, "and lands on that line only")
	_near(float(g.get_field("line_lean.3", 9.0)), 0.0, 0.0001, "leaving its neighbours alone")
	_check(int(g.get_field("flip_days", 0)) == WANT_FLIP_DAYS and g.correct("flip_days", 5.4)
		and int(g.get_field("flip_days", 0)) == 5, "an integer field stays an integer")
	_check(not g.correct("words.line_words", 3), "a field with no clamp row is refused")
	_check(not g.correct("nonsense.key", 1.0), "and so is a key that does not exist")

	var reread := HexyGauge.new(TEST_PATH)
	reread.load()
	_near(float(reread.get_field("line_lean.2", 0.0)), -0.5, 0.0001,
		"a correction is on disk the moment it is made")


## --- 10. the slow self-fit from senses -----------------------------------
func _fit() -> void:
	print("\n- fit(): the clock offset, guessed from lux")
	var g := HexyGauge.new(TEST_PATH)
	g.reset()
	_near(float(g.get_field("clock_offset_h", 9.0)), 0.0, 0.0001,
		"an unentrained gauge runs on the sun")

	## A NIGHT OWL'S WEEK: bright light only from noon to midnight.
	for day in range(7):
		for h in range(12, 24):
			g.fit(HexyMsg.sense("ocelli", "light", 0,
				400.0, {"day": day, "wall_hour": float(h)}))
	var est: Dictionary = g.estimate()
	_check(float(est["offset_h"]) > 0.5, "a week of afternoon light pushes the offset late (%.2f)"
		% float(est["offset_h"]))
	_check(float(est["confidence"]) > 0.0, "and gives the estimate some confidence")
	_near(float(g.get_field("clock_offset_h", 0.0)), float(est["offset_h"]), 0.0001,
		"fit writes that offset into the gauge")

	var reread := HexyGauge.new(TEST_PATH)
	reread.load()
	_near(float(reread.get_field("clock_offset_h", 0.0)), float(est["offset_h"]), 0.0001,
		"and it is on disk")

	## A sense the gauge does not listen to changes nothing.
	var before: float = float(g.get_field("clock_offset_h", 0.0))
	var n_before: int = g.samples.size()
	g.fit(HexyMsg.sense("pheromone", "radio", 0, 1.0, {"day": 6, "wall_hour": 3.0}))
	_check(g.samples.size() == n_before, "an organ the gauge does not read is ignored")
	_near(float(g.get_field("clock_offset_h", 0.0)), before, 0.0001, "and moves nothing")

	## The offset is clamped by the gauge's own field, not a const.
	_check(absf(float(est["offset_h"])) <= float(g.get_field("offset_clamp_h", 6.0)),
		"the offset never leaves the clamp the gauge itself carries")

	g.data["confidence"] = 1.0
	g.decay(10)
	_near(float(g.get_field("confidence", 0.0)), 0.8, 0.0001,
		"confidence decays when the caller notices a gap")

	## The PRC advisory, over the gauge's own bright_lux and max_shift_h.
	_check(String(g.advice(6.0, 400.0, 8.0, 0.0)["key"]) == "light_advances",
		"bright light before wake advances the clock")
	_check(String(g.advice(6.0, 1.0, 8.0, 0.0)["key"]) == "none",
		"and dim light says nothing at all")


## --- 11. THE GLASS WALL, checked in the source text ----------------------
func _glass_wall() -> void:
	print("\n- the gauge knows no brain and no glass")
	var text: String = FileAccess.get_file_as_string("res://scripts/core/gauge.gd")
	_check(text != "", "gauge.gd is on disk and readable")
	_check(not text.contains("res://scripts/brain"), "gauge.gd preloads nothing from scripts/brain")
	_check(not text.contains("res://scripts/glass"), "gauge.gd preloads nothing from scripts/glass")
	_check(not text.contains("res://scripts/senses"), "nor reaches for a sense on its own")
	_check(not text.contains("res://scripts/net"), "nor for a socket")
