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

var pacing: Pacing = null

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
	if not _store.head_changed.is_connected(_on_head_changed):
		_store.head_changed.connect(_on_head_changed)


func unbind() -> void:
	if _store != null and _store.head_changed.is_connected(_on_head_changed):
		_store.head_changed.disconnect(_on_head_changed)
	_store = null
	_senses = null


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
func inject(bits: int, when: int, source: String = "tap", who: String = "") -> void:
	if _injecting or _store == null:
		return
	_injecting = true
	var b: int = bits & 63
	var w: int = maxi(when, _last_now_ms)
	pacing.inject(b, w)
	_store.set_body({
		"bits": b,
		"moving": 0,
		"throws": [],
		"when": w,
		"who": who,
		"source": source,
		"seq_index": HexyStore.seq_index_of(b, false),
	})
	_injecting = false


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
