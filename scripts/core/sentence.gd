class_name Sentence
extends RefCounted

## THE ONE LINE THE FRONT GLASS SAYS.
##
## Everything else in this app computes a fact -- the body's six lines, the
## room's peers, the day's phase, the journey's chapter. Nothing turns those
## facts into the one sentence a person reads without tapping anything. This
## file is that seam, and it is the only one: [method of] takes whatever the
## host already has lying around and returns a lowercase line, at most 48
## characters, with no trailing period, that says the same thing every time
## it is given the same inputs.
##
## THREE CLAUSES, JOINED BY " · ", DROPPED FROM THE END WHEN THEY DO NOT FIT:
##   1. the body   -- one word for whichever line leans hardest (or the top
##                    line, with nothing else to go on)
##   2. the room    -- alone / one near / n near / one in phase
##   3. the day     -- dawn/day/dusk/night/siesta, plus the journey's stage
##                    name when the journey has left the ordinary world
##
## PURE. No store, no autoload, no wall-clock read -- a caller that wants a
## sentence hands in the dictionaries it already has, in the shapes the rest
## of the core already speaks: `cast` is a last-cast dict, `peers` is
## `Wmn.peers()`, `day` is `FlyCircadianClock.get_circadian_modifiers()`
## folded together with `Entrain.estimate()`, `marks` is `Alchemy.marks()`,
## `chapter` is `Journey.chapter()`.

const MAX_LEN: int = 48
const CLAUSE_SEP: String = " · "

## A mark past this magnitude is loud enough that a line is "worth a word"
## on its own extreme; short of it the line reads as its plain bit value.
const LEANING_THRESHOLD: float = 0.4

## SIX LINES, THREE WORDS EACH: yin (bit 0), neutral (bit unknown / barely
## leaning), yang (bit 1). Bottom line first, exactly as every other bit
## table in this core counts them.
const WORD_TABLE: Array = [
	["rooted", "grounding", "rising"],     # line 0: the foundation
	["settled", "steadying", "stirring"],  # line 1: the first step
	["quiet", "poised", "reaching"],       # line 2: the inner trigram's crown
	["yielding", "turning", "pressing"],   # line 3: the outer trigram's floor
	["holding", "balancing", "opening"],   # line 4: the near approach
	["resting", "crowning", "soaring"],    # line 5: the top line
]

## The uppermost line, used when no mark says otherwise -- the line a body
## reads first, being the one furthest from the ground.
const TOP_LINE: int = 5


## ONE LINE'S WORD. `value` is the line's bit (0 or 1); pass -1 when the bit
## itself is unknown and only the neutral word will do. `leaning` is the
## line's signed mark in [-1, 1] (0.0 when there is none) -- past
## [const LEANING_THRESHOLD] it overrides `value` with the extreme the mark
## itself points at, because a mark that loud is more honest than the bit.
static func word_for_line(line: int, value: int, leaning: float) -> String:
	var l: int = clampi(line, 0, WORD_TABLE.size() - 1)
	var lean: float = clampf(leaning, -1.0, 1.0)
	var idx: int
	if absf(lean) > LEANING_THRESHOLD:
		idx = 2 if lean > 0.0 else 0
	elif value == 0:
		idx = 0
	elif value == 1:
		idx = 2
	else:
		idx = 1
	return String(WORD_TABLE[l][idx])


## THE ROOM, AS ONE OF FOUR PHRASES. `peers` is `Wmn.peers()` (or anything
## shaped like it): a row counts as in-phase when it carries `in_phase: true`
## outright, or a numeric `phase` within 0.08 of a row-carried `own_phase`
## marker -- but most callers simply mark the row `in_phase` themselves,
## since only they know their own phase. A peer with neither key present is
## just a peer: unknown is not counted as in-phase.
static func room_phrase(peers: Array) -> String:
	if peers.is_empty():
		return "alone"
	for raw in peers:
		if not (raw is Dictionary):
			continue
		var p: Dictionary = raw
		if bool(p.get("in_phase", false)):
			return "one in phase"
		var mine: Variant = p.get("own_phase", null)
		var theirs: Variant = p.get("phase", null)
		if mine != null and theirs != null and absf(float(theirs) - float(mine)) <= 0.08:
			return "one in phase"
	var n: int = peers.size()
	if n == 1:
		return "one near"
	return "%d near" % n


## THE DAY, SHORTENED TO ONE WORD. `day` is duck-typed against whatever a
## host folds `FlyCircadianClock.get_circadian_modifiers()` and
## `Entrain.estimate()` into -- only `phase_name` is read, and a missing or
## unrecognised one reads as plain "day" rather than guessing.
static func _day_word(day: Dictionary) -> String:
	var raw_phase: Variant = day.get("phase_name", "")
	var phase: String = String(raw_phase).to_lower() if raw_phase != null else ""
	if phase.find("dawn") >= 0:
		return "dawn"
	if phase.find("dusk") >= 0 or phase.find("twilight") >= 0:
		return "dusk"
	if phase.find("night") >= 0:
		return "night"
	if phase.find("siesta") >= 0:
		return "siesta"
	## The seven bands [Entrain.phase_name] hands out, matched whole so a
	## host that spells its own phase differently still falls through to
	## "day" rather than being guessed at.
	for w in ["morning", "midday", "afternoon", "evening"]:
		if phase.find(w) >= 0:
			return w
	return "day"


## WHICH LINE SPEAKS FOR THE BODY. The line whose mark leans hardest, when
## any mark clears [const LEANING_THRESHOLD]; otherwise [const TOP_LINE],
## which still gets a word from its own plain bit.
static func _dominant_line(marks: Array) -> int:
	var best_line: int = TOP_LINE
	var best_abs: float = 0.0
	for i in range(marks.size()):
		var m: float = absf(float(marks[i]))
		if m > best_abs:
			best_abs = m
			best_line = i
	if best_abs <= LEANING_THRESHOLD:
		return TOP_LINE
	return best_line


## THE ONE ENTRY POINT. See the file header for the shape of every argument;
## every one of them may be short, empty, or missing keys, and none of that
## may throw -- a sentence with nothing to say about the room or the day
## still says something about the body.
static func of(body_bits: int, cast: Dictionary, peers: Array, day: Dictionary,
		marks: Array = [], chapter: Dictionary = {}, advice: String = "") -> String:
	var bits: int = body_bits & 63
	## `cast` carries only `bits`/`source` today; a cast with its own bits
	## does not override the body -- the body is what the glass shows -- but
	## a caller that wants the cast's own word can still read it back via
	## word_for_line directly. This entry point stays about the body.
	var _unused_cast: Variant = cast.get("source", "") if cast is Dictionary else ""

	var line: int = _dominant_line(marks)
	var value: int = (bits >> line) & 1
	var leaning: float = float(marks[line]) if line < marks.size() else 0.0
	var body_word: String = word_for_line(line, value, leaning)

	var room_word: String = room_phrase(peers)

	var day_word: String = _day_word(day)
	var raw_stage: Variant = chapter.get("stage_name", "") if chapter is Dictionary else ""
	var stage_name: String = String(raw_stage) if raw_stage != null else ""
	if stage_name != "" and stage_name != "Ordinary World":
		day_word += " " + stage_name.to_lower()

	## THE LIGHT ADVISORY, WHEN THERE IS ONE. It is the newest thing the day
	## has to say, so it outranks the room: if all four will not fit, the room
	## clause is the one that goes, not the advice.
	var clue: String = advice.strip_edges().to_lower()
	if clue != "":
		var full: String = _compose([body_word, room_word, day_word, clue])
		if full.length() <= MAX_LEN and full.find(clue) >= 0:
			return full
		return _compose([body_word, day_word, clue])

	return _compose([body_word, room_word, day_word])


## JOIN, THEN DROP FROM THE END UNTIL IT FITS. A clause is never cut in the
## middle: a sentence that cannot fit its day clause says only the body and
## the room, and a sentence that cannot fit even those says only the body.
static func _compose(clauses: Array) -> String:
	var parts: Array[String] = []
	for c in clauses:
		var s: String = String(c).strip_edges()
		if s != "":
			parts.append(s)
	if parts.is_empty():
		return ""
	var out: String = CLAUSE_SEP.join(parts)
	while out.length() > MAX_LEN and parts.size() > 1:
		parts.remove_at(parts.size() - 1)
		out = CLAUSE_SEP.join(parts)
	if out.length() > MAX_LEN:
		out = out.substr(0, MAX_LEN)
	return out.to_lower()
