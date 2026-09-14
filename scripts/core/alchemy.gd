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

## THE CUBE SPEAKS TO QWEN AS LOUDLY AS THE BODY HOLDS STILL. Off by default:
## the prior weight stays whatever a human last set it to, and nothing here
## touches it. Switched on, every beat writes it from the senses.
const PRIOR_FOLLOWS_STILLNESS_DEFAULT: bool = false
## The most the decode loop may ever be leaned on from here, however still the
## body gets. Above this the answer is the cube's and not the model's.
const PRIOR_MAX: float = 0.35

## The keys this node will take from HexyConfig when there is one.
const CFG_FOLLOWS: String = "prior.follows_stillness"
const CFG_MAX: String = "prior.max"

var pacing: Pacing = null
var prior_follows_stillness: bool = PRIOR_FOLLOWS_STILLNESS_DEFAULT
## The live ceiling. Starts at the const and follows HexyConfig when one exists.
var prior_max: float = PRIOR_MAX

var _config: Object = null

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


func _on_config_changed(key: String, _value: Variant) -> void:
	if key == CFG_FOLLOWS or key == CFG_MAX:
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
	if out.is_empty():
		return out
	var bits: int = int(out["bits"]) & 63
	var line: int = int(out["line"])
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
		"to_yang": bool(out["to_yang"]),
		"reason": String(out["reason"]),
		"when": now_ms,
	})
	line_flipped.emit(out)
	return out


## An explicit cast lands in the body whole, re-anchoring pacing and locking out both fires.
## `moving` carries the cast's own changing lines straight through, so the glass never has to
## write the body itself to keep them.
func inject(bits: int, when: int, source: String = "tap", who: String = "",
		moving: int = 0, seq_index: int = -1) -> void:
	if _injecting or _store == null:
		return
	_injecting = true
	var b: int = bits & 63
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
	_publish_pacing_state()
	_injecting = false


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
	var now: int = _last_now_ms if _last_now_ms > 0 else Time.get_ticks_msec()
	pacing.reset(_store.body_bits(), now)
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
	var now: int = _last_now_ms if _last_now_ms > 0 else Time.get_ticks_msec()
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
	}
