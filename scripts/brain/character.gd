class_name Character
extends RefCounted

## THE CHARACTER CORE — Grounded in the Drosophila Neuromodulatory Connectome.
##
## SIX NEEDS, SIX LINES, SIX FLY NEUROMODULATORY HUBS:
##   Index 0: LINE 1 (Bottom) -> BODY       (Dopamine / PAM & PPL1 cluster)
##   Index 1: LINE 2          -> FOOD       (Neuropeptide F / Subesophageal zone)
##   Index 2: LINE 3          -> BREATH     (Octopamine / VUM cluster)
##   Index 3: LINE 4          -> REST       (GABA/5-HT / dFB & R5 sleep homeostat)
##   Index 4: LINE 5          -> FOCUS      (Acetylcholine / Central Complex EB/PB)
##   Index 5: LINE 6 (Top)    -> CONNECTION (Fruitless / pC1 social pheromone cluster)
##
## Each need is a float fullness, 0.0..1.0. A line is OPEN (yang, unbroken) when
## fullness >= 0.5, CLOSED (yin, broken) below it.
##
## Connectome Synaptic Coupling:
##   In addition to linear baseline decay, the 6 needs interact dynamically via
##   FlyConductance (derived from FlyWire/MaleCNS synaptic weights).
##
## Deterministic, clockless arithmetic: tick(now_ms) takes timestamps directly.

const FlyConductanceScript := preload("res://scripts/brain/fly_conductance.gd")

signal line_opened(line: int)
signal line_closed(line: int)
signal refused(why: String)
signal spoke(text: String)

const LINE_BODY := 0
const LINE_FOOD := 1
const LINE_BREATH := 2
const LINE_REST := 3
const LINE_FOCUS := 4
const LINE_CONNECTION := 5

const NEED_COUNT := 6

const NEED_NAMES := ["body", "food", "breath", "rest", "focus", "connection"]

const FLY_NEUROMODULATORS := [
	{"transmitter": "Dopamine (DA)", "cluster": "PAM/PPL1", "role": "Cuticular integrity & motor vigor"},
	{"transmitter": "Neuropeptide F (NPF)", "cluster": "SEZ/Antennal", "role": "Energy reserve & food valence"},
	{"transmitter": "Octopamine (OA)", "cluster": "VUM", "role": "Flight arousal & ventilation"},
	{"transmitter": "GABA / 5-HT", "cluster": "dFB / R5", "role": "Sleep homeostat & synaptic pruning"},
	{"transmitter": "Acetylcholine (ACh)", "cluster": "Central Complex", "role": "Angular heading attractor"},
	{"transmitter": "Fruitless (fru) / pC1", "cluster": "Lateral Horn / P1", "role": "Conspecific pheromonal resonance"}
]

const OPEN_THRESHOLD := 0.5

const HALF_LIFE_HOURS := {
	LINE_BODY: 18.0,
	LINE_FOOD: 6.0,
	LINE_BREATH: 12.0,
	LINE_REST: 20.0,
	LINE_FOCUS: 8.0,
	LINE_CONNECTION: 96.0,
}

const ATTESTED := "attested"
const CHANGING_BAND := 0.15
const DAILY_WINDOW_MS := 24 * 60 * 60 * 1000
const SCHEMA_VERSION := 2
const V1_CONNECTION_CLAMP := 0.45

const MOOD_RADIANT := "radiant"
const MOOD_STEADY := "steady"
const MOOD_QUIET := "quiet"
const MOOD_SLUGGISH := "sluggish"

const FlyBrainScript := preload("res://scripts/brain/fly_brain.gd")

var _fullness: Array[float] = [0.6, 0.6, 0.6, 0.6, 0.6, 0.0]
var _last_tick_ms := -1
var _was_open: Array[bool] = [true, true, true, true, true, false]
var _last_spoke_ms := -1
var enable_connectome_coupling: bool = true

## THE ONE BRAIN. Built here, stepped by whoever owns the sample loop, and read
## by everybody through get_fly_state(). The three names below are kept as
## read-only windows onto it so that nothing that used to reach for
## character.mushroom_body has to learn a new word.
var fly_brain: RefCounted = null

var mushroom_body: RefCounted:
	get:
		return fly_brain.mushroom_body if fly_brain != null else null

var giant_fiber: RefCounted:
	get:
		return fly_brain.giant_fiber if fly_brain != null else null

var circadian_clock: RefCounted:
	get:
		return fly_brain.circadian_clock if fly_brain != null else null

var central_complex: RefCounted:
	get:
		return fly_brain.central_complex if fly_brain != null else null


func _init() -> void:
	fly_brain = FlyBrainScript.new()
	fly_brain.startled.connect(_on_giant_fiber_startled)


## One sensory sample, one step of the whole fly brain.
func feed_senses(sample: Dictionary, dt_sec: float) -> void:
	if fly_brain != null:
		fly_brain.feed(sample, dt_sec)


## Something happened that the mushroom body should learn from. See
## FlyBrain.REWARDS for the names. Returns the valence that was applied.
func reward_event(kind: String) -> float:
	if fly_brain == null:
		return 0.0
	return float(fly_brain.reward_event(kind))


## The six needs under their transmitter names, for anyone reading the brain.
func get_neuromodulators() -> Dictionary:
	return {
		"dopamine": _fullness[LINE_BODY],
		"npf": _fullness[LINE_FOOD],
		"octopamine": _fullness[LINE_BREATH],
		"gaba": _fullness[LINE_REST],
		"serotonin": _fullness[LINE_REST],
		"acetylcholine": _fullness[LINE_FOCUS],
		"fruitless": _fullness[LINE_CONNECTION],
	}


## The whole readable brain state plus the six neuromodulators, one dictionary.
func get_fly_state() -> Dictionary:
	var out: Dictionary = fly_brain.state() if fly_brain != null else {}
	out.merge(get_neuromodulators(), true)
	return out


func _on_giant_fiber_startled(intensity: float, _reason: String) -> void:
	# Flight arousal spike (Octopamine)
	_set_fullness(LINE_BREATH, _fullness[LINE_BREATH] + 0.25 * intensity)
	# Mild suppression of rest due to acute startle
	_set_fullness(LINE_REST, clampf(_fullness[LINE_REST] * (1.0 - 0.2 * intensity), 0.0, 1.0))


static func _rate_per_ms(line0: int) -> float:
	var hours: float = HALF_LIFE_HOURS[line0]
	var half_life_ms := hours * 3600.0 * 1000.0
	return 0.5 / half_life_ms


func tick(now_ms: int) -> void:
	if _last_tick_ms < 0:
		_last_tick_ms = now_ms
		_sync_open_state()
		return
	var elapsed: int = maxi(0, now_ms - _last_tick_ms)
	if elapsed > 0:
		var dt_sec: float = float(elapsed) / 1000.0
		# 1. Baseline metabolic decay
		for i in NEED_COUNT:
			var loss: float = _rate_per_ms(i) * float(elapsed)
			_set_fullness(i, _fullness[i] - loss)
		
		# 2. Connectome-constrained synaptic cross-coupling (FlyWire matrix)
		if enable_connectome_coupling and dt_sec > 0.0:
			var packed := PackedFloat64Array()
			packed.resize(NEED_COUNT)
			for i in NEED_COUNT:
				packed[i] = _fullness[i]
			var coupled := FlyConductanceScript.step_coupling(packed, dt_sec)
			for i in NEED_COUNT:
				_set_fullness(i, float(coupled[i]))
				
	_last_tick_ms = now_ms


func _set_fullness(line0: int, value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	_fullness[line0] = clamped
	var now_open: bool = clamped >= OPEN_THRESHOLD
	if now_open != _was_open[line0]:
		_was_open[line0] = now_open
		if now_open:
			line_opened.emit(line0 + 1)
		else:
			line_closed.emit(line0 + 1)


func _sync_open_state() -> void:
	for i in NEED_COUNT:
		_was_open[i] = _fullness[i] >= OPEN_THRESHOLD


func feed(line: int, strength: float, source: String, now_ms: int) -> void:
	if line < 1 or line > NEED_COUNT:
		refused.emit("no such line: %d" % line)
		return
	if strength <= 0.0:
		refused.emit("feed strength must be positive")
		return
	var line0 := line - 1
	if line0 == LINE_CONNECTION and source != ATTESTED:
		refused.emit("connection requires an attested source, got: %s" % source)
		return
	tick(now_ms)
	_set_fullness(line0, _fullness[line0] + strength)


func is_open(line: int) -> bool:
	return _fullness[line - 1] >= OPEN_THRESHOLD


func get_fullness(line0: int) -> float:
	if line0 >= 0 and line0 < NEED_COUNT:
		return _fullness[line0]
	return 0.0


func lines() -> int:
	var bits := 0
	for i in NEED_COUNT:
		if _fullness[i] >= OPEN_THRESHOLD:
			bits |= 1 << i
	return bits


func hexagram_text_key() -> String:
	var s := ""
	for i in NEED_COUNT:
		s += "1" if _fullness[i] >= OPEN_THRESHOLD else "0"
	return s


func changing_line(now_ms: int) -> int:
	tick(now_ms)
	var best_line := 0
	var best_dist := CHANGING_BAND
	for i in NEED_COUNT:
		var dist: float = absf(_fullness[i] - OPEN_THRESHOLD)
		if dist <= best_dist:
			best_dist = dist
			best_line = i + 1
	return best_line


func vitality() -> float:
	var total := 0.0
	for f in _fullness:
		total += f
	return total / float(NEED_COUNT)


func mood() -> String:
	var v := vitality()
	if v >= 0.75:
		return MOOD_RADIANT
	if v >= 0.5:
		return MOOD_STEADY
	if v >= 0.25:
		return MOOD_QUIET
	return MOOD_SLUGGISH


func say_the_daily_thing(now_ms: int) -> void:
	if _last_spoke_ms >= 0 and now_ms - _last_spoke_ms < DAILY_WINDOW_MS:
		return
	var line := changing_line(now_ms)
	if line == 0:
		line = _lowest_need_line()
	_last_spoke_ms = now_ms
	var need_name: String = NEED_NAMES[line - 1]
	spoke.emit("tend your %s" % need_name)


func _lowest_need_line() -> int:
	var best_line := 1
	var best_fullness: float = _fullness[0]
	for i in range(1, NEED_COUNT):
		if _fullness[i] < best_fullness:
			best_fullness = _fullness[i]
			best_line = i + 1
	return best_line


## Returns the Q6 bias vector in [-1.0, 1.0]^6 for Q6Lattice, optionally blended with learned habit biases
func to_q6_bias(incorporate_habits: bool = true) -> PackedFloat64Array:
	var p := PackedFloat64Array()
	p.resize(NEED_COUNT)
	for i in NEED_COUNT:
		p[i] = _fullness[i]
	var base_bias: PackedFloat64Array = FlyConductanceScript.to_q6_bias(p)
	if incorporate_habits and mushroom_body != null:
		var habit_biases: Array[float] = mushroom_body.predict_habit_bias()
		for i in NEED_COUNT:
			base_bias[i] = clampf(float(base_bias[i]) * 0.85 + habit_biases[i] * 0.15, -1.0, 1.0)
	return base_bias


## Returns biological metadata for a line (0..5)
func fly_neuromodulator(line0: int) -> Dictionary:
	if line0 >= 0 and line0 < NEED_COUNT:
		return FLY_NEUROMODULATORS[line0]
	return {}


func to_dict() -> Dictionary:
	var needs := {}
	for i in NEED_COUNT:
		needs[NEED_NAMES[i]] = _fullness[i]
	return {
		"schema": SCHEMA_VERSION,
		"needs": needs,
		"last_tick_ms": _last_tick_ms,
		"last_spoke_ms": _last_spoke_ms,
	}


func from_dict(d: Dictionary) -> void:
	var schema: int = int(d.get("schema", 1))
	var needs: Dictionary = d.get("needs", {})
	for i in NEED_COUNT:
		var v: Variant = needs.get(NEED_NAMES[i], _fullness[i])
		_fullness[i] = clampf(float(v), 0.0, 1.0)
	if schema < 2 and _fullness[LINE_CONNECTION] >= OPEN_THRESHOLD:
		_fullness[LINE_CONNECTION] = V1_CONNECTION_CLAMP
	_last_tick_ms = int(d.get("last_tick_ms", -1))
	_last_spoke_ms = int(d.get("last_spoke_ms", -1))
	_sync_open_state()
