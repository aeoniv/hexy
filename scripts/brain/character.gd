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

## ============================ W8c -- THE ORGANISM ===========================
##
## THE HOMEOSTAT'S SIX LINE FILLS ARE THE BODY. Not a picture of it, not a
## cache of it: the body IS these six floats, and `bits` is a READOUT of them
## (each line yang where its fill crosses OPEN_THRESHOLD), computed on the way
## out and stored nowhere. Before W8c four outsiders wrote body bits behind the
## homeostat's back -- the glass through feed/reward paths, Alchemy through
## store.set_body with its own hysteresis, Entrain through a phase estimate,
## wmn through peer effects -- and the figure the glass drew was not the figure
## the needs were standing on.
##
## Now: senses in as Sense messages on a topic, one Body and one Phase out per
## tick, and `feed` / `reward_event` are this circuit's INTERNAL API, called
## from inside scripts/brain and nowhere else.
##
## WHAT THIS FILE TAKES OFF THE BUS (the rest goes to FlyBrain.route_sense):
##   tarsi     -> a line fill, directly. value {line:0..5, amount:float}.
##   pheromone -> the CONNECTION line, and only this organ may open it: a
##                conspecific is the one attested source there has ever been.
##                It also reaches FlyBrain as a social zeitgeber.
const BUS_TOPIC_SENSE := "/sense"
const BUS_TOPIC_BODY := "/body"
const BUS_TOPIC_PHASE := "/phase"

## The most one touch may pour into a line. A tarsal contact is evidence, not
## a refill.
const TARSI_MAX_STRENGTH: float = 0.5
## What one attested conspecific contact is worth to the connection line.
const PHEROMONE_STRENGTH: float = 0.1

var bus: RefCounted = null
var _bus_sub: int = -1


## Attach the organism to a topic bus. One subscription: everything on
## "/sense" comes here, the two organs this file owns are taken, and the rest
## is handed down to the fly brain's own routing.
func attach_bus(topic: RefCounted) -> void:
	if topic == null:
		return
	detach_bus()
	bus = topic
	_bus_sub = int(topic.subscribe(BUS_TOPIC_SENSE, Callable(self, "_on_sense")))


func detach_bus() -> void:
	if bus != null and _bus_sub >= 0:
		bus.unsubscribe(_bus_sub)
	bus = null
	_bus_sub = -1


func _on_sense(msg: Dictionary) -> void:
	route_sense(msg)


## Returns the organ that took the message, or "" when none did.
func route_sense(msg: Dictionary) -> String:
	if typeof(msg) != TYPE_DICTIONARY or String(msg.get("kind", "")) != "sense":
		return ""
	var organ: String = String(msg.get("organ", ""))
	var value: Variant = msg.get("value", null)
	var now_ms: int = int(msg.get("t_ns", 0)) / 1_000_000
	match organ:
		"tarsi":
			## W8e -- THE TILLER. A finger on the head ring says a heading,
			## not a line fill; the goal vector is the fan-shaped body's own.
			if String(msg.get("door", "")) == "head_tiller":
				if fly_brain != null and fly_brain.central_complex != null:
					fly_brain.central_complex.set_target_heading(float(value))
				return organ
			var line: int = int(_field(value, "line", -1.0))
			if line < 0 or line > 5:
				return ""
			## SIGNED. A touch may pour into a line or drain it; `feed` only
			## ever adds, and refuses the connection line to anything but an
			## attested source, so the draining half is done here -- inside the
			## brain, which is the only place a line fill may be written.
			var amount: float = clampf(
				_field(value, "amount", 0.0), -TARSI_MAX_STRENGTH, TARSI_MAX_STRENGTH)
			if is_zero_approx(amount):
				return ""
			var when: int = maxi(now_ms, _last_tick_ms)
			if amount > 0.0:
				feed(line + 1, amount, String(msg.get("door", "touch")), when)
			else:
				tick(when)
				_set_fullness(line, _fullness[line] + amount)
			return organ
		"pheromone":
			## THE ONLY ATTESTED SOURCE. A body cannot talk itself into being
			## connected; another body has to say so.
			var strength: float = clampf(
				_field(value, "strength", 1.0) * PHEROMONE_STRENGTH, 0.0, 1.0)
			if strength > 0.0:
				feed(LINE_CONNECTION + 1, strength, ATTESTED, maxi(now_ms, _last_tick_ms))
			if fly_brain != null:
				fly_brain.route_sense(msg)
			return organ
	if fly_brain == null:
		return ""
	return String(fly_brain.route_sense(msg))


## ONE BEAT OF THE ORGANISM. The needs decay and couple, the fly brain spends
## everything the bus handed it, and exactly two messages go out: the Body the
## six lines now are, and the Phase the clock now stands in.
func bus_tick(now_ms: int, dt_sec: float = -1.0) -> void:
	var dt: float = dt_sec
	if dt <= 0.0:
		dt = maxf(float(now_ms - _last_tick_ms) / 1000.0, 0.0001) if _last_tick_ms >= 0 else 0.0166
	tick(now_ms)
	if fly_brain != null:
		fly_brain.bus_tick(dt)
	publish_body(now_ms)
	publish_phase(now_ms)


## THE BODY, AS A MESSAGE. `bits` is the threshold readout of the six fills,
## computed here and stored nowhere.
func body_msg(now_ms: int = 0) -> Dictionary:
	return HexyMsg.body_from_fly_state(get_fly_state(), lines(), now_ms * 1_000_000)


func phase_msg(now_ms: int = 0) -> Dictionary:
	var f: Dictionary = fly_brain.phase_fields() if fly_brain != null else {}
	return HexyMsg.phase(now_ms * 1_000_000,
		float(f.get("seconds", 0.0)), float(f.get("day", 0.0)),
		float(f.get("weeks", 0.0)), String(f.get("life", "")), [])


func publish_body(now_ms: int = 0) -> bool:
	if bus == null:
		return false
	return bool(bus.publish(BUS_TOPIC_BODY, body_msg(now_ms)))


func publish_phase(now_ms: int = 0) -> bool:
	if bus == null:
		return false
	return bool(bus.publish(BUS_TOPIC_PHASE, phase_msg(now_ms)))


## A number out of a Sense value that may be a bare number or a dictionary.
static func _field(value: Variant, key: String, fallback: float) -> float:
	if typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has(key):
		return float((value as Dictionary)[key])
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value)
	return fallback
