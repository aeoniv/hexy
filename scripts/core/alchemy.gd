class_name Alchemy
extends Node

## WHERE THE SENSES TOUCH THE BODY, and the only place they do.
##
## Senses elect two trigrams and say how surely; Pacing pours that into the
## cube and decides which line may turn and when; the store holds the two
## figures. Alchemy is the hinge between the three and owns no
## state of its own beyond the pacing it drives.
##
## THE COUPLING IS ONE WAY. A head cast is injected into the body -- re-anchor,
## zero the strains, and both fires held for Pacing.INJECT_LOCKOUT seconds. The
## body never writes back to the head.

## Announced on every turned line, for a host that wants to buzz or speak.
signal line_flipped(f: Dictionary)

## A LINE'S STANDING PRESSURE MOVED, and no line turned. The dials page draws
## this as a needle leaning; `mark` is the line's whole signed accumulator in
## [-1, 1], not the delta that moved it.
signal mark_moved(line: int, mark: float)

## THE CUBE SPEAKS TO QWEN AS LOUDLY AS THE BODY HOLDS STILL. Off by default:
## the prior weight stays whatever a human last set it to, and nothing here
## touches it. Switched on, every beat writes it from the senses.
const PRIOR_FOLLOWS_STILLNESS_DEFAULT: bool = false
## The most the decode loop may ever be leaned on from here, however still the
## body gets. Above this the answer is the cube's and not the model's.
const PRIOR_MAX: float = 0.35

## EPIGENETIC HYSTERESIS. A body that turned a line the moment a sense said so
## was a body made of the last thing that happened. These three numbers make it
## the thing that KEEPS happening: evidence for a line lands as a signed mark,
## the mark leaks away over a fortnight, and the line only turns once the mark
## has crossed its threshold AND the pressure has come back on enough separate
## DAYS. One loud afternoon is not a body.
##
## Distinct days of same-direction evidence a line needs before it may turn.
##
## ZERO IS THE OLD BODY: no marks, no days, a line turns the beat it is asked
## to -- which is what everything written before this file expects, and what a
## suite that wants it says out loud by putting `alchemy.flip_days` to zero.
const FLIP_DAYS_DEFAULT: int = 3
## How far a mark must lean, in [0, 1], before the days gate is even consulted.
const MARK_THRESHOLD_DEFAULT: float = 0.6
## The leak. A mark left alone falls by 1/e in this many days, so evidence that
## stops being repeated stops counting without ever being deleted.
const MARK_DECAY_DAYS_DEFAULT: float = 14.0

## What one piece of unweighted evidence is worth. Four of them saturate a mark;
## three of them clear MARK_THRESHOLD_DEFAULT, which is the shape the tests
## lean on and the reason the default is not a round half.
const MARK_STEP: float = 0.25

## A cast is a whole figure stated on purpose, so it is worth more than a beat
## of sense -- but it is still only evidence.
const INJECT_WEIGHT: float = 1.0

const MS_PER_DAY: int = 86_400_000
## Under this, a mark is nothing and its run of days is forgotten.
const MARK_EPSILON: float = 0.001

## The keys this node will take from HexyConfig when there is one.
const CFG_FOLLOWS: String = "prior.follows_stillness"
const CFG_MAX: String = "prior.max"
const CFG_FLIP_DAYS: String = "alchemy.flip_days"
const CFG_MARK_THRESHOLD: String = "alchemy.mark_threshold"
const CFG_MARK_DECAY: String = "alchemy.mark_decay_days"

var pacing: Pacing = null
var prior_follows_stillness: bool = PRIOR_FOLLOWS_STILLNESS_DEFAULT
## The live ceiling. Starts at the const and follows HexyConfig when one exists.
var prior_max: float = PRIOR_MAX

## The live hysteresis dials, following HexyConfig when one exists.
var flip_days: int = FLIP_DAYS_DEFAULT
var mark_threshold: float = MARK_THRESHOLD_DEFAULT
var mark_decay_days: float = MARK_DECAY_DAYS_DEFAULT

var _config: Object = null

## THE SIX ACCUMULATORS, one per line, signed: + leans yang, - leans yin. Held
## in memory only -- the store persists figures and cube state, not pressure,
## so a cold start begins with an unmarked body.
var _mark: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Which way each mark's current run leans: +1, -1, or 0 for no run at all.
var _dir: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
## How many DISTINCT days that run has been fed on.
var _days: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
## The day index each run was last fed on, so two beats in one afternoon count
## once. -1 is "never fed".
var _last_day: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1])
## When the marks were last leaked, so decay is paid per elapsed day and not
## per beat.
var _decayed_at_ms: int = 0

var _store: HexyStore = null
var _senses: Senses = null
## A head cast writes the body; the body must not be heard as a head.
var _injecting: bool = false
## The last clock the host handed us, so an injected cast can be locked out
## against the same now the senses are walking on.
var _last_now_ms: int = 0


func _init() -> void:
	pacing = Pacing.new()


func bind(store: HexyStore, senses: Senses) -> void:
	_store = store
	_senses = senses
	if _store == null:
		return
	pacing.reset(_store.body_bits())
	_publish_pacing_state()
	if not _store.head_changed.is_connected(_on_head_changed):
		_store.head_changed.connect(_on_head_changed)
	## THE BODY IS OURS. Said once, out loud, so the store stops writing it and
	## every announcement comes to us instead.
	if _store.has_method("claim_body"):
		_store.claim_body(true)
	## ONE of the two, never both: the general bus when the store has one, the
	## old cast wire when it does not. Both would inject every cast twice.
	if _store.has_signal("seat_landed"):
		if not _store.seat_landed.is_connected(_on_seat_landed):
			_store.seat_landed.connect(_on_seat_landed)
	elif _store.has_signal("cast_landed") and not _store.cast_landed.is_connected(_on_cast_landed):
		_store.cast_landed.connect(_on_cast_landed)
	if _store.has_signal("restored") and not _store.restored.is_connected(_on_restored):
		_store.restored.connect(_on_restored)
	_bind_config()


func unbind() -> void:
	if _store != null and _store.head_changed.is_connected(_on_head_changed):
		_store.head_changed.disconnect(_on_head_changed)
	if _store != null and _store.has_signal("seat_landed") and _store.seat_landed.is_connected(_on_seat_landed):
		_store.seat_landed.disconnect(_on_seat_landed)
	if _store != null and _store.has_signal("cast_landed") and _store.cast_landed.is_connected(_on_cast_landed):
		_store.cast_landed.disconnect(_on_cast_landed)
	if _store != null and _store.has_signal("restored") and _store.restored.is_connected(_on_restored):
		_store.restored.disconnect(_on_restored)
	## THE CLAIM IS NOT GIVEN BACK. A store that has once been told the body is
	## Alchemy's must never quietly start writing it again: an unbound Alchemy
	## means a cast is a reward and no more, not a cast that writes itself.
	_store = null
	_senses = null


# -- the dials a human may turn ----------------------------------------------

## HexyConfig, IF THERE IS ONE. There may not be: this node is older than the
## config and must keep running on its own consts when it stands alone.
func _find_config() -> Object:
	## `peek` on purpose, not `instance`: this node asks whether a config
	## already exists and never conjures one, so a test that wants the consts
	## gets the consts.
	var cfg: Object = HexyConfig.peek()
	if cfg != null and cfg.has_method("get_value"):
		return cfg
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		var n: Node = (loop as SceneTree).root.get_node_or_null("Config")
		if n != null and n.has_method("get_value"):
			return n
	return null


func _bind_config() -> void:
	_config = _find_config()
	if _config == null:
		return
	if _config.has_signal("changed") and not _config.changed.is_connected(_on_config_changed):
		_config.changed.connect(_on_config_changed)
	_read_config()


func _read_config() -> void:
	if _config == null or not _config.has_method("get_value"):
		return
	## An unknown key reads back null, and null is not an answer: the const
	## stands until the config actually has something to say.
	var follows: Variant = _config.get_value(CFG_FOLLOWS)
	if follows != null:
		prior_follows_stillness = bool(follows)
	var ceiling: Variant = _config.get_value(CFG_MAX)
	if ceiling != null:
		prior_max = clampf(float(ceiling), 0.0, 1.0)
	var days: Variant = _config.get_value(CFG_FLIP_DAYS)
	if days != null:
		flip_days = maxi(int(days), 0)
	var thresh: Variant = _config.get_value(CFG_MARK_THRESHOLD)
	if thresh != null:
		mark_threshold = clampf(float(thresh), 0.0, 1.0)
	var decay: Variant = _config.get_value(CFG_MARK_DECAY)
	if decay != null:
		mark_decay_days = maxf(float(decay), 0.0)


func _on_config_changed(key: String, _value: Variant) -> void:
	if key == CFG_FOLLOWS or key == CFG_MAX:
		_read_config()
	elif key == CFG_FLIP_DAYS or key == CFG_MARK_THRESHOLD or key == CFG_MARK_DECAY:
		_read_config()


## One beat, called by the host straight after senses.tick. Returns the pacing
## result: {} when no line turned, else {bits, line, to_yang, reason, kind}.
func tick(now_ms: int) -> Dictionary:
	if _store == null or _senses == null:
		return {}
	_last_now_ms = now_ms
	var out: Dictionary = pacing.tick(
		now_ms,
		_senses.target_bits(),
		_senses.stillness(),
		_senses.excitation(),
		_senses.machine_margin(),
		_senses.human_margin())
	_publish_q6_mass()
	_publish_pacing_state()
	if prior_follows_stillness:
		Q6Core.set_prior_weight(_prior_weight(_senses.stillness(), _tension()))
	_decay_marks(now_ms)
	_publish_pressure()
	if out.is_empty():
		return out
	var line: int = int(out["line"])
	## THE HYSTERESIS GATE. With flip_days at zero this is the body that has
	## always been here: Pacing says turn and the line turns. Above zero the
	## verdict is only evidence, and `nudge` decides whether today is the day.
	if flip_days > 0:
		## `nudge` owns the write and the announcement on this path, so a turned
		## line is reported once and a leaning one is reported as no line at all.
		if not nudge(line, bool(out["to_yang"]), 1.0, now_ms):
			return {}
		out = out.duplicate(true)
		out["bits"] = _store.body_bits()
		out["reason"] = "hysteresis"
		return out
	_commit_flip(
		int(out["bits"]) & 63,
		line,
		bool(out["to_yang"]),
		String(out["reason"]),
		now_ms)
	line_flipped.emit(out)
	return out


## EVIDENCE FOR ONE LINE, and the only door marks come in through.
##
## `weight` scales the mark this lands, so a whole cast may lean harder than a
## beat of sense. Returns true when the evidence actually TURNED the line --
## which needs the mark past `mark_threshold` and the run fed on at least
## `flip_days` distinct days -- and false when it only leaned it.
func nudge(line: int, to_yang: bool, weight: float = 1.0, now_ms: int = -1) -> bool:
	if line < 0 or line > 5 or _store == null:
		return false
	var when: int = Clock.ms_or_ticks(now_ms)
	_last_now_ms = maxi(_last_now_ms, when)
	if flip_days <= 0:
		_commit_flip(_body_after(line, to_yang), line, to_yang, "nudge", when)
		line_flipped.emit({
			"bits": _store.body_bits(),
			"line": line,
			"to_yang": to_yang,
			"reason": "nudge",
			"kind": "nudge",
		})
		return true
	## The leak is paid from the first mark ever banked, not from the first
	## beat: a mark laid down by a cast between two ticks must still age.
	if _decayed_at_ms <= 0:
		_decayed_at_ms = when
	var sign_now: int = 1 if to_yang else -1
	var day: int = int(floor(float(when) / float(MS_PER_DAY)))
	if _dir[line] != sign_now:
		## THE RUN BROKE. Evidence the other way does not merely subtract from
		## the mark, it starts a new run: a day of yin pressure is not half a
		## day of yang pressure.
		_dir[line] = sign_now
		_days[line] = 1
		_last_day[line] = day
	elif day != _last_day[line]:
		_days[line] += 1
		_last_day[line] = day
	elif _days[line] <= 0:
		_days[line] = 1
		_last_day[line] = day
	_mark[line] = clampf(
		_mark[line] + float(sign_now) * MARK_STEP * absf(weight), -1.0, 1.0)
	if absf(_mark[line]) + 1e-6 < mark_threshold or _days[line] < flip_days:
		_publish_pressure()
		mark_moved.emit(line, _mark[line])
		return false
	## THE LINE TURNS, and the pressure that turned it is SPENT: a flipped line
	## starts again from nothing, so a body cannot ratchet twice on one week of
	## evidence.
	_clear_mark(line)
	_commit_flip(_body_after(line, to_yang), line, to_yang, "hysteresis", when)
	line_flipped.emit({
		"bits": _store.body_bits(),
		"line": line,
		"to_yang": to_yang,
		"reason": "hysteresis",
		"kind": "hysteresis",
	})
	_publish_pressure()
	mark_moved.emit(line, _mark[line])
	return true


## The body with one line forced the way the evidence points.
func _body_after(line: int, to_yang: bool) -> int:
	var bits: int = _store.body_bits() if _store != null else 0
	if to_yang:
		return (bits | (1 << line)) & 63
	return (bits & ~(1 << line)) & 63


## Forget one line's standing pressure entirely.
func _clear_mark(line: int) -> void:
	_mark[line] = 0.0
	_dir[line] = 0
	_days[line] = 0
	_last_day[line] = -1


## THE LEAK. Every mark falls toward zero with a time constant in DAYS, paid
## against the wall the host hands us rather than per beat, so a phone that was
## asleep for a week wakes with a week of forgetting already done.
func _decay_marks(now_ms: int) -> void:
	if _decayed_at_ms <= 0:
		_decayed_at_ms = now_ms
		return
	var elapsed_ms: int = now_ms - _decayed_at_ms
	if elapsed_ms <= 0:
		return
	_decayed_at_ms = now_ms
	if mark_decay_days <= 0.0:
		return
	var days: float = float(elapsed_ms) / float(MS_PER_DAY)
	var keep: float = exp(-days / mark_decay_days)
	for i in range(6):
		if is_zero_approx(_mark[i]):
			continue
		_mark[i] *= keep
		if absf(_mark[i]) < MARK_EPSILON:
			## A mark that has leaked away takes its run of days with it.
			## Otherwise a body could bank three days in March and spend them
			## in June, which is the exact thing this whole file refuses.
			_clear_mark(i)
		mark_moved.emit(i, _mark[i])


## THE ONE WRITE. Whatever turned a line -- pacing on the old path, a mark that
## crossed on the new one -- the body and the flip record are written here and
## nowhere else.
func _commit_flip(bits: int, line: int, to_yang: bool, reason: String, now_ms: int) -> void:
	if _store == null:
		return
	_store.set_body({
		"bits": bits,
		"moving": 1 << line,
		"when": now_ms,
		"who": "",
		"source": "senses",
		"seq_index": HexyStore.seq_index_of(bits, false),
	})
	_store.set_last_flip({
		"line": line,
		"to_yang": to_yang,
		"reason": reason,
		"when": now_ms,
	})


## An explicit cast lands in the body whole, re-anchoring pacing and locking out both fires.
## `moving` carries the cast's own changing lines straight through, so the glass never has to
## write the body itself to keep them.
func inject(bits: int, when: int, source: String = "tap", who: String = "",
		moving: int = 0, seq_index: int = -1) -> void:
	if _injecting or _store == null:
		return
	_injecting = true
	var b: int = bits & 63
	var before: int = _store.body_bits()
	var w: int = maxi(when, _last_now_ms)
	pacing.inject(b, w)
	## WHY the body moved is ours to say, not Pacing's: `inject` writes the
	## entry, we stamp the reason onto it, so a wheel walk does not read back
	## from the journal as a tap.
	if not pacing.journal.is_empty():
		pacing.journal[pacing.journal.size() - 1]["source"] = source
	_store.set_body({
		"bits": b,
		"moving": moving & 63,
		"throws": [],
		"when": w,
		"who": who,
		"source": source,
		"seq_index": seq_index if seq_index >= 0 else HexyStore.seq_index_of(b, false),
	})
	_mark_cast(b, before, w)
	_publish_pacing_state()
	_injecting = false


## WHAT A CAST DOES TO THE PRESSURE. The figure itself lands whole -- a cast has
## always been a statement, not an argument -- but it is also the loudest
## evidence this body ever gets, so it is written into the marks too:
##
##   a line the cast MOVED has its pressure spent, exactly as a flip does;
##   a line the cast merely AGREED with banks a day of evidence for staying,
##   so a figure a person keeps casting becomes a figure that resists a beat
##   of sense the other way.
func _mark_cast(bits: int, before: int, when: int) -> void:
	if flip_days <= 0:
		return
	if _decayed_at_ms <= 0:
		_decayed_at_ms = when
	for line in range(6):
		var to_yang: bool = (bits >> line) & 1 == 1
		if ((before >> line) & 1) != int(to_yang):
			_clear_mark(line)
			continue
		var sign_now: int = 1 if to_yang else -1
		var day: int = int(floor(float(when) / float(MS_PER_DAY)))
		if _dir[line] != sign_now:
			_dir[line] = sign_now
			_days[line] = 1
			_last_day[line] = day
		elif day != _last_day[line]:
			_days[line] += 1
			_last_day[line] = day
		_mark[line] = clampf(
			_mark[line] + float(sign_now) * MARK_STEP * INJECT_WEIGHT, -1.0, 1.0)
		mark_moved.emit(line, _mark[line])


## HOW LOUDLY THE CUBE MAY SPEAK, given a body and the cube's own spread.
##
## The cube speaks to Qwen as loudly as the body holds still; a uniform cube --
## tension 1, mass smeared evenly over all 64 corners -- has nothing to say, so
## it says nothing however still the body is. Zero at either end, PRIOR_MAX at
## the far corner of both, linear between, and clamped on both inputs.
##
## THERE IS EXACTLY ONE WRITER OF THE PRIOR, and it is this. Mesh peers must
## never become a second one: a remote body's stillness is not this body's, and
## two writers racing on a static would make the weight a function of packet
## order rather than of anything anybody felt. A peer's cube may only ever
## enter as a bias term inside Pacing._diffuse, where it moves mass and is
## argued with by the local senses like any other pull.
static func prior_weight_for(stillness: float, tension: float) -> float:
	return PRIOR_MAX * clampf(stillness, 0.0, 1.0) * (1.0 - clampf(tension, 0.0, 1.0))


## The same curve under this node's own live ceiling, which a human may have
## lowered through HexyConfig. Same shape, same zeroes, only the height moves.
func _prior_weight(stillness: float, tension: float) -> float:
	var unit: float = prior_weight_for(stillness, tension) / PRIOR_MAX
	return prior_max * unit


## The cube's spread as of the last journal entry, so a beat does not pay for a
## second JNI round trip to ask the native cube what it just told us. Falls
## back to asking the cube directly when the journal is empty.
func _tension() -> float:
	if pacing == null:
		return 1.0
	if not pacing.journal.is_empty():
		var last: Dictionary = pacing.journal[pacing.journal.size() - 1]
		if last.has("tension"):
			return float(last["tension"])
	return float(pacing.cube.tension())


## PUBLISH ONLY. The 64-corner mass goes out to the store so Wmn can put it on
## the wire; nothing ever comes back in through this seam. Pacing stays the one
## and only writer of cube mass.
func _publish_q6_mass() -> void:
	if _store == null or pacing == null or not _store.has_method("set_q6_mass"):
		return
	_store.set_q6_mass(pacing.cube.state())


## PUBLISH ONLY. The cube's anchor and its newest journal line go to the store
## so `dump` can carry them and a restore can put the body back on the same
## corner it left. Nothing ever comes back in through this seam.
func _publish_pacing_state() -> void:
	if _store == null or pacing == null or not _store.has_method("set_pacing_state"):
		return
	var tail: Dictionary = {}
	if not pacing.journal.is_empty():
		tail = (pacing.journal[pacing.journal.size() - 1] as Dictionary).duplicate(true)
	_store.set_pacing_state(int(pacing.bits), tail)


## A FIGURE LANDED IN A SEAT. Only the BODY is ours: the head is free and the
## earth is the altar, and neither may touch the cube.
func _on_seat_landed(seat: int, c: Dictionary) -> void:
	if seat != HexyStore.Seat.BODY:
		return
	_on_cast_landed(c)


## THE WHOLE STATE CAME BACK. A restored body is not a body that walked there,
## so the cube is re-anchored on it whole rather than left on the corner it
## held before the dump was poured in.
func _on_restored() -> void:
	if _store == null or pacing == null:
		return
	var now: int = _last_now_ms if _last_now_ms > 0 else Clock.now_ms()
	pacing.reset(_store.body_bits(), now)
	## A FIGURE PUT BACK IS NOT A FIGURE THAT WAS ARGUED FOR. The marks belonged
	## to the body that was here a moment ago; they say nothing about this one
	## -- UNLESS the dump that put it back carried the marks too, in which case
	## they are the same body's own pressure coming home and clearing them
	## would throw away days of evidence the person actually lived.
	var carried: Dictionary = {}
	if _store.has_method("alchemy_state"):
		carried = _store.alchemy_state() as Dictionary
	if carried.is_empty():
		for i in range(6):
			_clear_mark(i)
		_decayed_at_ms = now
	else:
		restore(carried)
	if not pacing.journal.is_empty():
		pacing.journal[pacing.journal.size() - 1]["source"] = "restore"
	_publish_pacing_state()
	## A restore makes a warm chat stale for the same reason a cast does: the
	## figure the decode loop was leaning on is not the one we stand on now.
	Q6Core.bump_cast_version()


## A CAST THE GLASS ANNOUNCED. The glass owns the gesture; the body is ours to
## write, so it comes through inject and pacing re-anchors on it.
func _on_cast_landed(c: Dictionary) -> void:
	## A CAST MAKES A WARM CHAT STALE. The figure the decode loop was leaning
	## on is not the figure the body is standing on any more, so the stamp
	## moves even though no figure word was pushed.
	Q6Core.bump_cast_version()
	inject(
		int(c.get("bits", 0)) & 63,
		int(c.get("when", 0)),
		String(c.get("source", "tap")),
		String(c.get("who", "")),
		int(c.get("moving", 0)) & 63,
		int(c["seq_index"]) if c.has("seq_index") else -1)


## Decoupled: head dial tracks human breath and intention; it no longer overwrites the body.
func _on_head_changed(_h: Dictionary) -> void:
	pass


## WHAT THE TWO FIRES ARE DOING, as one small read-only dictionary.
##
## The glass wants to draw the civil dwell as an arc and the martial
## refractory as a countdown, and it must not reach into Pacing's privates to
## do it. Everything here is read; nothing is changed.
##
## The needed dwell follows the DEVICE: a fold held open in flex gets the
## longer breath its profile asks for (civil_fire_flex_multiplier), which is
## the 2.5 s slab breath doubled to 5 s.
func state() -> Dictionary:
	var profile: Dictionary = DeviceProfile.resolve()
	var flex: bool = bool(profile.get("has_hinge", false)) and bool(profile.get("is_dual_pane", false))
	var mult: float = float(profile.get("civil_fire_flex_multiplier", 1.0)) if flex else 1.0
	var now: int = _last_now_ms if _last_now_ms > 0 else Clock.now_ms()
	var flip: Dictionary = _store.last_flip if _store != null else {}
	return {
		"dwell_s": float(pacing.dwell()) if pacing != null else 0.0,
		"dwell_needed_s": Pacing.CIVIL_FIRE_THRESHOLD * mult,
		"refractory_s": float(pacing.refractory_s(now)) if pacing != null else 0.0,
		"refractory_needed_s": Pacing.MUTATION_COOLDOWN,
		"last_reason": String(flip.get("reason", "")),
		"last_line": int(flip.get("line", 0)),
		"flex": flex,
		"bits": int(pacing.bits) if pacing != null else 0,
		## THE PRESSURE, BEFORE IT IS A FLIP. Six signed marks in [-1, 1] and the
		## six runs of days feeding them, so the dials page can draw a line
		## leaning long before it turns.
		"marks": marks(),
		"days_toward": days_toward(),
		"flip_days": flip_days,
		"mark_threshold": mark_threshold,
	}


## THE PRESSURE, AS A DICTIONARY THAT SURVIVES A COLD START.
##
## [method state] is a readout for a glass and carries device facts and pacing
## alongside the marks; this is the narrower thing a store persists -- the six
## accumulators, the direction and day-count of each run, and when the leak was
## last paid -- and nothing that can be recomputed.
func pressure_dict() -> Dictionary:
	return {
		"mark": marks(),
		"dir": _int_array(_dir),
		"days": _int_array(_days),
		"last_day": _int_array(_last_day),
		"decayed_at_ms": _decayed_at_ms,
	}


static func _int_array(p: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	for v in p:
		out.append(int(v))
	return out


## THE INVERSE. A fresh Alchemy handed the dictionary its predecessor left
## stands on the same six marks, with the same runs of days behind them, so
## three days of evidence banked before a restart are still three days after
## it. An empty or short dictionary leaves the marks where they are rather
## than zeroing them, so a caller with nothing saved loses nothing.
func restore(state: Dictionary) -> void:
	if state.is_empty():
		return
	var mark: Array = state.get("mark", [])
	var dir: Array = state.get("dir", [])
	var days: Array = state.get("days", [])
	var last_day: Array = state.get("last_day", [])
	for i in range(6):
		if i < mark.size():
			_mark[i] = clampf(float(mark[i]), -1.0, 1.0)
		if i < dir.size():
			_dir[i] = clampi(int(dir[i]), -1, 1)
		if i < days.size():
			_days[i] = maxi(0, int(days[i]))
		if i < last_day.size():
			_last_day[i] = int(last_day[i])
	_decayed_at_ms = int(state.get("decayed_at_ms", _decayed_at_ms))
	for i in range(6):
		mark_moved.emit(i, _mark[i])


## THE MARKS, HANDED TO THE ONE THING THAT OUTLIVES THE RUN. Publish only: the
## store keeps the dictionary and dumps it; it never reads a mark back on its
## own.
func _publish_pressure() -> void:
	if _store != null and _store.has_method("set_alchemy_state"):
		_store.set_alchemy_state(pressure_dict())


## The six standing marks, copied, signed, + for yang.
func marks() -> Array[float]:
	var out: Array[float] = []
	for i in range(6):
		out.append(float(_mark[i]))
	return out


## How many distinct days each line's current run has been fed on. Zero where
## there is no run.
func days_toward() -> Array[int]:
	var out: Array[int] = []
	for i in range(6):
		out.append(int(_days[i]))
	return out
