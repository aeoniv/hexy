class_name HexyMsg
extends RefCounted

## W8a — "msg + topic bus", the ROS shape without ROS.
##
## Four message kinds, all plain Dictionaries so they cross the wmn wire and
## JSON.stringify/parse unchanged (no Vector2, no typed Array, no custom
## objects inside a msg -- ints, floats, Strings, bools, Arrays and
## Dictionaries only). This file only builds and checks dictionaries; it must
## never preload anything under scripts/brain or scripts/glass -- the glass
## only looks and the organs know topics, not each other.

const KIND_SENSE := "sense"
const KIND_BODY := "body"
const KIND_PHASE := "phase"
const KIND_ACT := "act"

const SENSE_ORGANS := ["ocelli", "halteres", "tarsi", "compound_eye", "antenna", "pheromone", "words"]
const ACT_DOORS := ["speaker", "screen", "haptic", "radio"]


## ---------------------------------------------------------------- Sense ----
## {kind:"sense", organ, door, t_ns, value, meta}
static func sense(organ: String, door: String, t_ns: int, value, meta: Dictionary = {}) -> Dictionary:
	return {
		"kind": KIND_SENSE,
		"organ": organ,
		"door": door,
		"t_ns": t_ns,
		"value": value,
		"meta": meta,
	}


## ----------------------------------------------------------------- Body ----
## THE ONE BODY SHAPE for store, wire and radar.
##
## {kind:"body", t_ns, bits:int, lines:Array[float]x6, heading_rad:float,
##  activity:Array[float]x8, glow:float, phase:float, stage:String}
##
## Field mapping, read from the code that exists today:
##  - bits         -> HexyStore.body["bits"] / body_bits() / HexyStore.set_body().
##                     Six lines, hexagram bits & 63. Also the wmn wire's
##                     "body" byte (Wmn.broadcast payload["body"]).
##  - lines[6]      -> Character._fullness (LINE_BODY..LINE_CONNECTION, 0..1
##                     each), the same six needs get_neuromodulators() reads
##                     out as dopamine/npf/octopamine/gaba/serotonin/
##                     fruitless. Independent of bits: bits is the hexagram
##                     the needs cast, lines are the needs themselves.
##  - heading_rad   -> FlyCentralComplex.current_heading via
##                     Character.get_fly_state()["heading_rad"]; also
##                     Wmn.peers()[x]["heading_rad"] (a peer's bio pulse).
##  - activity[8]   -> the calcium bump FlyCalciumRadar2D rebuilds from
##                     heading_rad + coherence (bump_of()); stored here
##                     pre-baked so a Body carries what the radar would show
##                     without needing the radar object.
##  - glow          -> get_fly_state()["coherence"] (0..1), also feeds
##                     activity's sharpness.
##  - phase         -> get_fly_state()["phase"] (circadian phase NAME today,
##                     e.g. "Day"/"Night") is a string, not 0..1 -- kept here
##                     as the String Character actually produces; the 0..1
##                     circadian fraction lives on the Phase message instead
##                     (see below), so nothing is invented that state() does
##                     not already hand out.
##  - stage         -> Character.stage(), the organism's own FIRST-PERSON stage
##                     machine (scripts/brain/fly_stage.gd): "" while nothing
##                     pulls, then "approach" / "refusal" / "reward". Written
##                     by the brain on every Body and read by the glass; the
##                     per-peer "stage" int on peers() is the journey chapter
##                     of somebody else's walk and is a different thing.
static func body(t_ns: int, bits: int, lines: Array, heading_rad: float,
		activity: Array, glow: float, phase: String, stage: String = "") -> Dictionary:
	var lines6: Array = lines.duplicate()
	lines6.resize(6)
	for i in 6:
		if lines6[i] == null:
			lines6[i] = 0.0
		lines6[i] = clampf(float(lines6[i]), 0.0, 1.0)
	var activity8: Array = activity.duplicate()
	activity8.resize(8)
	for i in 8:
		if activity8[i] == null:
			activity8[i] = 0.0
		activity8[i] = float(activity8[i])
	return {
		"kind": KIND_BODY,
		"t_ns": t_ns,
		"bits": int(bits) & 63,
		"lines": lines6,
		"heading_rad": heading_rad,
		"activity": activity8,
		"glow": clampf(glow, 0.0, 1.0),
		"phase": phase,
		"stage": stage,
	}


## Build a Body from a Character.get_fly_state()-shaped dict plus the store
## bits the hexagram is standing on. `fs` is exactly what
## Character.get_fly_state() returns (fly_brain.state() merged with
## get_neuromodulators()): heading_rad, coherence, phase (name), plus
## dopamine/npf/octopamine/gaba/serotonin/fruitless.
##
## The eight-wedge activity is rebuilt with the same cosine-hill formula
## FlyCalciumRadar2D.bump_of() uses, so body_to_radar_state() round-trips the
## same picture the radar would draw -- duplicated here on purpose so msg.gd
## never preloads scripts/brain.
static func body_from_fly_state(fs: Dictionary, bits: int, t_ns: int = 0,
		stage: String = "") -> Dictionary:
	var heading: float = float(fs.get("heading_rad", 0.0))
	var coherence: float = clampf(float(fs.get("coherence", 0.0)), 0.0, 1.0)
	var lines: Array = [
		float(fs.get("dopamine", 0.0)),
		float(fs.get("npf", 0.0)),
		float(fs.get("octopamine", 0.0)),
		float(fs.get("gaba", 0.0)),
		float(fs.get("serotonin", 0.0)),
		float(fs.get("fruitless", 0.0)),
	]
	var activity := _bump_of(heading, coherence)
	return body(t_ns, bits, lines, heading, activity, coherence,
		String(fs.get("phase", "Day")), stage)


## The dict FlyCalciumRadar2D.set_state() accepts: heading_rad, coherence,
## is_startled, dopamine, serotonin, octopamine, gaba, acetylcholine (grep of
## fly_calcium_radar_2d.gd's `fs.get(` calls). A Body carries lines in the
## LINE_BODY..LINE_CONNECTION order (dopamine, npf, octopamine, gaba,
## serotonin, fruitless) -- acetylcholine (LINE_FOCUS) has no Body slot today,
## so it is passed through as 0.0; is_startled has no Body slot either and
## defaults false. Both are documented gaps, not silent inventions.
static func body_to_radar_state(b: Dictionary) -> Dictionary:
	var lines: Array = b.get("lines", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	return {
		"heading_rad": float(b.get("heading_rad", 0.0)),
		"coherence": float(b.get("glow", 0.0)),
		"is_startled": false,
		"dopamine": float(lines[0]) if lines.size() > 0 else 0.0,
		"serotonin": float(lines[4]) if lines.size() > 4 else 0.0,
		"octopamine": float(lines[2]) if lines.size() > 2 else 0.0,
		"gaba": float(lines[3]) if lines.size() > 3 else 0.0,
		"acetylcholine": 0.0,
	}


## The compact peer row Wmn.peers() puts on the wire: bits, heading_rad,
## phase, stage. cls/band/rssi/last_seen_ms are receiver-side (room
## presence), not part of the body itself, so they are not carried here.
static func body_to_wire(b: Dictionary) -> Dictionary:
	return {
		"bits": int(b.get("bits", 0)) & 63,
		"heading_rad": float(b.get("heading_rad", 0.0)),
		"phase": b.get("phase", null),
		"stage": b.get("stage", null),
		## GLOW RIDES BESIDE THE HEADING because a peer that is lit is a
		## different neighbour from a peer that is dim, and one float is a
		## price the presence pulse can pay. (see Wmn._presence_pulse)
		"glow": clampf(float(b.get("glow", 0.0)), 0.0, 1.0),
	}


## The inverse of body_to_wire(): a received peer row back into a (partial)
## Body. Fields the wire never carried (lines, activity, glow) come back
## zeroed/empty since the wire never sent them.
static func body_from_wire(row: Dictionary, t_ns: int = 0) -> Dictionary:
	return body(t_ns, int(row.get("bits", 0)),
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		float(row.get("heading_rad", 0.0)),
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		float(row.get("glow", 0.0)),
		String(row.get("phase", "")) if row.get("phase") != null else "",
		String(row.get("stage", "")) if row.get("stage") != null else "")


static func body_bits(b: Dictionary) -> int:
	return int(b.get("bits", 0)) & 63


static func body_from_bits(bits: int, t_ns: int = 0) -> Dictionary:
	return body(t_ns, bits, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		0.0, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, "")


## Same cosine-hill bump FlyCalciumRadar2D.bump_of() computes, kept local so
## msg.gd never preloads scripts/brain. See that function for the reasoning.
static func _bump_of(heading: float, coherence: float) -> Array:
	var out: Array = []
	var total: float = 0.0
	var sharp: float = 0.2 + 2.8 * clampf(coherence, 0.0, 1.0)
	for i in range(8):
		var ang: float = float(i) * TAU / 8.0
		var v: float = pow(maxf(0.0, 0.5 + 0.5 * cos(ang - heading)), sharp)
		out.append(v)
		total += v
	if total <= 0.0:
		return [0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125]
	for i in range(8):
		out[i] = out[i] / total
	return out


## ---------------------------------------------------------------- Phase ----
## {kind:"phase", t_ns, seconds, day, weeks, life, together}
static func phase(t_ns: int, seconds: float, day: float, weeks: float,
		life: String, together: Array = []) -> Dictionary:
	return {
		"kind": KIND_PHASE,
		"t_ns": t_ns,
		"seconds": clampf(seconds, 0.0, 1.0),
		"day": clampf(day, 0.0, 1.0),
		"weeks": weeks,
		"life": life,
		"together": together.duplicate(),
	}


## ------------------------------------------------------------------ Act ----
## {kind:"act", t_ns, door, value, meta}
static func act(door: String, t_ns: int, value, meta: Dictionary = {}) -> Dictionary:
	return {
		"kind": KIND_ACT,
		"door": door,
		"t_ns": t_ns,
		"value": value,
		"meta": meta,
	}


## ------------------------------------------------------------- validate ----
static func kind_of(msg: Dictionary) -> String:
	return String(msg.get("kind", ""))


static func validate(msg: Variant) -> bool:
	if typeof(msg) != TYPE_DICTIONARY:
		push_error("HexyMsg.validate: not a Dictionary")
		return false
	var d: Dictionary = msg
	if not d.has("kind"):
		push_error("HexyMsg.validate: missing 'kind'")
		return false
	var kind: String = String(d["kind"])
	match kind:
		KIND_SENSE:
			return _validate_sense(d)
		KIND_BODY:
			return _validate_body(d)
		KIND_PHASE:
			return _validate_phase(d)
		KIND_ACT:
			return _validate_act(d)
		_:
			push_error("HexyMsg.validate: unknown kind '%s'" % kind)
			return false


static func _validate_sense(d: Dictionary) -> bool:
	if not (d.has("organ") and typeof(d["organ"]) == TYPE_STRING):
		push_error("HexyMsg.validate(sense): missing/bad 'organ'")
		return false
	if not SENSE_ORGANS.has(String(d["organ"])):
		push_error("HexyMsg.validate(sense): unknown organ '%s'" % String(d["organ"]))
		return false
	if not (d.has("door") and typeof(d["door"]) == TYPE_STRING):
		push_error("HexyMsg.validate(sense): missing/bad 'door'")
		return false
	if not (d.has("t_ns") and _is_int_like(d["t_ns"])):
		push_error("HexyMsg.validate(sense): missing/bad 't_ns'")
		return false
	if not d.has("value"):
		push_error("HexyMsg.validate(sense): missing 'value'")
		return false
	if not (d.has("meta") and typeof(d["meta"]) == TYPE_DICTIONARY):
		push_error("HexyMsg.validate(sense): missing/bad 'meta'")
		return false
	return true


static func _validate_body(d: Dictionary) -> bool:
	if not (d.has("t_ns") and _is_int_like(d["t_ns"])):
		push_error("HexyMsg.validate(body): missing/bad 't_ns'")
		return false
	if not (d.has("bits") and _is_int_like(d["bits"])):
		push_error("HexyMsg.validate(body): missing/bad 'bits'")
		return false
	if not (d.has("lines") and typeof(d["lines"]) in [TYPE_ARRAY] and d["lines"].size() == 6):
		push_error("HexyMsg.validate(body): 'lines' must be an Array of 6")
		return false
	if not (d.has("heading_rad") and _is_num_like(d["heading_rad"])):
		push_error("HexyMsg.validate(body): missing/bad 'heading_rad'")
		return false
	if not (d.has("activity") and typeof(d["activity"]) in [TYPE_ARRAY] and d["activity"].size() == 8):
		push_error("HexyMsg.validate(body): 'activity' must be an Array of 8")
		return false
	if not (d.has("glow") and _is_num_like(d["glow"])):
		push_error("HexyMsg.validate(body): missing/bad 'glow'")
		return false
	if not (d.has("phase") and typeof(d["phase"]) == TYPE_STRING):
		push_error("HexyMsg.validate(body): missing/bad 'phase'")
		return false
	if not (d.has("stage") and typeof(d["stage"]) == TYPE_STRING):
		push_error("HexyMsg.validate(body): missing/bad 'stage'")
		return false
	return true


static func _validate_phase(d: Dictionary) -> bool:
	if not (d.has("t_ns") and _is_int_like(d["t_ns"])):
		push_error("HexyMsg.validate(phase): missing/bad 't_ns'")
		return false
	if not (d.has("seconds") and _is_num_like(d["seconds"])):
		push_error("HexyMsg.validate(phase): missing/bad 'seconds'")
		return false
	if not (d.has("day") and _is_num_like(d["day"])):
		push_error("HexyMsg.validate(phase): missing/bad 'day'")
		return false
	if not (d.has("weeks") and _is_num_like(d["weeks"])):
		push_error("HexyMsg.validate(phase): missing/bad 'weeks'")
		return false
	if not (d.has("life") and typeof(d["life"]) == TYPE_STRING):
		push_error("HexyMsg.validate(phase): missing/bad 'life'")
		return false
	if not (d.has("together") and typeof(d["together"]) == TYPE_ARRAY):
		push_error("HexyMsg.validate(phase): missing/bad 'together'")
		return false
	return true


static func _validate_act(d: Dictionary) -> bool:
	if not (d.has("door") and typeof(d["door"]) == TYPE_STRING):
		push_error("HexyMsg.validate(act): missing/bad 'door'")
		return false
	if not ACT_DOORS.has(String(d["door"])):
		push_error("HexyMsg.validate(act): unknown door '%s'" % String(d["door"]))
		return false
	if not (d.has("t_ns") and _is_int_like(d["t_ns"])):
		push_error("HexyMsg.validate(act): missing/bad 't_ns'")
		return false
	if not d.has("value"):
		push_error("HexyMsg.validate(act): missing 'value'")
		return false
	if not (d.has("meta") and typeof(d["meta"]) == TYPE_DICTIONARY):
		push_error("HexyMsg.validate(act): missing/bad 'meta'")
		return false
	return true


static func _is_int_like(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _is_num_like(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
