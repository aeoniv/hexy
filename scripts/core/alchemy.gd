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


## A cast at the head lands in the body whole, and the fires go quiet while it
## settles. This is the ONE direction the two figures speak in.
func _on_head_changed(_h: Dictionary) -> void:
	pass
