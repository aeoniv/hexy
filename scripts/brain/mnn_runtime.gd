extends RefCounted
class_name MnnRuntime
## The MNN seam. On Android the IxMnn plugin hosts Alibaba MNN; on desktop a
## deterministic mock keeps every caller and test runnable. available() is
## honest: mock results are never presented as real inference.
##
## Models are not in the APK. embed_start()/chat_start() take a directory name
## relative to the app's external files dir (tools/push_mnn_model.ps1 puts them
## there); the mock accepts the same calls and answers from nothing, so desktop
## callers and tests never branch on platform.

## PHASE 10c — THE STREAM. A token exists seconds before the answer does, and
## until this phase nobody was told: `chat()` handed MNN an ostringstream nobody
## read until generation finished. `chat_stream()` is the same turn with the
## same weights and the same prompt; the only difference is that the words come
## out as they are made.
##
## `chat_token` is a CHUNK, not necessarily a word and never a sentence — the
## splitting into things a mouth can say is agent_loop.gd's job, because that is
## where the answer's shape is already known. `chat_done` carries the WHOLE
## reply, and it is emitted on every road out of a stream including a failed
## one, so a caller never has to time out to find out a stream is over.
signal chat_token(text: String)
signal chat_done(text: String)

## Default model directories — the names push_mnn_model.ps1 writes.
const EMBED_MODEL := "gte-embedding-mnn"
const CHAT_MODEL := "qwen3-0.6b-mnn"
const MOCK_DIM := 64
## Qwen3 reasons out loud by default and burns the whole token budget doing it;
## the model's own soft switch turns that off. Model-specific, so it lives next
## to the model name and is only ever appended to a real Qwen3 prompt.
const QWEN_NO_THINK := " /no_think"

var _android: Object = null
var _dim := MOCK_DIM
var _chat_ready := false
var _chat_model := ""
## THE SCRIPTED FAKE MODEL (Phase 8). Replies the mock hands out in order, one
## per `chat()`, and then it is back to the canned echo. It exists so the agent
## loop can be driven through a whole multi-step turn headless, with no weights
## and no phone: the loop calls the same `chat()` a device calls, and the only
## difference is what comes back.
##
## IGNORED ENTIRELY WHEN A PLUGIN IS PRESENT. `chat()` checks `available()`
## first, so a script set by mistake on a phone with real weights changes
## nothing at all - a fake that could shadow a real model would be the one way
## this could ever put a canned line in front of a person.
var _scripted: Array[String] = []


## Phase 10c. True between `chat_stream()` and its `chat_done`. One at a time,
## for the same reason the plugin refuses a second one: MNN's Llm is not
## reentrant and two answers interleaved into one voice is not an answer.
var _streaming := false
## Does the plugin under this seam know how to stream at all? False on a mock
## (which streams by its own road) and false on an APK older than Phase 10c.
var _can_stream := false


func _init() -> void:
	if Engine.has_singleton("IxMnn"):
		_android = Engine.get_singleton("IxMnn")
		# THE PLUGIN'S SIGNALS, FORWARDED AS OUR OWN. Both are guarded on
		# `_streaming`, because two MnnRuntime instances exist on a phone
		# (main.gd's `_mind` and `_agent_mind`) and both are connected to the one
		# singleton — without the guard the idle one would re-emit the busy
		# one's tokens and the loop would hear every word twice.
		# ASKED FOR RATHER THAN ASSUMED. An APK can outlive the plugin it was
		# built against — a phone with the Phase 9 AAR still installed has no
		# such signal, and connecting to one that is not there is an error in
		# the log at every launch rather than a mouth that falls back quietly.
		_can_stream = _android.has_signal("chat_token") \
			and _android.has_signal("chat_done")
		if _can_stream:
			_android.connect("chat_token", _on_plugin_token)
			_android.connect("chat_done", _on_plugin_done)
		else:
			print("mnn: this plugin cannot stream — the mouth waits for whole answers")


func _on_plugin_token(text: String) -> void:
	if _streaming:
		chat_token.emit(text)


func _on_plugin_done(text: String) -> void:
	if not _streaming:
		return
	_streaming = false
	chat_done.emit(text)


## THE STREAMING LOCKOUT, UNDONE. `_streaming` used to have exactly one door
## shut behind it — `_on_plugin_done` — and a turn the watchdog abandoned
## (THINKING outstaying THINK_MS, or the tree going down mid-generation) never
## walks through that door: the plugin's worker is still out there decoding,
## nobody is left waiting on it, and every `chat_stream()` after it returns
## `false` forever because the seam believes itself busy for good.
##
## `cancel()` is the other door. It clears `_streaming` itself, which is all
## `_on_plugin_done`'s own guard needs to treat a chat_done that still arrives
## from the abandoned generation as unwanted rather than as this seam's answer
## — the same one-flag-is-the-generation model `_streaming` already stood for,
## just released from the caller's side instead of the plugin's.
func cancel() -> void:
	if not _streaming:
		return
	print("mnn: stream cancelled — a late chat_done will be ignored")
	_streaming = false


func available() -> bool:
	return _android != null and _android.call("runtime_ready")


func backend_name() -> String:
	return "mnn" if available() else "mock"


## Loads the embedding model. Returns its dimension, 0 if it could not load.
## On the mock this always succeeds and reports MOCK_DIM.
func embed_start(dir: String = EMBED_MODEL) -> int:
	if available():
		_dim = _android.call("embed_start", dir)
		return _dim
	_dim = MOCK_DIM
	return _dim


## Dimension of whatever embed() currently returns.
func embed_dim() -> int:
	return _dim


## Loads the chat model. Slow on device (hundreds of MB of weights).
func chat_start(dir: String = CHAT_MODEL) -> bool:
	_chat_model = dir
	if available():
		_chat_ready = _android.call("chat_start", dir)
		return _chat_ready
	_chat_ready = true
	return true


## THE DIRECTORY THIS SESSION WAS ACTUALLY OPENED ON. Phase 10c: it is no longer
## always [constant CHAT_MODEL] — a phone over the RAM bar with the weights on
## disk gets `qwen3-1.7b-mnn` — and the beacon must advertise what is loaded
## rather than what is usual.
func chat_model() -> String:
	return _chat_model if _chat_model != "" else CHAT_MODEL


func chat_ready() -> bool:
	if available():
		return _android.call("chat_ready")
	return _chat_ready


## Single-turn completion, blocking. "" means no reply.
func chat(prompt: String) -> String:
	if available():
		var p := prompt
		if _chat_model.begins_with("qwen3"):
			p += QWEN_NO_THINK
		return _android.call("chat", p)
	if not _chat_ready:
		return ""
	return _mock_chat(prompt)


## THE SAME TURN, STREAMED. Returns whether a stream actually started; `false`
## is a caller's cue to take the blocking road, and it is returned rather than
## thrown because "this phone cannot stream" is an ordinary Tuesday on desktop.
##
## NEVER BLOCKS. On a phone the plugin submits to its own worker and returns; on
## the mock the chunks are emitted from here, synchronously, which is what makes
## the whole streaming road walkable in a headless suite with no weights.
func chat_stream(prompt: String) -> bool:
	if _streaming:
		return false
	if available():
		if not _can_stream:
			return false
		var p := prompt
		if _chat_model.begins_with("qwen3"):
			p += QWEN_NO_THINK
		_streaming = true
		if bool(_android.call("chat_stream", p)):
			return true
		_streaming = false
		return false
	if not _chat_ready:
		return false
	_streaming = true
	var whole := _mock_chat(prompt)
	for chunk: String in stream_chunks(whole):
		if not _streaming:
			return true
		chat_token.emit(chunk)
	_streaming = false
	chat_done.emit(whole)
	return true


func streaming() -> bool:
	return _streaming


## THE MOCK'S TOKENS, and they are a pure function so a test can pin the shape
## of a stream without owning one. Words, with their trailing space kept on the
## chunk — which is the shape a real tokenizer produces and therefore the shape
## the sentence splitter has to survive.
static func stream_chunks(text: String) -> Array:
	var out: Array = []
	var cur := ""
	for i in text.length():
		var c := text[i]
		cur += c
		if c == " " or c == "\n":
			out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out


func embed(text: String) -> PackedFloat32Array:
	if available():
		return _android.call("embed", text)
	return _mock_embed(text)


## Queues replies for the mock to hand out in order. Test rig only; see
## `_scripted` above for why a plugin makes this a no-op.
func set_scripted(lines: Array) -> void:
	_scripted = []
	for l: Variant in lines:
		_scripted.append(String(l))


func scripted_left() -> int:
	return _scripted.size()


## Canned reply: enough shape for callers to be written and tested, never
## enough to be mistaken for thought.
func _mock_chat(prompt: String) -> String:
	if not _scripted.is_empty():
		return _scripted.pop_front()
	if prompt.strip_edges().is_empty():
		return ""
	return "[mock] heard: " + prompt.strip_edges().left(60)


## Deterministic 64-dim pseudo-embedding: same text, same vector, unit length.
func _mock_embed(text: String) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(MOCK_DIM)
	var h := hash(text)
	var norm := 0.0
	for i in MOCK_DIM:
		h = int((h * 1103515245 + 12345 + i) & 0x7FFFFFFF)
		v[i] = float(h % 2000 - 1000) / 1000.0
		norm += v[i] * v[i]
	norm = sqrt(norm)
	for i in MOCK_DIM:
		v[i] /= norm
	return v


static func cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var dot := 0.0
	for i in mini(a.size(), b.size()):
		dot += a[i] * b[i]
	return dot
