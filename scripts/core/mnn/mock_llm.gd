class_name MockLlm
extends Node

## The voice the app keeps when there is no model on the device.
##
## Deterministic and offline: it reads the figure out of the prompt (either
## "figure N" or a hexagram glyph), speaks that figure's King Wen judgement
## line, and echoes back the two sentences the senses handed it. Nothing is
## sampled, so the same prompt always gives the same words.

signal token(t: String)
signal done(text: String)

const TOKEN_SECONDS: float = 0.01

## What stands between the judgement, the machine sentence and the human one.
const SEPARATOR: String = " | "

var token_seconds: float = TOKEN_SECONDS

var _queue: PackedStringArray = PackedStringArray()
var _spoken: String = ""
var _timer: Timer = null
var _busy: bool = false


func busy() -> bool:
	return _busy


## The whole reply for a prompt, with no streaming. Pure function of the text.
func reply(prompt: String, max_tokens: int = 80) -> String:
	var bits: int = figure_bits(prompt)
	var parts: Array[String] = ([] as Array[String])
	parts.append(Judgements.for_bits(bits))
	var m: String = _tail(prompt, "machine:")
	var h: String = _tail(prompt, "human:")
	if m != "":
		parts.append(m)
	if h != "":
		parts.append(h)
	var text: String = SEPARATOR.join(parts)
	var words: PackedStringArray = text.split(" ", false)
	if max_tokens > 0 and words.size() > max_tokens:
		var cut: PackedStringArray = PackedStringArray()
		for i in range(max_tokens):
			cut.append(words[i])
		text = " ".join(cut)
	return text


## Say the reply one word at a time, then emit `done` with the whole of it.
func start(prompt: String, max_tokens: int = 80) -> void:
	cancel()
	var text: String = reply(prompt, max_tokens)
	_queue = _tokenize(text)
	_spoken = ""
	_busy = true
	if not is_inside_tree():
		# No frames to ride on yet: say it all next idle, never inside this
		# call, so a caller can still await `done`.
		_flush.call_deferred()
		return
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = false
		add_child(_timer)
		_timer.timeout.connect(_on_tick)
	_timer.wait_time = maxf(0.001, token_seconds)
	_timer.start()


## Cut `text` the way a real tokenizer would: every piece but the first
## carries its own leading space, so a caller that simply concatenates the
## stream gets the sentence back with its spaces intact.
static func _tokenize(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for w in text.split(" ", false):
		out.append(w if out.is_empty() else " " + w)
	return out


func cancel() -> void:
	_busy = false
	_queue = PackedStringArray()
	if _timer != null:
		_timer.stop()


func _on_tick() -> void:
	if not _busy:
		return
	if _queue.is_empty():
		_finish()
		return
	var w: String = _queue[0]
	_queue.remove_at(0)
	_spoken += w
	token.emit(w)
	if _queue.is_empty():
		_finish()


func _flush() -> void:
	for w in _queue:
		_spoken += w
		token.emit(w)
	_queue = PackedStringArray()
	_finish()


func _finish() -> void:
	if _timer != null:
		_timer.stop()
	_busy = false
	done.emit(_spoken)


# --- reading the figure out of a prompt -------------------------------------

## The six bits of the figure named in `prompt`; 0 (Earth) when none is named.
static func figure_bits(prompt: String) -> int:
	var g: int = _glyph_number(prompt)
	if g > 0:
		return KingWen.bits_of(g)
	var n: int = _keyed_number(prompt, "figure")
	if n > 0:
		return KingWen.bits_of(n)
	n = _keyed_number(prompt, "hexagram")
	if n > 0:
		return KingWen.bits_of(n)
	return 0


static func _glyph_number(prompt: String) -> int:
	for c in prompt:
		var code: int = c.unicode_at(0)
		if code >= KingWen.HEXAGRAM_GLYPH_BASE and code < KingWen.HEXAGRAM_GLYPH_BASE + 64:
			return code - KingWen.HEXAGRAM_GLYPH_BASE + 1
	return 0


static func _keyed_number(prompt: String, key: String) -> int:
	var low: String = prompt.to_lower()
	var at: int = low.find(key)
	if at < 0:
		return 0
	var i: int = at + key.length()
	while i < low.length() and not _is_digit(low[i]):
		if low[i] != " " and low[i] != "#":
			return 0
		i += 1
	var digits: String = ""
	while i < low.length() and _is_digit(low[i]):
		digits += low[i]
		i += 1
	if digits == "":
		return 0
	return clampi(int(digits), 1, 64)


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


## Everything after `key` up to the next ";" marker, trimmed.
static func _tail(prompt: String, key: String) -> String:
	var low: String = prompt.to_lower()
	var at: int = low.find(key)
	if at < 0:
		return ""
	var start: int = at + key.length()
	var stop: int = prompt.find(";", start)
	if stop < 0:
		stop = prompt.length()
	return prompt.substr(start, stop - start).strip_edges()
