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
## The stream as it arrives, concatenated RAW. Tokens carry their own spacing,
## so gluing them with anything of our own would double it or lose it.
var _stream: String = ""


func bind(store: HexyStore, mnn: Mnn) -> void:
	_store = store
	_mnn = mnn
	if _mnn != null and not _mnn.done.is_connected(_on_done):
		_mnn.done.connect(_on_done)
	if _mnn != null and not _mnn.token.is_connected(_on_token):
		_mnn.token.connect(_on_token)
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
##
## TWO FIGURES, NAMED SEPARATELY. The head is the oracle the person threw; the
## body is the one their senses are walking. A prompt that folded them into one
## figure would be describing a moment nobody is in.
func ground(head_desc: Dictionary, body_desc: Dictionary, machine_sentence: String,
		human_sentence: String, last_flip: Dictionary = {}, state_line: String = "") -> String:
	var parts: Array[String] = ([] as Array[String])
	parts.append(SYSTEM_LINE)
	if state_line != "":
		parts.append(state_line)
	parts.append("head " + _figure_line(head_desc))
	parts.append("body " + _figure_line(body_desc))
	parts.append("machine: " + machine_sentence)
	parts.append("human: " + human_sentence)
	parts.append("last line: " + _flip_line(last_flip))
	return "; ".join(parts)


## One figure, in one clause.
static func _figure_line(desc: Dictionary) -> String:
	return "figure %d %s (%s), lower trigram %s, upper %s, becomes %d %s" % [
		int(desc.get("number", 1)),
		String(desc.get("name", "")),
		String(desc.get("pinyin", "")),
		String(desc.get("lower", "")),
		String(desc.get("upper", "")),
		int(desc.get("transformed_number", 1)),
		String(desc.get("transformed_name", "")),
	]


## The line that turned last, in the fire's own words when it has any.
static func _flip_line(last_flip: Dictionary) -> String:
	var reason: String = String(last_flip.get("reason", ""))
	if last_flip.is_empty() or (reason == "" and int(last_flip.get("when", 0)) <= 0):
		return "no line has turned yet"
	if reason != "":
		return reason
	var line: int = clampi(int(last_flip.get("line", 0)), 0, 5)
	var word: String = "turned to yang" if bool(last_flip.get("to_yang", false)) else "turned to yin"
	return "line %d (%s) %s" % [line + 1, Pacing.LINE_NAMES[line], word]


## One short number: no leading zero, no trailing zeros ("0.82" -> ".82",
## "0.00" -> "0"). Keeps the state line short enough for a 0.6B model.
static func _short_num(v: float) -> String:
	var s: String = "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	if s.begins_with("0."):
		s = s.substr(1)
	return s


## One live organism-state line, built from Character.get_fly_state(). Duck
## typed and disposable: no anatomy, no lecture, just the numbers that are
## true right now. rest is GABA (the dFB sleep drive), read as a rest signal
## rather than named after the neuron that carries it.
static func organism_line(fs: Dictionary, posture: String = "") -> String:
	var da: String = _short_num(float(fs.get("dopamine", 0.0)))
	var oa: String = _short_num(float(fs.get("octopamine", 0.0)))
	var rest: String = _short_num(float(fs.get("gaba", 0.0)))
	var heading: String = String(fs.get("dominant_trigram", ""))
	var phase: String = String(fs.get("phase", ""))
	var startle: String = _short_num(float(fs.get("startle", 0.0)))
	var segs: Array[String] = ([] as Array[String])
	segs.append("state DA %s OA %s rest %s" % [da, oa, rest])
	segs.append("heading %s" % heading)
	segs.append("phase %s" % phase)
	segs.append("startle %s" % startle)
	if posture != "":
		segs.append("posture %s" % posture)
	return "[" + " | ".join(segs) + "]"


## The prompt for the two figures currently in the store, plus a question.
func prompt_now(question: String) -> String:
	var head_desc: Dictionary = IChing.describe(0, 0)
	var body_desc: Dictionary = IChing.describe(0, 0)
	var m: String = ""
	var h: String = ""
	var flip: Dictionary = {}
	var state_line: String = ""
	if _store != null:
		head_desc = IChing.describe(
			_store.head_bits(), int(_store.head.get("moving", 0)))
		body_desc = IChing.describe(
			_store.body_bits(), int(_store.body.get("moving", 0)))
		m = String(_store.machine.get("sentence", ""))
		h = String(_store.human.get("sentence", ""))
		flip = _store.last_flip
		var ch: Variant = _store.get_character() if _store.has_method("get_character") else null
		if ch != null and ch.has_method("get_fly_state"):
			state_line = organism_line(ch.get_fly_state())
	var body: String = ground(head_desc, body_desc, m, h, flip, state_line)
	return body + "; question: " + question


# --- asking -----------------------------------------------------------------

## Ask one question about this moment. The answer lands in store.answer.
func ask(question: String) -> Signal:
	_busy = true
	_stream = ""
	var prompt: String = prompt_now(question)
	return _mnn.generate(prompt, max_tokens())


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


func _on_token(t: String) -> void:
	_stream += t


func _on_done(text: String) -> void:
	_busy = false
	var out: String = text.strip_edges()
	if out == "":
		out = _stream.strip_edges()
	if out == "":
		out = Judgements.for_bits(_store.primary() if _store != null else 0)
	out = clip(out)
	if _store != null:
		_store.set_answer(out)
	answer_ready.emit(out)


# --- the shape of an answer -------------------------------------------------

## THE TOKEN BUDGET, from the drawer when there is one. MAX_TOKENS stays the
## default and the fallback, so a Qwen built in a test with no HexyConfig asks
## for exactly the eighty tokens it always did.
func max_tokens() -> int:
	var cfg: HexyConfig = HexyConfig.peek()
	if cfg == null:
		return MAX_TOKENS
	return int(cfg.get_value("qwen.max_tokens"))


## CUT THE ANSWER DOWN TO THE GLASS. A model asked for one or two short
## sentences will sometimes give five, and the bubble is one line wide, so the
## answer is trimmed HERE rather than hoped for in the prompt. Off by default
## of the drawer: with no config, nothing is cut.
func clip(text: String) -> String:
	var cfg: HexyConfig = HexyConfig.peek()
	if cfg == null or not bool(cfg.get_value("qwen.one_line_only")):
		return text
	return first_sentences(text, int(cfg.get_value("qwen.max_sentences")))


## The first `n` sentences of `text`, kept WITH their terminators. A sentence
## ends at . ! ? or the Chinese full stop -- the four marks the model actually
## reaches for -- and a run of them ("?!") ends ONE sentence, not two. Text
## carrying no terminator at all is one sentence and comes back whole, because
## a truncated stream is still the only answer there is.
static func first_sentences(text: String, n: int) -> String:
	if n <= 0:
		return text.strip_edges()
	var src: String = text.strip_edges()
	var count: int = 0
	var i: int = 0
	while i < src.length():
		if _is_terminator(src[i]):
			while i + 1 < src.length() and _is_terminator(src[i + 1]):
				i += 1
			count += 1
			if count >= n:
				return src.substr(0, i + 1).strip_edges()
		i += 1
	return src


static func _is_terminator(c: String) -> bool:
	return c == "." or c == "!" or c == "?" or c == "。"


# --- embedding --------------------------------------------------------------

func embed(text: String) -> PackedFloat32Array:
	return _mnn.embed(text)
