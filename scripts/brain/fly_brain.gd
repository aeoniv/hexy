class_name FlyBrain
extends RefCounted

## THE ONE FLY BRAIN.
##
## One instance of each Drosophila subsystem, stepped exactly once per tick by
## whoever owns the sample loop, and read by everybody else through state().
## Before this existed the central complex and the giant fiber were built twice
## (once in the sensor oracle, once in the character) and the halves that the
## glass read were not the halves that were being stepped.
##
## STEP ORDER, and it matters:
##   1. Giant Fiber   -- the reflex is first because it overrides everything.
##   2. Central Complex -- heading integrates the gyro and the compass.
##   3. Circadian Clock -- the slow envelope over arousal.
##   4. Mushroom Body  -- projects the finished sensory context into Kenyon cells.

const FlyCentralComplexScript := preload("res://scripts/brain/fly_central_complex.gd")
const FlyMushroomBodyScript := preload("res://scripts/brain/fly_mushroom_body.gd")
const FlyGiantFiberScript := preload("res://scripts/brain/fly_giant_fiber.gd")
const FlyCircadianClockScript := preload("res://scripts/brain/fly_circadian_clock.gd")

## Re-emitted from the giant fiber so nobody has to reach inside for it.
signal startled(intensity: float, reason: String)

const TRIGRAM_NAMES: Array[String] = [
	"坤 Earth", "震 Thunder", "坎 Water", "兌 Lake",
	"艮 Mountain", "離 Fire", "巽 Wind", "乾 Heaven"
]

const SENSE_COUNT := 16

## DOPAMINERGIC VALENCE TABLE.
##
## The mushroom body only learns when a DAN fires, and a DAN only fires when
## something actually happened. These are the things that happen to Hexy, and
## what each is worth. Positive is PAM-like (reward, approach); negative is
## PPL1-like (punishment, avoid).
const REWARDS := {
	"cast_confirmed": 1.0,      # a reading was taken and stood
	"witness_received": 0.6,    # a peer answered across the mesh
	"find_landed": 0.8,         # the thing looked for was there
	"owner_tap": 0.4,           # a hand on the glass
	"startle": -1.0,            # the giant fiber fired
	"thermal_throttle": -0.6,   # the substrate is cooking
	"battery_critical": -0.8,   # the substrate is starving
}

var central_complex: RefCounted = null
var mushroom_body: RefCounted = null
var giant_fiber: RefCounted = null
var circadian_clock: RefCounted = null

## Last 16-input vector actually projected, kept so learn() can reinforce the
## pattern that was live when the reward arrived.
var last_senses: PackedFloat32Array = PackedFloat32Array()
var peers: int = 0


func _init() -> void:
	central_complex = FlyCentralComplexScript.new()
	mushroom_body = FlyMushroomBodyScript.new()
	giant_fiber = FlyGiantFiberScript.new()
	circadian_clock = FlyCircadianClockScript.new()
	last_senses.resize(SENSE_COUNT)
	last_senses.fill(0.0)
	_pending.resize(SENSE_COUNT)
	_pending.fill(0.0)
	giant_fiber.startled.connect(_on_startled)
	circadian_clock.update(12.0)


func _on_startled(intensity: float, reason: String) -> void:
	# A startle IS a punishment signal: the pattern that was live when the fly
	# was dropped is the pattern it should learn to avoid. Wired here so no
	# caller has to remember to do it.
	learn(REWARDS["startle"] * clampf(intensity, 0.0, 1.0))
	startled.emit(intensity, reason)


## Something happened. Name it, and the dopaminergic table decides what it is
## worth. Unknown names are ignored rather than guessed at.
func reward_event(kind: String) -> float:
	if not REWARDS.has(kind):
		return 0.0
	var valence: float = float(REWARDS[kind])
	learn(valence)
	return valence


## One sample, one step of the whole brain. Every key is optional; a missing
## key is a neutral one, so a caller with half a phone still gets a live brain.
func feed(sample: Dictionary, dt_sec: float) -> void:
	var dt: float = maxf(dt_sec, 0.0001)

	# 1. Giant fiber: the escape reflex reads raw acceleration.
	var accel: Vector3 = sample.get("accel", Vector3(0.0, -9.8, 0.0))
	giant_fiber.step(dt, accel)

	# 2. Central complex: yaw rate turns the bump; an absolute compass bearing,
	#    when the phone has one, pulls it toward the world instead of drifting.
	var yaw_rate: float = float(sample.get("gyro_yaw_rate", 0.0))
	central_complex.step(dt, yaw_rate, 0.0)
	if sample.has("heading_deg"):
		var world_rad: float = fposmod(deg_to_rad(float(sample["heading_deg"])), TAU)
		var diff: float = fposmod(world_rad - central_complex.current_heading + PI, TAU) - PI
		central_complex.current_heading = fposmod(
			central_complex.current_heading + diff * clampf(dt * 0.5, 0.0, 1.0), TAU)

	#    And the fan-shaped body's goal, when a hand on the head dial set one:
	#    the steering error the central complex already computes is finally
	#    spent on the heading, which is what makes the creature actually turn.
	central_complex.steer_toward_target(dt)

	# 3. Circadian clock.
	if sample.has("solar_hour"):
		circadian_clock.update(float(sample["solar_hour"]))
	else:
		circadian_clock.update(circadian_clock.solar_hour)

	# 4. Mushroom body projection of the 16 senses.
	peers = int(sample.get("peers", peers))
	var senses: Variant = sample.get("senses", null)
	if senses != null:
		var v: Array = []
		for i in range(SENSE_COUNT):
			var f: float = float(senses[i]) if i < senses.size() else 0.0
			v.append(f)
			last_senses[i] = f
		mushroom_body.encode_context(v)

	# 5. Sleep pruning. The clock says how much sleep is permitted right now;
	#    what sleep permits, it also protects, so an association made at night
	#    fades far slower than one made at noon.
	var mods: Dictionary = circadian_clock.get_circadian_modifiers()
	mushroom_body.decay(dt, float(mods.get("dfb_permissiveness", 0.5)))


## Hebbian reinforcement of whatever pattern is currently projected.
## Accepts a scalar valence or a 6-element per-need reward vector.
func learn(reward: Variant) -> void:
	if mushroom_body == null:
		return
	var rewards: Array = []
	if reward is Array or reward is PackedFloat32Array or reward is PackedFloat64Array:
		for r in reward:
			rewards.append(float(r))
	else:
		var scalar: float = float(reward)
		rewards = [scalar, scalar, scalar, scalar, scalar, scalar]
	if mushroom_body.active_kcs.is_empty() and last_senses.size() == SENSE_COUNT:
		var v: Array = []
		for f in last_senses:
			v.append(f)
		mushroom_body.encode_context(v)
	mushroom_body.learn(rewards)


## Everything anyone outside the brain is allowed to read, under fixed keys.
func state() -> Dictionary:
	var kcs: Array[int] = ([] as Array[int])
	for kc in mushroom_body.active_kcs:
		kcs.append(int(kc))
	var mods: Dictionary = circadian_clock.get_circadian_modifiers()
	return {
		"heading_rad": float(central_complex.current_heading),
		"dominant_trigram": TRIGRAM_NAMES[clampi(central_complex.dominant_trigram(), 0, 7)],
		"target_alignment": float(central_complex.target_alignment()),
		"coherence": float(central_complex.coherence()),
		"startle": float(giant_fiber.startle_intensity),
		"curl": float(giant_fiber.get_curl_factor()),
		"is_startled": bool(giant_fiber.is_startled),
		"pdf": float(circadian_clock.pdf_level),
		"phase": String(mods.get("phase_name", "Day")),
		"solar_hour": float(circadian_clock.solar_hour),
		"habit_bias": mushroom_body.predict_habit_bias(),
		"kc_active": kcs,
		"kc_count": kcs.size(),
		"peers": peers,
	}


## ============================== W8c -- THE BUS ==============================
##
## SENSES COME IN AS MESSAGES, AND ONLY AS MESSAGES. Before W8c four different
## outsiders reached into this brain and wrote parts of it (the glass through
## Character.feed, Alchemy through the store's body bits, Entrain through a
## phase estimate, wmn through peer effects). Now there is one door: a HexyMsg
## Sense published on a HexyTopic. The brain subscribes, routes by ORGAN, and
## publishes one Body and one Phase back. Nothing outside scripts/brain writes
## a line, and this file preloads nothing outside scripts/brain.
##
## ROUTING TABLE (organ -> circuit):
##   ocelli       -> circadian clock            (lux, measured; see update_lux)
##   halteres     -> central complex + giant fiber
##   compound_eye -> central complex + mushroom body
##   antenna      -> mushroom body + central complex
##   pheromone    -> circadian clock (social zeitgeber) + mushroom body
##   tarsi        -> the homeostat (Character; not this file's circuits)
##   words        -> mushroom body
##
## WHERE EACH ORGAN SITS IN THE 16-INPUT VECTOR the mushroom body projects.
## Fixed slots, so a pattern learnt from an antenna is not recalled from a
## word: the KC code IS the address.
const SLOT_COMPOUND_EYE := 0   # 0..7, the eight trigram scores
const SLOT_ANTENNA := 8        # 8..10
const SLOT_WORDS := 11         # 11..13
const SLOT_PHEROMONE := 14
const SLOT_OCELLI := 15

## The organs this brain answers to. Anything else published on "/sense" is
## ignored in silence -- an unknown organ is not an error, it is an organ this
## body does not have.
const BUS_ORGANS := ["ocelli", "halteres", "compound_eye", "antenna", "pheromone", "words"]

## The bus, when one is attached. Untyped on purpose: this file names no class
## outside scripts/brain, and a topic is duck-typed through publish/subscribe
## like everything else here.
var bus: RefCounted = null
var _bus_sub: int = -1

## THE PENDING SAMPLE. Sense messages land here between ticks; `bus_tick`
## spends them through feed(), so the step order at the top of this file is the
## same whether a caller feeds a sample directly or publishes messages.
var _pending: PackedFloat32Array = PackedFloat32Array()
var _accel: Vector3 = Vector3(0.0, -9.8, 0.0)
var _yaw_rate: float = 0.0
var _heading_deg: float = NAN
## How many sense messages have been routed since the last tick, so a caller
## can tell a quiet bus from a broken one.
var routed: int = 0


## Subscribe to a topic bus. Every "/sense" message is routed by organ; the
## per-door topics are fanned out from "/sense" by the bus itself, so one
## subscription hears them all.
func attach_bus(topic: RefCounted) -> void:
	if topic == null:
		return
	detach_bus()
	bus = topic
	_bus_sub = int(topic.subscribe("/sense", Callable(self, "_on_sense")))


func detach_bus() -> void:
	if bus != null and _bus_sub >= 0:
		bus.unsubscribe(_bus_sub)
	bus = null
	_bus_sub = -1


func _on_sense(msg: Dictionary) -> void:
	route_sense(msg)


## ONE SENSE MESSAGE INTO ONE SET OF CIRCUITS. Returns the organ that took it,
## or "" when nothing did -- a bogus organ, a malformed message, a sense this
## body has no organ for.
func route_sense(msg: Dictionary) -> String:
	if typeof(msg) != TYPE_DICTIONARY:
		return ""
	if String(msg.get("kind", "")) != "sense":
		return ""
	var organ: String = String(msg.get("organ", ""))
	if not BUS_ORGANS.has(organ):
		return ""
	var value: Variant = msg.get("value", null)
	if _pending.size() != SENSE_COUNT:
		_pending.resize(SENSE_COUNT)
	match organ:
		"ocelli":
			## THE REAL MEASUREMENT, not a guess from the hour. A dict may also
			## carry the solar hour when the host happens to know it.
			var lux: float = _num(value, "lux", -1.0)
			if lux >= 0.0:
				circadian_clock.update_lux(lux)
				_pending[SLOT_OCELLI] = circadian_clock.light_drive
			var hour: float = _num(value, "solar_hour", NAN)
			if not is_nan(hour):
				circadian_clock.update(hour)
		"halteres":
			## The fly's gyroscopes. The giant fiber reads the raw acceleration
			## and the central complex reads the yaw rate; both are spent on
			## the next tick, in the step order at the top of this file.
			_accel = _vec3(value, _accel)
			_yaw_rate = _num(value, "gyro_yaw_rate", _yaw_rate)
			var hd: float = _num(value, "heading_deg", NAN)
			if not is_nan(hd):
				_heading_deg = hd
		"compound_eye":
			## Eight trigram scores, straight into the ring attractor as a
			## stimulus, and into the first eight projection slots.
			var scores: Array = _floats(value, 8)
			central_complex.inject_stimulus(scores, 1.0)
			for i in range(8):
				_pending[SLOT_COMPOUND_EYE + i] = float(scores[i])
		"antenna":
			var odour: Array = _floats(value, 3)
			for i in range(3):
				_pending[SLOT_ANTENNA + i] = float(odour[i])
			## An odour plume has a direction as surely as a light does, so the
			## antennae lean the ring attractor as well as feeding the KCs.
			central_complex.inject_stimulus(_floats(value, 8), 0.35)
		"pheromone":
			## A CONSPECIFIC IS A CLOCK. Flies entrain to each other: a peer
			## that says what hour it is on pulls this pacemaker a little way
			## toward it, never all the way -- a social zeitgeber, not a reset.
			var peer_hour: float = _num(value, "solar_hour", NAN)
			if not is_nan(peer_hour):
				var here: float = circadian_clock.solar_hour
				var diff: float = fposmod(peer_hour - here + 12.0, 24.0) - 12.0
				circadian_clock.update(fposmod(here + diff * 0.1, 24.0))
			_pending[SLOT_PHEROMONE] = clampf(_num(value, "strength", 1.0), 0.0, 1.0)
		"words":
			## A word is not a number: a String (or {"text": String}) is hashed
			## down to three deterministic floats -- the same sentence always
			## lands on the same three slots, a different sentence lands
			## elsewhere, and an empty string leaves no stimulus at all. A
			## numeric payload (Array/bare number) still routes as before.
			var text: String = ""
			var is_text: bool = false
			if typeof(value) == TYPE_STRING:
				text = String(value)
				is_text = true
			elif typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has("text"):
				text = String((value as Dictionary)["text"])
				is_text = true
			if is_text:
				if text != "":
					var wv: Array = _text_vec3(text)
					for i in range(3):
						_pending[SLOT_WORDS + i] = float(wv[i])
			else:
				var w: Array = _floats(value, 3)
				for i in range(3):
					_pending[SLOT_WORDS + i] = float(w[i])
	routed += 1
	return organ


## ONE TICK OF THE BUS. Everything routed since the last call is spent here,
## through the same feed() a direct caller uses, so there is one step order and
## not two.
func bus_tick(dt_sec: float) -> void:
	if _pending.size() != SENSE_COUNT:
		_pending.resize(SENSE_COUNT)
	var senses: Array = []
	for f in _pending:
		senses.append(float(f))
	var sample: Dictionary = {
		"accel": _accel,
		"gyro_yaw_rate": _yaw_rate,
		"senses": senses,
	}
	if not is_nan(_heading_deg):
		sample["heading_deg"] = _heading_deg
	feed(sample, dt_sec)
	routed = 0


## THE CIRCADIAN PHASE, as a Phase message's two live fields. `weeks` and
## `life` are left at 0.0 and "" on purpose: this brain knows the day it is in
## and nothing longer, and a gauge fills the rest in W8e.
func phase_fields() -> Dictionary:
	var hour: float = float(circadian_clock.solar_hour)
	return {
		"seconds": fposmod(hour * 3600.0, 60.0) / 60.0,
		"day": clampf(hour / 24.0, 0.0, 1.0),
		"weeks": 0.0,
		"life": "",
	}


# -- reading a message's value, whatever shape it came in ---------------------

## A number out of a value that may be a bare float, or a dict with that key.
static func _num(value: Variant, key: String, fallback: float) -> float:
	if typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has(key):
		return float((value as Dictionary)[key])
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value)
	return fallback


## `n` floats out of a value that may be an Array, a bare number (which fills
## the first slot) or a dict carrying one under "v".
static func _floats(value: Variant, n: int) -> Array:
	var out: Array = []
	out.resize(n)
	out.fill(0.0)
	var src: Variant = value
	if typeof(src) == TYPE_DICTIONARY and (src as Dictionary).has("v"):
		src = (src as Dictionary)["v"]
	if typeof(src) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY]:
		var i: int = 0
		for f in src:
			if i >= n:
				break
			out[i] = float(f)
			i += 1
	elif typeof(src) in [TYPE_INT, TYPE_FLOAT]:
		out[0] = float(src)
	return out


## THREE FLOATS OUT OF A SENTENCE, heuristic-free and stable across runs and
## sessions: Godot's String.hash() is a fixed algorithm (not process-salted),
## so the same text always yields the same 32-bit hash here, on this install
## and the next. FlyHash (fly_hash.gd) projects a 768-dim embedding onto
## Kenyon cells -- it has nothing to say about a bare String, so this splits
## the hash's 24 low bits into three independent bytes instead, each
## normalised to 0..1. A different sentence almost certainly lands on a
## different hash and so a different triple.
static func _text_vec3(text: String) -> Array:
	var h: int = text.hash() & 0x7fffffff
	return [
		float(h & 0xFF) / 255.0,
		float((h >> 8) & 0xFF) / 255.0,
		float((h >> 16) & 0xFF) / 255.0,
	]


static func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value as Vector3
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		if d.has("accel"):
			return _vec3(d["accel"], fallback)
		if d.has("x") and d.has("y") and d.has("z"):
			return Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
	if typeof(value) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
