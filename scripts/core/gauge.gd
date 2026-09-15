class_name HexyGauge
extends RefCounted

## W8b — THE GAUGE: the one mutable thing.
##
## The five canonical parts (ffbrain, mnn, wmn, qwen, i-ching) are immutable
## and free of heuristics. Every heuristic — every threshold, every band
## boundary, every word a caption reaches for — is a FIELD IN THIS ONE DATA
## FILE, persisted at user://gauge.json.
##
## THE GAUGE READS CANON OUTPUT AND NEVER WRITES INTO IT. Nothing here calls
## into a brain, a store or a glass; the functions below are pure reads over
## `data` plus their arguments. It must never preload anything under
## scripts/brain or scripts/glass — tests/gauge_smoke.gd asserts that by
## reading this file's own source text.
##
## IT CHANGES TWO WAYS, AND ONLY TWO:
##   1. [method fit]     — slow self-fit from senses (lux/motion/screen/words).
##   2. [method correct] — the user's correction from the glass, clamped.
## Neither emits a signal: the caller publishes on /body or /phase itself.
##
## A DIFFERENT GAUGE FILE IS A DIFFERENT INTERPRETATION OF THE SAME ORGANISM.
## Swap the word tables and the captions change; swap `line_lean` and the
## reading of the six homeostat fills changes. The lines themselves — what
## the creature actually is — are never touched from here. Bias is a file you
## can diff.
##
## DEFAULTS REPRODUCE TODAY'S BEHAVIOUR. Every number below was read off the
## source that owns it today: scripts/core/entrain.gd, scripts/core/alchemy.gd,
## scripts/core/iching/journey.gd and scripts/core/sentence.gd.

const KingWen = preload("res://scripts/core/iching/king_wen.gd")

const PATH: String = "user://gauge.json"
const VERSION: int = 1


## THE WHOLE INTERPRETATION, AS ONE DICTIONARY. Plain JSON types only (ints,
## floats, Strings, bools, Arrays, Dictionaries) so the file round-trips
## through JSON.stringify/parse unchanged, exactly like a HexyMsg does.
var data: Dictionary = {}

## Where this instance loads from and saves to. Overridable so a test (or a
## second interpretation held side by side) can point at its own file.
var path: String = PATH

## THE RING BUFFER [method fit] KEEPS. Runtime only — samples are evidence,
## not interpretation, so they are deliberately NOT part of `data` and never
## reach gauge.json. Rows are {day, wall_hour, lux, motion, screen_on, spoke}.
var samples: Array = []

## WHETHER [method fit] WRITES gauge.json EVERY TIME IT IS CALLED. The bus
## pushes a Sense far faster than a disk wants to be written, so a host that
## subscribes the gauge to "/sense" turns this off and calls [method save]
## on its own throttle (once every few minutes, and on quit). Off changes
## nothing about what fit computes -- only when the file is touched.
var autosave: bool = true


func _init(from_path: String = PATH) -> void:
	path = from_path
	data = defaults()


## ------------------------------------------------------------ defaults ----

## EVERY HEURISTIC IN THE APP, CONDENSED, WITH THE NUMBER IT HAS TODAY.
static func defaults() -> Dictionary:
	return {
		"version": VERSION,

		## --- from scripts/core/entrain.gd -------------------------------
		## clock_offset_h / confidence are the two things [method fit]
		## writes; the rest are Entrain's own constants, as data.
		"clock_offset_h": 0.0,
		"confidence": 0.0,
		"fly_morning_h": 7.0,
		"offset_clamp_h": 6.0,
		"confidence_sample_floor": 8,
		"bright_lux": 50.0,
		"max_shift_h": 1.5,
		"decay_rate": 0.02,
		"days": 7,
		"min_samples": 48,
		## How much of a fresh estimate each [method fit] adopts. 1.0 keeps
		## the gauge in lockstep with Entrain.estimate (today's behaviour);
		## lower it and the self-fit becomes the slow drift it is named for.
		"fit_rate": 1.0,
		## [start_hour, name); the table wraps past midnight into row 0.
		"phase_bands": [
			[0.0, "night"],
			[5.0, "dawn"],
			[7.0, "morning"],
			[11.0, "midday"],
			[14.0, "afternoon"],
			[17.0, "dusk"],
			[19.0, "evening"],
			[22.0, "night"],
		],
		## The activity votes Entrain.estimate casts, as data: a lux sample
		## at or over bright_lux is worth 0.6, screen-on 0.4, a spoken word
		## 0.8, and raw motion is worth itself.
		"activity_weights": {
			"bright": 0.6,
			"screen_on": 0.4,
			"spoke": 0.8,
		},
		## lerpf(12, 2, resultant): how wide the wake window reads.
		"half_span_h": [12.0, 2.0],

		## --- from scripts/core/alchemy.gd -------------------------------
		## THE READING LAYER'S THUMB ON THE SCALE. Six signed nudges, one per
		## line (bottom first), added to a homeostat fill before it is read
		## as a bit. Zero is "read the body as it is".
		"line_lean": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		## Alchemy.MARK_STEP — one nudge's worth of lean.
		"lean_step": 0.25,
		## Alchemy.MARK_THRESHOLD_DEFAULT — how far a line must lean before
		## it reads (and, in Alchemy, turns) yang.
		"lean_threshold": 0.6,
		## Alchemy.MARK_DECAY_DAYS_DEFAULT — the leak: a mark left alone
		## falls by 1/e over this many days.
		"mark_decay_days": 14.0,
		## Alchemy.MS_PER_DAY, the fortnight's own unit.
		"ms_per_day": 86400000,
		## Alchemy.MARK_EPSILON — below this a mark is gone, not faint.
		"mark_epsilon": 0.001,
		## Alchemy.FLIP_DAYS_DEFAULT — distinct days of pressure the
		## hysteresis gate wants before a line may turn.
		"flip_days": 3,
		## Alchemy.PRIOR_MAX / PRIOR_FOLLOWS_STILLNESS_DEFAULT.
		"prior_max": 0.35,
		"prior_follows_stillness": false,
		## Alchemy.INJECT_WEIGHT — a whole cast's weight when injected.
		"inject_weight": 1.0,

		## --- from scripts/core/iching/journey.gd ------------------------
		## THE TEN STAGES AS A DATA TABLE. `rules` is checked in order,
		## first match wins — the same order Journey.stage_of_path codes.
		"chapter_rules": {
			"stage_names": [
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
			],
			"stage_gloss": [
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
			],
			"return_numbers": [1, 2, 63, 64],
			"road_back_lookback": 8,
			"call_days": 28,
			"ordinary_days": 14,
			"rules": [
				{"test": "return_number", "stage": 9},
				{"test": "road_back", "stage": 8},
				{"test": "still_days", "min_days": 28, "stage": 1},
				{"test": "still_days", "min_days": 14, "stage": 0},
				{"test": "changed_at_least", "min": 4, "stage": 6},
				{"test": "changed_at_least", "min": 2, "stage": 5},
				{"test": "one_line_lower", "stage": 4},
				{"test": "one_line_upper", "stage": 3},
				{"test": "always", "stage": 0},
			],
		},

		## --- from scripts/core/sentence.gd ------------------------------
		"words": {
			"max_len": 48,
			"clause_sep": " · ",
			## Sentence.LEANING_THRESHOLD — past this a mark is louder than
			## the bit it sits on.
			"leaning_threshold": 0.4,
			## Sentence.TOP_LINE — who speaks when no mark is loud.
			"top_line": 5,
			## SIX LINES, THREE WORDS EACH: [yin, neutral, yang]. Bottom
			## line first, like every other bit table in this core.
			"line_words": [
				["rooted", "grounding", "rising"],
				["settled", "steadying", "stirring"],
				["quiet", "poised", "reaching"],
				["yielding", "turning", "pressing"],
				["holding", "balancing", "opening"],
				["resting", "crowning", "soaring"],
			],
			## Phase name -> day word. Matched as a SUBSTRING, in this order,
			## so a host that spells its phase differently still lands
			## somewhere rather than being guessed at.
			"day_words": [
				["dawn", "dawn"],
				["dusk", "dusk"],
				["twilight", "dusk"],
				["night", "night"],
				["siesta", "siesta"],
				["morning", "morning"],
				["midday", "midday"],
				["afternoon", "afternoon"],
				["evening", "evening"],
			],
			"day_word_fallback": "day",
			## THE ROOM, AS ONE OF FOUR PHRASES. "%d" in `many` takes the
			## peer count.
			"peer_phrases": {
				"alone": "alone",
				"in_phase": "one in phase",
				"one": "one near",
				"many": "%d near",
			},
			## How close two phases must sit to read as in phase.
			"peer_phase_eps": 0.08,
			## Entrain.advice_clause, as data.
			"advice_clauses": {
				"light_advances": "light now shifts you earlier",
				"light_delays": "light now shifts you later",
			},
			## A stage name equal to this adds nothing to the day clause.
			"quiet_stage": "Ordinary World",
		},
	}


## WHAT [method correct] IS ALLOWED TO DO. field -> [min, max]; a field with
## no row here is refused outright, so the glass can never write a word table
## into a threshold by fat-fingering a key.
static func clamps() -> Dictionary:
	return {
		"clock_offset_h": [-12.0, 12.0],
		"confidence": [0.0, 1.0],
		"fly_morning_h": [0.0, 24.0],
		"offset_clamp_h": [0.0, 12.0],
		"bright_lux": [0.0, 100000.0],
		"max_shift_h": [0.0, 12.0],
		"decay_rate": [0.0, 1.0],
		"fit_rate": [0.0, 1.0],
		"lean_step": [0.0, 1.0],
		"lean_threshold": [0.0, 1.0],
		"mark_decay_days": [0.0, 3650.0],
		"prior_max": [0.0, 1.0],
		"inject_weight": [0.0, 8.0],
		"line_lean.0": [-1.0, 1.0],
		"line_lean.1": [-1.0, 1.0],
		"line_lean.2": [-1.0, 1.0],
		"line_lean.3": [-1.0, 1.0],
		"line_lean.4": [-1.0, 1.0],
		"line_lean.5": [-1.0, 1.0],
		"days": [1.0, 365.0],
		"min_samples": [1.0, 100000.0],
		"confidence_sample_floor": [1.0, 100000.0],
		"flip_days": [0.0, 365.0],
		"words.leaning_threshold": [0.0, 1.0],
		"words.max_len": [8.0, 240.0],
		"words.top_line": [0.0, 5.0],
		"words.peer_phase_eps": [0.0, 1.0],
	}


## ---------------------------------------------------------- persistence ----

## MISSING FILE IS NOT AN ERROR: it is the default interpretation, which is
## exactly today's behaviour. Returns true when a file was actually read.
func load() -> bool:
	data = defaults()
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	## MERGE, NOT REPLACE. Keys the file does not carry keep their default
	## (an older gauge.json stays readable); keys this build has never heard
	## of are kept verbatim so a round-trip never silently drops a field a
	## newer build wrote.
	data = _merge(defaults(), parsed as Dictionary)
	return true


func save() -> bool:
	data["version"] = int(data.get("version", VERSION))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## BACK TO THE DEFAULT INTERPRETATION, on disk as well as in memory.
func reset() -> void:
	data = defaults()
	samples.clear()
	save()


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over.keys():
		var v: Variant = over[k]
		if v is Dictionary and out.has(k) and out[k] is Dictionary:
			out[k] = _merge(out[k] as Dictionary, v as Dictionary)
		else:
			out[k] = _coerce(out.get(k, null), v)
	return out


## JSON HAS ONE NUMBER TYPE AND THIS FILE HAS TWO. A field that is an int in
## the defaults comes back from JSON.parse_string as a float, and a gauge
## loaded from disk would then differ from the same gauge in memory over
## nothing at all. Where the default says int, an integral float is put back.
static func _coerce(base: Variant, over: Variant) -> Variant:
	if base is int and over is float and over == floor(over):
		return int(over)
	if base is Dictionary and over is Dictionary:
		return _merge(base as Dictionary, over as Dictionary)
	if base is Array and over is Array:
		var b: Array = base
		var o: Array = over
		var out: Array = []
		for i in range(o.size()):
			out.append(_coerce(b[i] if i < b.size() else null, o[i]))
		return out
	return over


## ------------------------------------------------------------- reading ----

## `key` is dotted: "words.leaning_threshold", "line_lean.2".
func get_field(key: String, fallback: Variant = null) -> Variant:
	var cur: Variant = data
	for part in key.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = (cur as Dictionary)[part]
		elif cur is Array and part.is_valid_int():
			var arr: Array = cur
			var i: int = int(part)
			if i < 0 or i >= arr.size():
				return fallback
			cur = arr[i]
		else:
			return fallback
	return cur


## THE SIX HOMEOSTAT FILLS, READ AS A HEXAGRAM. `lines` is Body.lines (0..1
## each, bottom first). Each fill is nudged by this gauge's own `line_lean`
## and then read against `lean_threshold`: at or over it the line is yang.
##
## THIS IS THE READING LAYER, not the body. Changing line_lean changes what
## the gauge SAYS the body is; the fills handed in are never touched.
func bits_of(lines: Array) -> int:
	var lean: Array = get_field("line_lean", [])
	var thr: float = float(get_field("lean_threshold", 0.6))
	var bits: int = 0
	for i in range(6):
		var fill: float = float(lines[i]) if i < lines.size() else 0.0
		var nudge: float = float(lean[i]) if i < lean.size() else 0.0
		if clampf(fill + nudge, 0.0, 1.0) >= thr:
			bits |= 1 << i
	return bits


## WHICH BAND AN INTERNAL HOUR FALLS IN. Reproduces Entrain.phase_name for
## the default bands. Pass an INTERNAL hour (see [method internal_hour]), not
## a wall hour, or the name is the sun's and not the user's.
func phase_name(internal_h: float) -> String:
	var bands: Array = get_field("phase_bands", [])
	if bands.is_empty():
		return ""
	var h: float = fposmod(internal_h, 24.0)
	var out: String = String((bands[0] as Array)[1])
	for row in bands:
		var r: Array = row
		if h >= float(r[0]):
			out = String(r[1])
		else:
			break
	return out


## A DAY FRACTION (0..1) READ AS A BAND, for a caller holding a phase msg
## rather than an hour.
func phase_of_frac(day_frac: float) -> String:
	return phase_name(fposmod(day_frac, 1.0) * 24.0)


## THE HOUR THE FLY SHOULD BELIEVE, given this gauge's clock offset.
func internal_hour(wall_hour: float) -> float:
	return fposmod(wall_hour - float(get_field("clock_offset_h", 0.0)), 24.0)


## THE CHAPTER A PATH IS IN. Reproduces Journey.stage_of_path for the default
## rule table — same order, first match wins — but the rules are DATA, so a
## second gauge file can call four changed lines "Trials" without a rebuild.
func stage_of(path_bits: Array, days_still: int = 0) -> int:
	var cr: Dictionary = get_field("chapter_rules", {})
	if path_bits.is_empty():
		return 0
	var bits: int = int(path_bits[path_bits.size() - 1]) & 63
	var num: int = KingWen.number(bits)

	var has_prev: bool = path_bits.size() >= 2
	var n_changed: int = 0
	var changed: int = 0
	if has_prev:
		changed = (int(path_bits[path_bits.size() - 2]) & 63) ^ bits
		for i in range(6):
			if (changed >> i) & 1 == 1:
				n_changed += 1

	for raw in cr.get("rules", []):
		var rule: Dictionary = raw
		var test: String = String(rule.get("test", ""))
		var stage: int = int(rule.get("stage", 0))
		match test:
			"return_number":
				if num in (cr.get("return_numbers", []) as Array):
					return stage
			"road_back":
				if path_bits.size() >= 3:
					var look: int = int(cr.get("road_back_lookback", 8))
					var start: int = maxi(0, path_bits.size() - 2 - look)
					for i in range(start, path_bits.size() - 2):
						if (int(path_bits[i]) & 63) == bits:
							return stage
			"still_days":
				## "Standing still" is no predecessor at all, or a
				## predecessor that changed nothing.
				if (not has_prev) or n_changed == 0:
					if days_still >= int(rule.get("min_days", 0)):
						return stage
			"changed_at_least":
				if has_prev and n_changed >= int(rule.get("min", 1)):
					return stage
			"one_line_lower":
				if has_prev and n_changed == 1 and (changed & 7) != 0:
					return stage
			"one_line_upper":
				if has_prev and n_changed == 1 and (changed & 7) == 0:
					return stage
			"always":
				return stage
	return 0


func stage_name(stage: int) -> String:
	var names: Array = get_field("chapter_rules.stage_names", [])
	if names.is_empty():
		return ""
	return String(names[clampi(stage, 0, names.size() - 1)])


func stage_gloss(stage: int) -> String:
	var gloss: Array = get_field("chapter_rules.stage_gloss", [])
	if gloss.is_empty():
		return ""
	return String(gloss[clampi(stage, 0, gloss.size() - 1)])


## ONE LINE'S THREE WORDS: [yin, neutral, yang].
func words_for_line(line: int) -> Array:
	var table: Array = get_field("words.line_words", [])
	if table.is_empty():
		return ["", "", ""]
	return (table[clampi(line, 0, table.size() - 1)] as Array).duplicate()


## ONE LINE'S WORD FOR A FILL IN 0..1. The fill is leaned and thresholded the
## same way [method bits_of] does it, and a fill sitting within half a
## `lean_step` of the threshold is the NEUTRAL word — a line that close to
## turning is not honestly either extreme.
func word_for_fill(line: int, fill: float) -> String:
	var w: Array = words_for_line(line)
	var lean: Array = get_field("line_lean", [])
	var nudge: float = float(lean[line]) if line >= 0 and line < lean.size() else 0.0
	var thr: float = float(get_field("lean_threshold", 0.6))
	var step: float = float(get_field("lean_step", 0.25))
	var v: float = clampf(fill + nudge, 0.0, 1.0)
	if absf(v - thr) <= step * 0.5:
		return String(w[1])
	return String(w[2]) if v >= thr else String(w[0])


## ONE LINE'S WORD FROM A BIT AND A SIGNED MARK. Reproduces
## Sentence.word_for_line exactly: `value` is the bit (0/1, or -1 for
## unknown) and `leaning` is the line's mark in [-1, 1], which overrides the
## bit once it is louder than `words.leaning_threshold`.
func word_for_line(line: int, value: int, leaning: float) -> String:
	var w: Array = words_for_line(line)
	var thr: float = float(get_field("words.leaning_threshold", 0.4))
	var lean: float = clampf(leaning, -1.0, 1.0)
	var idx: int
	if absf(lean) > thr:
		idx = 2 if lean > 0.0 else 0
	elif value == 0:
		idx = 0
	elif value == 1:
		idx = 2
	else:
		idx = 1
	return String(w[idx])


## WHICH LINE SPEAKS FOR THE BODY: the loudest mark, or the top line when no
## mark clears the threshold. Reproduces Sentence._dominant_line.
func dominant_line(marks: Array) -> int:
	var top: int = int(get_field("words.top_line", 5))
	var thr: float = float(get_field("words.leaning_threshold", 0.4))
	var best_line: int = top
	var best_abs: float = 0.0
	for i in range(marks.size()):
		var m: float = absf(float(marks[i]))
		if m > best_abs:
			best_abs = m
			best_line = i
	if best_abs <= thr:
		return top
	return best_line


## THE DAY, SHORTENED TO ONE WORD. Takes a phase NAME (Entrain's or a host's
## own) and matches it as a substring against the `day_words` table, falling
## through to `day_word_fallback` rather than guessing. Reproduces
## Sentence._day_word.
func day_word(phase: String) -> String:
	var table: Array = get_field("words.day_words", [])
	var p: String = phase.to_lower()
	for raw in table:
		var row: Array = raw
		if p.find(String(row[0])) >= 0:
			return String(row[1])
	return String(get_field("words.day_word_fallback", "day"))


## THE DAY CLAUSE: the day word, plus the chapter's stage name when the
## journey has left the ordinary world.
func day_clause(phase: String, stage_title: String = "") -> String:
	var out: String = day_word(phase)
	var quiet: String = String(get_field("words.quiet_stage", "Ordinary World"))
	if stage_title != "" and stage_title != quiet:
		out += " " + stage_title.to_lower()
	return out


## THE ROOM, AS ONE OF FOUR PHRASES. Reproduces Sentence.room_phrase.
func room_phrase(peers: Array) -> String:
	var ph: Dictionary = get_field("words.peer_phrases", {})
	if peers.is_empty():
		return String(ph.get("alone", "alone"))
	var eps: float = float(get_field("words.peer_phase_eps", 0.08))
	for raw in peers:
		if not (raw is Dictionary):
			continue
		var p: Dictionary = raw
		if bool(p.get("in_phase", false)):
			return String(ph.get("in_phase", "one in phase"))
		var mine: Variant = p.get("own_phase", null)
		var theirs: Variant = p.get("phase", null)
		if mine != null and theirs != null and absf(float(theirs) - float(mine)) <= eps:
			return String(ph.get("in_phase", "one in phase"))
	if peers.size() == 1:
		return String(ph.get("one", "one near"))
	return String(ph.get("many", "%d near")) % peers.size()


## THE LIGHT ADVISORY, AS ONE LOWERCASE CLAUSE. "" when there is nothing to
## say. Reproduces Entrain.advice_clause.
func advice_clause(key: String) -> String:
	var table: Dictionary = get_field("words.advice_clauses", {})
	return String(table.get(key, ""))


## A ONE-LIGHT-SAMPLE PHASE-RESPONSE ADVISORY, over this gauge's own numbers.
## Bright light in the six hours before the estimated wake advances the
## clock; bright light in the six hours after the estimated sleep delays it.
func advice(wall_hour: float, lux: float, wake_h: float, sleep_h: float) -> Dictionary:
	if lux < float(get_field("bright_lux", 50.0)):
		return {"key": "none", "shift_h": 0.0}
	var max_shift: float = float(get_field("max_shift_h", 1.5))
	var h: float = fposmod(wall_hour, 24.0)
	var before_wake: float = fposmod(wake_h - h, 24.0)
	if before_wake > 0.0 and before_wake <= 6.0:
		return {"key": "light_advances", "shift_h": lerpf(max_shift, 0.0, before_wake / 6.0)}
	var after_sleep: float = fposmod(h - sleep_h, 24.0)
	if after_sleep >= 0.0 and after_sleep <= 6.0:
		return {"key": "light_delays", "shift_h": lerpf(max_shift, 0.0, after_sleep / 6.0)}
	return {"key": "none", "shift_h": 0.0}


## ---------------------------------------------------- mutation path #1 ----

## SLOW SELF-FIT FROM ONE SENSE MESSAGE.
##
## `sense_msg` is a HexyMsg Sense dictionary: {kind:"sense", organ, door,
## t_ns, value, meta}. The organs this gauge listens to are the light ones
## (`ocelli`/`compound_eye`, whose value is lux), `halteres`/`tarsi` (motion,
## 0..1), `words` (the user spoke) and a `screen_on` flag in meta. Everything
## else is ignored outright — the gauge is not a second sense bus.
##
## The wall hour comes from `meta.wall_hour` (0..24) and the day index from
## `meta.day`; both are the caller's business, exactly as Entrain.sample's
## are, so a test drives a week of a night owl's days with no phone in sight.
##
## Returns the fresh estimate {offset_h, confidence, wake_h, sleep_h}. Writes
## only `clock_offset_h` and `confidence`, blended by `fit_rate`, and saves.
func fit(sense_msg: Dictionary) -> Dictionary:
	if String(sense_msg.get("kind", "")) != "sense":
		return estimate()
	var organ: String = String(sense_msg.get("organ", ""))
	var meta: Dictionary = sense_msg.get("meta", {}) if sense_msg.get("meta", {}) is Dictionary else {}
	var value: Variant = sense_msg.get("value", null)

	var lux: float = -1.0
	var motion: float = 0.0
	var spoke: bool = false
	match organ:
		"ocelli", "compound_eye":
			lux = float(value) if (value is float or value is int) else -1.0
		"halteres", "tarsi":
			motion = clampf(float(value) if (value is float or value is int) else 0.0, 0.0, 1.0)
		"words":
			spoke = true
		_:
			return estimate()

	samples.append({
		"day": int(meta.get("day", 0)),
		"wall_hour": fposmod(float(meta.get("wall_hour", 0.0)), 24.0),
		"lux": lux,
		"motion": motion,
		"screen_on": bool(meta.get("screen_on", false)),
		"spoke": spoke,
	})
	_trim(int(meta.get("day", 0)))

	var est: Dictionary = estimate()
	var rate: float = clampf(float(get_field("fit_rate", 1.0)), 0.0, 1.0)
	var was: float = float(get_field("clock_offset_h", 0.0))
	data["clock_offset_h"] = lerpf(was, float(est["offset_h"]), rate)
	data["confidence"] = lerpf(float(get_field("confidence", 0.0)), float(est["confidence"]), rate)
	if autosave:
		save()
	return est


## Drops samples older than `days` relative to the newest day seen.
func _trim(latest_day: int) -> void:
	var days: int = int(get_field("days", 7))
	var cutoff: int = latest_day - days + 1
	var kept: Array = []
	for s in samples:
		if int((s as Dictionary)["day"]) >= cutoff:
			kept.append(s)
	samples = kept


## WHERE THE USER'S DAY LIVES, from what the senses saw. Same circular
## centroid Entrain.estimate computes — every activity sample votes as a unit
## vector so a night owl's 23:00-03:00 span does not average to noon — with
## every constant read off this gauge instead of a const block.
func estimate() -> Dictionary:
	var morning: float = float(get_field("fly_morning_h", 7.0))
	var idle := {"offset_h": 0.0, "confidence": 0.0, "wake_h": morning,
		"sleep_h": morning + 16.0}
	if samples.is_empty():
		return idle

	var w: Dictionary = get_field("activity_weights", {})
	var bright_lux: float = float(get_field("bright_lux", 50.0))
	var sum_x := 0.0
	var sum_y := 0.0
	var weight_total := 0.0
	var active_count := 0
	var day_sums: Dictionary = {}

	for raw in samples:
		var s: Dictionary = raw
		var activity: float = float(s["motion"])
		if float(s["lux"]) >= 0.0 and float(s["lux"]) >= bright_lux:
			activity = maxf(activity, float(w.get("bright", 0.6)))
		if bool(s["screen_on"]):
			activity = maxf(activity, float(w.get("screen_on", 0.4)))
		if bool(s["spoke"]):
			activity = maxf(activity, float(w.get("spoke", 0.8)))
		if activity <= 0.0:
			continue
		active_count += 1
		var angle: float = float(s["wall_hour"]) / 24.0 * TAU
		sum_x += cos(angle) * activity
		sum_y += sin(angle) * activity
		weight_total += activity
		var acc: Dictionary = day_sums.get(s["day"], {"x": 0.0, "y": 0.0, "w": 0.0})
		acc["x"] += cos(angle) * activity
		acc["y"] += sin(angle) * activity
		acc["w"] += activity
		day_sums[s["day"]] = acc

	if weight_total <= 0.0:
		return idle

	## Cross-day agreement: does the active window land in the same place
	## night after night? Kept separate from the pooled spread below, which
	## only says how WIDE that window is.
	var cross_x := 0.0
	var cross_y := 0.0
	var day_count := 0
	for day in day_sums.keys():
		var acc: Dictionary = day_sums[day]
		if float(acc["w"]) <= 0.0:
			continue
		var day_angle: float = atan2(float(acc["y"]), float(acc["x"]))
		cross_x += cos(day_angle)
		cross_y += sin(day_angle)
		day_count += 1
	var cross_day_consistency := 0.0
	if day_count > 0:
		cross_day_consistency = sqrt(cross_x * cross_x + cross_y * cross_y) / float(day_count)

	var mean_angle: float = atan2(sum_y / weight_total, sum_x / weight_total)
	var centroid_h: float = fposmod(mean_angle / TAU * 24.0, 24.0)
	var resultant: float = sqrt(sum_x * sum_x + sum_y * sum_y) / weight_total

	var span: Array = get_field("half_span_h", [12.0, 2.0])
	var half_span_h: float = lerpf(float(span[0]), float(span[1]), clampf(resultant, 0.0, 1.0))
	var wake_h: float = fposmod(centroid_h - half_span_h, 24.0)
	var sleep_h: float = fposmod(centroid_h + half_span_h, 24.0)

	## Wrap into the shorter arc before clamping, so a lark waking just past
	## midnight reads as a small negative offset, not a spurious +22h.
	var raw_diff: float = wake_h - morning
	if raw_diff > 12.0:
		raw_diff -= 24.0
	elif raw_diff < -12.0:
		raw_diff += 24.0
	var clamp_h: float = float(get_field("offset_clamp_h", 6.0))
	var offset_h: float = clampf(raw_diff, -clamp_h, clamp_h)

	var floor_n: int = int(get_field("confidence_sample_floor", 8))
	var count_conf: float = clampf(float(active_count) / float(floor_n * 6), 0.0, 1.0)
	var conf: float = clampf(count_conf * clampf(cross_day_consistency, 0.0, 1.0), 0.0, 1.0)

	return {"offset_h": offset_h, "confidence": conf, "wake_h": wake_h, "sleep_h": sleep_h}


## CALLED WHEN A CALLER NOTICES A STRETCH WITH NO SAMPLES. The gauge reads no
## clock of its own, so it cannot decay itself on a timer.
func decay(ticks: int) -> void:
	var rate: float = float(get_field("decay_rate", 0.02))
	data["confidence"] = clampf(
		float(get_field("confidence", 0.0)) - rate * maxf(float(ticks), 0.0), 0.0, 1.0)


## ---------------------------------------------------- mutation path #2 ----

## THE USER'S CORRECTION, FROM THE GLASS. `field` is a dotted key that must
## appear in [method clamps] — anything else is refused, so a stray write can
## never reach a word table or a rule row through this door. Numbers are
## clamped to the row's range and integer fields stay integers. Saves on
## success. Returns true when something was actually written.
func correct(field: String, value: Variant) -> bool:
	var table: Dictionary = clamps()
	if not table.has(field):
		return false
	if not (value is float or value is int or value is bool):
		return false
	var row: Array = table[field]
	var was: Variant = get_field(field, null)
	var v: float = clampf(float(value), float(row[0]), float(row[1]))
	var out: Variant = int(round(v)) if was is int else v
	return _set_field(field, out)


func _set_field(key: String, value: Variant) -> bool:
	var parts: PackedStringArray = key.split(".")
	var cur: Variant = data
	for i in range(parts.size() - 1):
		var part: String = parts[i]
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = (cur as Dictionary)[part]
		elif cur is Array and part.is_valid_int():
			cur = (cur as Array)[int(part)]
		else:
			return false
	var last: String = parts[parts.size() - 1]
	if cur is Dictionary:
		(cur as Dictionary)[last] = value
	elif cur is Array and last.is_valid_int():
		var arr: Array = cur
		var i2: int = int(last)
		if i2 < 0 or i2 >= arr.size():
			return false
		arr[i2] = value
	else:
		return false
	save()
	return true
