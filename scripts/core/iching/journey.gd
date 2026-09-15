class_name Journey
extends RefCounted

## Names the hero's-journey chapter that a body transition corresponds to.
##
## The body (six lines, written only by Alchemy) drifts through the 64
## hexagrams over weeks. Journey turns a (previous figure, new figure, how
## long it sat still) triple into a chapter title for the reading sheet,
## instead of a fortune-cookie line.
##
## RULE TABLE (checked in this order, first match wins):
##   1. landing on hexagram #1, #2, #63 or #64            -> RETURN
##   2. the new figure was seen within the last 8 steps    -> ROAD_BACK
##      of the path (excluding the figure just left)
##   3. 0 lines changed and days_still >= 28                -> CALL
##   4. 0 lines changed and days_still >= 14                -> ORDINARY
##   5. 4 or more lines changed                             -> ORDEAL
##   6. 2 or 3 lines changed                                -> TRIALS
##   7. exactly 1 line changed, in the lower (inner) trigram -> THRESHOLD
##   8. exactly 1 line changed, in the upper (outer) trigram -> MENTOR
##   9. fallback (0 changed, days_still < 14)               -> ORDINARY
##
## THRESHOLD/MENTOR/TRIALS/ORDEAL/ROAD_BACK/RETURN are about the SHAPE of the
## move; CALL/ORDINARY are about standing still. REFUSAL is reachable only by
## a caller that decides, elsewhere, that a CALL was ignored (Journey has no
## way to know that from bits alone) — it is kept in the enum so a chapter
## number always names a rung on the same ladder.

const KingWen = preload("res://scripts/core/iching/king_wen.gd")

enum Stage {
	ORDINARY,
	CALL,
	REFUSAL,
	MENTOR,
	THRESHOLD,
	TRIALS,
	ORDEAL,
	REWARD,
	ROAD_BACK,
	RETURN,
}

const STAGE_NAMES: Array[String] = [
	"Ordinary World",
	"Call to Adventure",
	"Refusal",
	"Meeting the Mentor",
	"Crossing the Threshold",
	"Trials",
	"Ordeal",
	"Reward",
	"The Road Back",
	"Return",
]

const STAGE_GLOSS: Array[String] = [
	"Nothing moving. Life as usual.",
	"Stuck long enough that something has to give.",
	"Kept in the enum; Journey never assigns this from bits alone.",
	"An outer, outward-facing line shifted first.",
	"An inner line shifted first: a step actually taken.",
	"Several lines moved at once: the middle of the story.",
	"Most or all of the body changed at once: the low point.",
	"Kept in the enum; Journey never assigns this from bits alone.",
	"Circled back to ground already covered.",
	"Landed on one of the four axis hexagrams: Qian, Kun, Ji Ji, Wei Ji.",
]

## How many of the most recent past figures count when checking for a
## return to old ground (rule 2).
const ROAD_BACK_LOOKBACK: int = 8

## King Wen numbers that mark a RETURN: Qian 1, Kun 2, Ji Ji 63, Wei Ji 64.
const RETURN_NUMBERS: Array[int] = [1, 2, 63, 64]


## Days-still thresholds are read straight off the calendar: two weeks of no
## motion is ORDINARY, four weeks is loud enough to be a CALL.
const CALL_DAYS: int = 28
const ORDINARY_DAYS: int = 14


static func _changed_lines(prev_bits: int, bits: int) -> int:
	return (prev_bits ^ bits) & 63


static func _popcount6(v: int) -> int:
	var n: int = 0
	for i in range(6):
		if (v >> i) & 1 == 1:
			n += 1
	return n


## Single-step rule: no memory of the path, so rule 2 (ROAD_BACK) never
## fires here. Use stage_of_path when a path is available.
static func stage_of(prev_bits: int, bits: int, days_still: int) -> int:
	return stage_of_path([prev_bits, bits], days_still)


## Path-aware rule: path[-1] is the current figure, path[-2] (if present) is
## where it came from. Earlier entries (path[0 .. -3], up to
## ROAD_BACK_LOOKBACK of them) are checked for a return to old ground.
static func stage_of_path(path: Array[int], days_still: int) -> int:
	if path.is_empty():
		return Stage.ORDINARY
	var bits: int = path[path.size() - 1] & 63
	var num: int = KingWen.number(bits)

	if num in RETURN_NUMBERS:
		return Stage.RETURN

	if path.size() >= 3:
		var lookback_start: int = maxi(0, path.size() - 2 - ROAD_BACK_LOOKBACK)
		for i in range(lookback_start, path.size() - 2):
			if (path[i] & 63) == bits:
				return Stage.ROAD_BACK

	if path.size() < 2:
		if days_still >= CALL_DAYS:
			return Stage.CALL
		if days_still >= ORDINARY_DAYS:
			return Stage.ORDINARY
		return Stage.ORDINARY

	var prev_bits: int = path[path.size() - 2] & 63
	var changed: int = _changed_lines(prev_bits, bits)
	var n_changed: int = _popcount6(changed)

	if n_changed == 0:
		if days_still >= CALL_DAYS:
			return Stage.CALL
		if days_still >= ORDINARY_DAYS:
			return Stage.ORDINARY
		return Stage.ORDINARY

	if n_changed >= 4:
		return Stage.ORDEAL
	if n_changed >= 2:
		return Stage.TRIALS

	# exactly one line changed: which trigram is it in?
	var lower_mask: int = changed & 7
	if lower_mask != 0:
		return Stage.THRESHOLD
	return Stage.MENTOR


static func chapter(bits: int, stage: int) -> Dictionary:
	var s: int = clampi(stage, 0, Stage.RETURN)
	var hexagram_no: int = KingWen.number(bits)
	var hexagram_name: String = KingWen.name(bits)
	var stage_name: String = STAGE_NAMES[s]
	return {
		"stage": s,
		"stage_name": stage_name,
		"gloss": STAGE_GLOSS[s],
		"hexagram_no": hexagram_no,
		"hexagram_name": hexagram_name,
		"title": "%s · %s" % [stage_name, hexagram_name],
	}


## Stages for every step of a path (path[0] gets ORDINARY/CALL treatment
## with no predecessor; days_still applies only to the last step, since
## earlier steps' actual dwell time isn't known here).
static func arc(path: Array[int]) -> Array[int]:
	var out: Array[int] = ([] as Array[int])
	for i in range(path.size()):
		var sub: Array[int] = path.slice(0, i + 1)
		var days_still: int = 0
		out.append(stage_of_path(sub, days_still))
	return out
