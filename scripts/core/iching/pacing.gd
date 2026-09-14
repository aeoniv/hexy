class_name Pacing
extends RefCounted

## THE ALCHEMICAL FIRE, taken out of the device and made testable.
##
## One figure walks toward another ONE LINE AT A TIME, and the line it turns is
## always the LOWEST that differs. Two fires may turn it:
##
##   Civil (wen huo): stillness held for one resting breath, 2.5 s of dwell.
##   Martial (wu huo): a kinetic surge, excitation at or past 0.85.
##
## WHICH LINE TURNS IS THE CUBE'S TO SAY. Pacing carries a 64-entry mass over
## Q6 -- the six-cube whose corners are the figures and whose edges are single
## lines -- and every tick it diffuses that mass and reweights it by a six-line
## bias read off the two elections. The next figure is the ONE-LINE NEIGHBOUR
## of the body holding the most mass. The fire decides WHEN; the cube decides
## WHICH, and at a large beta the cube agrees with the owner's original rule.
##
## Pure: no Input, no Time, no Node. The caller passes now_ms, so a test may
## make a minute pass in a line and a phone may pass it at sixty hertz.

## Seconds of stillness dwell before the civil fire turns a line.
const CIVIL_FIRE_THRESHOLD: float = 2.5
## Seconds since the last flip before the civil fire may turn another.
const REARM: float = 2.0
## Seconds since the last flip before the martial fire may turn another.
const MUTATION_COOLDOWN: float = 3.5
## Excitation at which the martial fire takes over.
const MARTIAL_THRESHOLD: float = 0.85
## Seconds both fires are held after an inject, so a cast may settle.
const INJECT_LOCKOUT: float = 2.5

## DIFFUSION TIME, BY BRANCH. Civil fire is a held breath: it must barely move
## the mass, so the neighbourhood it reads is the body's own immediate one and
## the bias decides among six corners. Martial fire is a surge: it throws the
## mass wide across the cube, so a far corner's pull can reach back and change
## which of the six neighbours lies on the way to it. Both are then SCALED by
## how much of that branch's own quantity is actually present -- stillness for
## the civil, excitation for the martial -- so a fire barely lit spreads
## barely anything.
const CIVIL_T: float = 0.06
const MARTIAL_T: float = 0.90
## How hard the Gibbs reweight listens to the bias. Large beta is the owner's
## original rule exactly; it is a var so a test may drive it.
const DEFAULT_BETA: float = 2.5
## Two neighbours within this RELATIVE distance of each other are a TIE, and a
## tie goes to the lower line. It has to be relative: at a large beta the six
## neighbours of a body far from the target all sit around 1e-68, and an
## absolute epsilon there would call every pair of them equal. The cube's
## symmetry makes those six exactly equal in arithmetic and only nearly equal
## in floating point, and "nearly" must not be allowed to decide which line of
## a person's body turns.
const TIE_EPSILON: float = 1e-9
## HOW MUCH OF THE BODY'S OWN CORNER IS PUT BACK EACH TICK. The mass is a cloud
## around where the body actually STANDS, not a forecast of where it will end
## up: left to run, the Gibbs reweight would pile every last grain on the target
## corner and the six neighbours would all read zero, which is a tie the cube
## never meant to call. Re-anchoring keeps the neighbourhood readable and keeps
## the answer a walk rather than a teleport.
const ANCHOR: float = 0.5

## The two reasons, in the owner's own glyphs.
const CIVIL_REASON: String = "Civil Fire (文火): 1 Breath Stillness Anchor ➔ Line %d (%s) %s"
const MARTIAL_REASON: String = "Martial Fire (武火): Kinetic Surge ➔ Line %d (%s) %s"
const YANG_WORD: String = "Ignited into Yang ⚊"
const YIN_WORD: String = "Yielded into Yin ⚋"

## Line 1 at the bottom, line 6 at the top: the six habits of a body.
const LINE_NAMES: Array[String] = ["Body", "Food", "Breath", "Rest", "Focus", "Connection"]

## The BODY figure this object is walking.
var bits: int = 0

## How hard the cube listens to the six-line bias. At DEFAULT_BETA the mass has
## room to disagree with the lowest differing line; very large, it cannot.
var beta: float = DEFAULT_BETA

## THE CUBE ITSELF -- one Q6Core, which is the native Q6 inside the ixmnn
## plugin when there is one and the same arithmetic in GDScript when there is
## not. The mass over the 64 corners lives in there, seeded on the body and
## carried tick to tick, and it is the SAME state the Qwen decode loop reads as
## a prior. Pacing is built first, so Pacing holds the native lease.
var cube: Q6Core = Q6Core.new()

## The mass over the 64 corners, read out of the cube. Kept as a property so
## every old reader still reads the same 64 numbers.
var mass: PackedFloat64Array:
	get:
		return cube.state()

var _last_tick_ms: int = -1
var _last_target_bits: int = -1
var _dwell: float = 0.0
var _last_flip_s: float = -1000.0
var _lockout_until_s: float = -1000.0


## One beat. Returns {} when nothing turned, else
## {bits, line, to_yang, reason, kind} with kind "civil" or "martial".
func tick(now_ms: int, target_bits: int, stillness: float, excitation: float,
		machine_margin: float = 1.0, human_margin: float = 1.0) -> Dictionary:
	var now_s: float = float(now_ms) / 1000.0
	var delta: float = 0.0
	if _last_tick_ms >= 0:
		delta = minf(1.0, float(now_ms - _last_tick_ms) / 1000.0)
	_last_tick_ms = now_ms
	var target: int = target_bits & 63
	var locked: bool = now_s < _lockout_until_s

	# THE CUBE MOVES EVERY TICK, gate or no gate. A mass that only stirred on
	# the beat it was read would be a lookup table with extra arithmetic.
	_diffuse(target, stillness, excitation, machine_margin, human_margin)

	# Branch 1: Civil Fire -- stillness dwell, one resting breath.
	if target != bits:
		if target == _last_target_bits:
			if stillness > 0.4:
				_dwell += delta * stillness * 1.15
				if _dwell >= CIVIL_FIRE_THRESHOLD and (now_s - _last_flip_s) >= REARM and not locked:
					return _flip(target, now_s, "civil")
			else:
				_dwell = maxf(0.0, _dwell - delta * 0.5)
		else:
			_last_target_bits = target
			_dwell = 0.0
	else:
		_dwell = 0.0

	# Branch 2: Martial Fire -- a kinetic surge shakes a line over.
	if excitation >= MARTIAL_THRESHOLD and (now_s - _last_flip_s) >= MUTATION_COOLDOWN and not locked:
		if target != bits:
			return _flip(target, now_s, "martial")

	return {}


## A head cast lands in the body: re-anchor, zero the dwell, and hold BOTH
## fires for INJECT_LOCKOUT seconds so the figure a person just threw is the
## figure they see.
func inject(bits_in: int, now_ms: int) -> void:
	bits = bits_in & 63
	cube.inject(bits)
	_dwell = 0.0
	_last_target_bits = -1
	_lockout_until_s = float(now_ms) / 1000.0 + INJECT_LOCKOUT


func reset(bits_in: int = 0) -> void:
	bits = bits_in & 63
	cube.reset(bits)
	beta = DEFAULT_BETA
	_last_tick_ms = -1
	_last_target_bits = -1
	_dwell = 0.0
	_last_flip_s = -1000.0
	_lockout_until_s = -1000.0


## Seconds of stillness banked so far, 0..CIVIL_FIRE_THRESHOLD.
func dwell() -> float:
	return _dwell


## THE SIX-LINE BIAS, read off the 8x8 target and scaled by how sure the two
## elections are. A trigram that won by a hair pulls at its three lines by a
## hair. Lines 0..2 are the machine's (lower) trigram, lines 3..5 the human's.
static func bias_of(target_bits: int, machine_margin: float,
		human_margin: float) -> PackedFloat64Array:
	return Q6Core.bias_of(target_bits, machine_margin, human_margin)


## One heat step under that bias. The time is the branch's: civil barely
## spreads, martial throws wide, and each is scaled by its own fire.
func _diffuse(target: int, stillness: float, excitation: float,
		machine_margin: float, human_margin: float) -> void:
	var bias: PackedFloat64Array = bias_of(target, machine_margin, human_margin)
	var t: float = CIVIL_T * clampf(stillness, 0.0, 1.0)
	if excitation >= MARTIAL_THRESHOLD:
		t = MARTIAL_T * clampf(excitation, 0.0, 1.0)
	cube.anchor(bits, ANCHOR)
	cube.step(bias, t, beta)


## THE NEXT FIGURE IS A NEIGHBOUR, never a jump: of the six corners one line
## from the body, the one holding the most mass. Ties go to the lowest line, so
## the answer is the cube's and never chance's.
func best_neighbour() -> int:
	return cube.best_neighbour(bits)


## THE LOWEST DIFFERING BIT, and nothing else. A figure walks; it does not
## jump. This is the owner's original rule, kept as the reference the cube is
## measured against: at a large enough beta `best_neighbour` returns this.
static func lowest_differing_bit(from_bits: int, to_bits: int) -> int:
	var diff: int = (from_bits ^ to_bits) & 63
	for b in range(6):
		if ((diff >> b) & 1) == 1:
			return b
	return -1


func _flip(target: int, now_s: float, kind: String) -> Dictionary:
	if ((bits ^ target) & 63) == 0:
		return {}
	var b: int = best_neighbour()
	if b < 0:
		return {}
	bits ^= (1 << b)
	_dwell = 0.0
	_last_flip_s = now_s
	var to_yang: bool = ((bits >> b) & 1) == 1
	var template: String = CIVIL_REASON if kind == "civil" else MARTIAL_REASON
	var reason: String = template % [b + 1, LINE_NAMES[b], YANG_WORD if to_yang else YIN_WORD]
	return {"bits": bits, "line": b, "to_yang": to_yang, "reason": reason, "kind": kind}


## Seconds still to wait before the MARTIAL fire may turn another line, given
## the host's clock. 0.0 means it is armed. The glass draws this as an arc; no
## other caller needs it, and nothing here changes state.
func refractory_s(now_ms: int) -> float:
	var since: float = float(now_ms) / 1000.0 - _last_flip_s
	return clampf(MUTATION_COOLDOWN - since, 0.0, MUTATION_COOLDOWN)
