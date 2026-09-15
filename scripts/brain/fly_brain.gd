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
