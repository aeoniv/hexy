class_name Qwen
extends Node

## The language layer: the figure, the two sentences, and one short answer.
##
## Qwen owns the prompt. It reads the figure from HexyStore, dresses it with
## IChing.describe, hands a short grounded prompt to Mnn, and writes whatever
## comes back into store.answer. It is the only part of core that touches Mnn.

signal thought_started(question: String)
signal answer_ready(text: String)

const SYSTEM_LINE: String = "You are Hexy. Answer in one or two short sentences, plain ASCII."
const THOUGHT_QUESTION: String = "What is this moment?"
const COOLDOWN_MS: int = 3000
const MAX_TOKENS: int = 80
const MAX_NEIGHBOURS: int = 4

var _store: HexyStore = null
var _mnn: Mnn = null
var _names: Dictionary = {}
var _last_thought_ms: int = -COOLDOWN_MS * 2
var _thoughts: int = 0
var _busy: bool = false
## A change that arrived inside the cooldown and has not been spoken for yet.
var _owed: bool = false
## The figure the last thought was actually about, as bits | moving << 6.
var _spoken_key: int = -1


func bind(store: HexyStore, mnn: Mnn) -> void:
	_store = store
	_mnn = mnn
	if _mnn != null and not _mnn.done.is_connected(_on_done):
		_mnn.done.connect(_on_done)
	if _store != null and not _store.hexagram_changed.is_connected(_on_hexagram_changed):
		_store.hexagram_changed.connect(_on_hexagram_changed)


func busy() -> bool:
	return _busy


func thoughts_fired() -> int:
	return _thoughts


# --- naming -----------------------------------------------------------------

## Short label for a figure; cached, since KingWen walks a table each time.
func label(bits: int) -> String:
	var b: int = bits & 63
	if not _names.has(b):
		_names[b] = KingWen.name(b)
	return String(_names[b])


# --- the prompt -------------------------------------------------------------

## Everything the model needs about this moment, in about 120 tokens.
func ground(figure_desc: Dictionary, machine_sentence: String, human_sentence: String,
		neighbourhood: Array[String] = ([] as Array[String])) -> String:
	var near: Array[String] = neighbourhood.duplicate()
	if near.is_empty():
		var raw: Variant = figure_desc.get("neighbors_names", [])
		if raw is Array:
			for n in (raw as Array):
				near.append(String(n))
	var shown: Array[String] = ([] as Array[String])
	for i in range(mini(near.size(), MAX_NEIGHBOURS)):
		shown.append(near[i])
	var line: String = "figure %d %s (%s), lower trigram %s, upper %s, becomes %d %s" % [
		int(figure_desc.get("number", 1)),
		String(figure_desc.get("name", "")),
		String(figure_desc.get("pinyin", "")),
		String(figure_desc.get("lower", "")),
		String(figure_desc.get("upper", "")),
		int(figure_desc.get("transformed_number", 1)),
		String(figure_desc.get("transformed_name", "")),
	]
	var parts: Array[String] = ([] as Array[String])
	parts.append(SYSTEM_LINE)
	parts.append(line)
	if not shown.is_empty():
		parts.append("neighbours: " + ", ".join(shown))
	parts.append("machine: " + machine_sentence)
	parts.append("human: " + human_sentence)
	return "; ".join(parts)


## The prompt for the figure currently in the store, plus a question.
func prompt_now(question: String) -> String:
	var bits: int = _store.primary() if _store != null else 0
	var moving: int = int(_store.hexagram.get("moving", 0)) if _store != null else 0
	var desc: Dictionary = IChing.describe(bits, moving)
	var m: String = String(_store.machine.get("sentence", "")) if _store != null else ""
	var h: String = String(_store.human.get("sentence", "")) if _store != null else ""
	var body: String = ground(desc, m, h)
	return body + "; question: " + question


# --- asking -----------------------------------------------------------------

## Ask one question about this moment. The answer lands in store.answer.
func ask(question: String) -> Signal:
	_busy = true
	var prompt: String = prompt_now(question)
	return _mnn.generate(prompt, MAX_TOKENS)


## Ask "What is this moment?" on the store's own beat, at most once per 3 s.
##
## The cooldown thins the stream; it must not swallow its end. A change that
## arrives too soon is not dropped but OWED: one timer is armed for the rest
## of the cooldown, and when it rings the figure is spoken for -- unless the
## store has meanwhile come back to the figure we already answered, in which
## case there is nothing left to say.
func thought() -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _last_thought_ms < COOLDOWN_MS:
		_owe(COOLDOWN_MS - (now - _last_thought_ms))
		return false
	_speak()
	return true


func _speak() -> void:
	_owed = false
	_last_thought_ms = Time.get_ticks_msec()
	_spoken_key = _figure_key()
	_thoughts += 1
	thought_started.emit(THOUGHT_QUESTION)
	ask(THOUGHT_QUESTION)


## What is on the glass right now, as one comparable number.
func _figure_key() -> int:
	if _store == null:
		return -1
	return (_store.primary() & 63) | ((int(_store.hexagram.get("moving", 0)) & 63) << 6)


## Arm the one trailing thought. A debt already owed is not owed twice: the
## timer already running will read the store as it finds it then, which is by
## definition the latest figure.
func _owe(wait_ms: int) -> void:
	if _owed:
		return
	_owed = true
	if is_inside_tree() and get_tree() != null:
		var wait_s: float = maxf(0.01, float(wait_ms) / 1000.0)
		get_tree().create_timer(wait_s).timeout.connect(_settle)
	else:
		_settle.call_deferred()


func _settle() -> void:
	if not _owed:
		return
	_owed = false
	if _figure_key() == _spoken_key:
		return
	_speak()


func _on_hexagram_changed(_h: Dictionary) -> void:
	thought()


func _on_done(text: String) -> void:
	_busy = false
	var out: String = text.strip_edges()
	if out == "":
		out = Judgements.for_bits(_store.primary() if _store != null else 0)
	if _store != null:
		_store.set_answer(out)
	answer_ready.emit(out)


# --- embedding --------------------------------------------------------------

func embed(text: String) -> PackedFloat32Array:
	return _mnn.embed(text)
