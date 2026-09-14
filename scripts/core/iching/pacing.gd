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

## THE LIVE TUNABLES. Every one of them starts at the const above it, so a
## Pacing built in a test that never asks for a HexyConfig behaves exactly as
## it did before this drawer existed. When a config DOES exist, `_sync_config`
## pulls these across -- by REVISION, not by signal, because Pacing is a
## RefCounted and a connected signal would keep it alive as long as the config.
var civil_fire_s: float = CIVIL_FIRE_THRESHOLD
var rearm_s: float = REARM
var mutation_cooldown_s: float = MUTATION_COOLDOWN
var martial_threshold: float = MARTIAL_THRESHOLD
var inject_lockout_s: float = INJECT_LOCKOUT
var civil_t: float = CIVIL_T
var martial_t: float = MARTIAL_T
var anchor: float = ANCHOR
var journal_max: int = JOURNAL_MAX

## The config revision these vars were last pulled at. -1 is "never pulled".
var _cfg_revision: int = -1

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


## A Pacing born while a HexyConfig exists starts already tuned by it. One that
## is born without one -- every test that does not ask for a drawer -- keeps
## its consts, and `peek` is used rather than `instance` precisely so asking
## cannot CREATE the thing being asked about.
func _init() -> void:
	_sync_config()


## Pull the tunables across, but only when the drawer has actually moved. Also
## the manual door: `configure` hands the same dictionary in by hand.
func _sync_config() -> void:
	var cfg: HexyConfig = HexyConfig.peek()
	if cfg == null or cfg.revision() == _cfg_revision:
		return
	_cfg_revision = cfg.revision()
	configure({
		"civil_fire_s": cfg.get_value("pacing.civil_fire_s"),
		"rearm_s": cfg.get_value("pacing.rearm_s"),
		"mutation_cooldown_s": cfg.get_value("pacing.mutation_cooldown_s"),
		"martial_threshold": cfg.get_value("pacing.martial_threshold"),
		"inject_lockout_s": cfg.get_value("pacing.inject_lockout_s"),
		"civil_t": cfg.get_value("pacing.civil_t"),
		"martial_t": cfg.get_value("pacing.martial_t"),
		"beta": cfg.get_value("pacing.beta"),
		"anchor": cfg.get_value("pacing.anchor"),
		"journal_max": cfg.get_value("pacing.journal_max"),
	})


## Set any subset of the tunables by name. Keys not present are left alone, so
## a caller may hand over one number without knowing the other nine.
func configure(cfg: Dictionary) -> void:
	if cfg.has("civil_fire_s"): civil_fire_s = float(cfg["civil_fire_s"])
	if cfg.has("rearm_s"): rearm_s = float(cfg["rearm_s"])
	if cfg.has("mutation_cooldown_s"): mutation_cooldown_s = float(cfg["mutation_cooldown_s"])
	if cfg.has("martial_threshold"): martial_threshold = float(cfg["martial_threshold"])
	if cfg.has("inject_lockout_s"): inject_lockout_s = float(cfg["inject_lockout_s"])
	if cfg.has("civil_t"): civil_t = float(cfg["civil_t"])
	if cfg.has("martial_t"): martial_t = float(cfg["martial_t"])
	if cfg.has("beta"): beta = float(cfg["beta"])
	if cfg.has("anchor"): anchor = float(cfg["anchor"])
	if cfg.has("journal_max"): journal_max = maxi(1, int(cfg["journal_max"]))

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

## THE REPLAY LOG. Append-only, one entry per write to the cube -- reset,
## inject, step (every `tick`, gate or no gate, since `_diffuse` runs every
## tick), and flip. Named `journal` and not `log` so nothing here shadows a
## future logger. Bounded at JOURNAL_MAX and oldest-first-dropped, because a
## body left running for a day must not carry a day of history in RAM: this
## is a recent-past debugger and a test fixture, not an audit trail.
var journal: Array[Dictionary] = []

## Ring size of the journal. Past this many entries the oldest is dropped.
const JOURNAL_MAX: int = 4096


## One beat. Returns {} when nothing turned, else
## {bits, line, to_yang, reason, kind} with kind "civil" or "martial".
func tick(now_ms: int, target_bits: int, stillness: float, excitation: float,
		machine_margin: float = 1.0, human_margin: float = 1.0) -> Dictionary:
	_sync_config()
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
	var step_kind: String = "martial" if excitation >= martial_threshold else "civil"
	_journal_push(now_ms, "step", bits, bits, step_kind)

	# Branch 1: Civil Fire -- stillness dwell, one resting breath.
	if target != bits:
		if target == _last_target_bits:
			if stillness > 0.4:
				_dwell += delta * stillness * 1.15
				if _dwell >= civil_fire_s and (now_s - _last_flip_s) >= rearm_s and not locked:
					return _flip(target, now_s, "civil")
			else:
				_dwell = maxf(0.0, _dwell - delta * 0.5)
		else:
			_last_target_bits = target
			_dwell = 0.0
	else:
		_dwell = 0.0

	# Branch 2: Martial Fire -- a kinetic surge shakes a line over.
	if excitation >= martial_threshold and (now_s - _last_flip_s) >= mutation_cooldown_s and not locked:
		if target != bits:
			return _flip(target, now_s, "martial")

	return {}


## A head cast lands in the body: re-anchor, zero the dwell, and hold BOTH
## fires for INJECT_LOCKOUT seconds so the figure a person just threw is the
## figure they see.
func inject(bits_in: int, now_ms: int) -> void:
	var before: int = bits
	bits = bits_in & 63
	cube.inject(bits)
	_dwell = 0.0
	_last_target_bits = -1
	_lockout_until_s = float(now_ms) / 1000.0 + inject_lockout_s
	_journal_push(now_ms, "inject", before, bits, "inject")


## `now_ms` is optional and defaults to 0 so every existing caller -- which
## never passed a clock to a reset -- still compiles unchanged; it only
## timestamps the journal entry.
func reset(bits_in: int = 0, now_ms: int = 0) -> void:
	var before: int = bits
	bits = bits_in & 63
	cube.reset(bits)
	beta = DEFAULT_BETA
	_cfg_revision = -1
	_sync_config()
	_last_tick_ms = -1
	_last_target_bits = -1
	_dwell = 0.0
	_last_flip_s = -1000.0
	_lockout_until_s = -1000.0
	_journal_push(now_ms, "reset", before, bits, "reset")


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
	var t: float = civil_t * clampf(stillness, 0.0, 1.0)
	if excitation >= martial_threshold:
		t = martial_t * clampf(excitation, 0.0, 1.0)
	cube.anchor(bits, anchor)
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
	var before: int = bits
	var b: int = best_neighbour()
	if b < 0:
		return {}
	bits ^= (1 << b)
	_dwell = 0.0
	_last_flip_s = now_s
	var to_yang: bool = ((bits >> b) & 1) == 1
	var template: String = CIVIL_REASON if kind == "civil" else MARTIAL_REASON
	var reason: String = template % [b + 1, LINE_NAMES[b], YANG_WORD if to_yang else YIN_WORD]
	_journal_push(int(round(now_s * 1000.0)), "flip", before, bits, kind, {
		"line": b, "to_yang": to_yang, "reason": reason,
	})
	return {"bits": bits, "line": b, "to_yang": to_yang, "reason": reason, "kind": kind}


## Seconds still to wait before the MARTIAL fire may turn another line, given
## the host's clock. 0.0 means it is armed. The glass draws this as an arc; no
## other caller needs it, and nothing here changes state.
func refractory_s(now_ms: int) -> float:
	var since: float = float(now_ms) / 1000.0 - _last_flip_s
	return clampf(mutation_cooldown_s - since, 0.0, mutation_cooldown_s)


# --- the replay log ----------------------------------------------------------

## One line in the journal: the cube's own argmax and tension AFTER the write,
## so a reader never has to re-derive them. `extra` carries a flip's line,
## to_yang and reason -- the three things only a flip has.
func _journal_push(now_ms: int, op: String, bits_before: int, bits_after: int,
		kind: String = "", extra: Dictionary = {}) -> void:
	var entry: Dictionary = {
		"t_ms": now_ms, "op": op,
		"bits_before": bits_before & 63, "bits_after": bits_after & 63,
		"argmax": cube.argmax(), "tension": cube.tension(),
		"kind": kind,
	}
	for k in extra:
		entry[k] = extra[k]
	journal.append(entry)
	if journal.size() > journal_max:
		journal.remove_at(0)


## A duplicate of the journal, so a caller may hold onto it while ticks keep
## appending to the live one underneath.
func journal_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in journal:
		out.append(e.duplicate())
	return out


## RE-DRIVE THE CUBE FROM ITS OWN JOURNAL, honestly and no further than that.
## `reset` and `inject` are replayed exactly, because the journal holds every
## number either one needs. A `flip` is replayed by setting the SAME line the
## original flip set -- the journal already says which line and which way, so
## this is playback of the outcome, not a re-run of `best_neighbour`.
##
## A `step` CANNOT be replayed from the log alone: it would need the bias, the
## time and beta that produced it, none of which the journal carries, and
## reconstructing them from stillness/excitation would bias the cube in a way
## nothing here can vouch for. `replay` skips step entries outright, leaving
## the cube parked on whatever the last reset/inject/flip left it on. A test
## that wants the diffusion back too has to re-drive `tick` itself with the
## same inputs and compare the resulting argmax/tension to the journal's.
func replay(entries: Array[Dictionary], upto: int = -1) -> void:
	if entries.is_empty():
		return
	var last: int = entries.size() - 1
	var end: int = last if upto < 0 else mini(upto, last)

	bits = int(entries[0].get("bits_before", 0)) & 63
	cube.reset(bits)

	for i in range(end + 1):
		var e: Dictionary = entries[i]
		match String(e.get("op", "")):
			"reset":
				bits = int(e.get("bits_after", bits)) & 63
				cube.reset(bits)
			"inject":
				bits = int(e.get("bits_after", bits)) & 63
				cube.inject(bits)
			"flip":
				bits = int(e.get("bits_after", bits)) & 63
				cube.anchor(bits, anchor)
			"step":
				pass # see the doc comment above: honestly unreplayable alone.


## Empty the journal. Does not touch the cube or `bits` -- a caller wanting a
## clean slate for both calls `reset` too.
func journal_clear() -> void:
	journal.clear()
