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
signal chat_thought(text: String)
signal chat_done(text: String)

## Default model directories — the names the adb sideload writes.
const EMBED_MODEL := "gte-embedding-mnn"
const CHAT_MODEL := "qwen3-0.6b-mnn"

## Supported model families
const MODEL_QWEN3_0_6B := "qwen3-0.6b-mnn"
const MODEL_QWEN3_1_7B := "qwen3-1.7b-mnn"
const MODEL_QWEN2_5_1_5B := "qwen2.5-1.5b-mnn"
const MODEL_QWEN2_5_3B := "qwen2.5-3b-mnn"
## PHASE 11c — THE 0.8B. `taobao-mnn/Qwen3.5-0.8B-MNN`, ~548 MB pushed, and it
## is ONE DIRECTORY THAT IS ALSO EYES: `visual.mnn` rides beside `llm.mnn`, so
## the pack that answers is the pack that looks. MNN 3.6.1 already runs it —
## hybrid attention landed in 3.4.1 — so nothing under `libs/mnn-jni` moves.
const MODEL_QWEN3_5_0_8B := "qwen3.5-0.8b-mnn"

## EVERY DIRECTORY THIS SEAM WILL OPEN. `chat_start` does not refuse a name that
## is not here — the loader's answer is the only truth about what is on disk —
## but a name off this list is a typo until somebody adds it, and the smoke
## walks this list rather than keeping a second copy of it.
const CHAT_MODELS := [
	MODEL_QWEN3_0_6B,
	MODEL_QWEN3_1_7B,
	MODEL_QWEN3_5_0_8B,
	MODEL_QWEN2_5_1_5B,
	MODEL_QWEN2_5_3B,
]

## THE KNOB, AND IT IS ONE STRING. Set it and a `chat_start()` with no argument
## opens that directory instead of [constant CHAT_MODEL]; unset, nothing about a
## 0.6B phone changes. Callers that already name a directory (main.gd asks
## [ModelStore.chat_model_name]) are untouched — an explicit name always wins.
const ENV_CHAT_MODEL := "HEXY_CHAT_MODEL"

const MOCK_DIM := 64
## Qwen3 reasons out loud by default and burns the whole token budget doing it;
## the model's own soft switch turns that off. Model-specific, so it lives next
## to the model name and is only ever appended to a real Qwen3 prompt.
##
## QWEN3.5 HAS NO SUCH SWITCH. It decides by `jinja.context.enable_thinking` in
## its own `llm_config.json` (shipped `true`, and that file is the place to turn
## it off) and otherwise by emitting the `<think>` tags this seam already
## separates. A literal " /no_think" is not a command there, it is a sentence
## the model reads. `begins_with("qwen3")` would have caught `qwen3.5-*` too;
## [method _wants_no_think] is the fence.
const QWEN_NO_THINK := " /no_think"

var _android: Object = null
var _hex_prior_bits: int = -1
var _hex_prior_beta: float = 0.0
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
		if _android.has_signal("chat_thought"):
			_android.connect("chat_thought", _on_plugin_thought)
			_android.connect("chat_done", _on_plugin_done)
		else:
			print("mnn: this plugin cannot stream — the mouth waits for whole answers")


func _on_plugin_thought(text: String) -> void:
	if _streaming:
		chat_thought.emit(text)

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


## THE PROMPT SWITCH, FENCED BY FAMILY. True only for the Qwen3 line, which is
## the only line that reads `/no_think` as a command rather than as words. The
## dash is what does the work: "qwen3-" excludes "qwen3.5-0.8b-mnn".
static func _wants_no_think(dir: String) -> bool:
	return dir.begins_with("qwen3-")


## Loads the chat model. Slow on device (hundreds of MB of weights).
##
## An empty `dir` means "whatever [constant ENV_CHAT_MODEL] says, else the usual
## one", so a phone can be pointed at another pack without a rebuild.
func chat_start(dir: String = "") -> bool:
	if dir == "":
		dir = OS.get_environment(ENV_CHAT_MODEL).strip_edges()
	if dir == "":
		dir = CHAT_MODEL
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
		if _wants_no_think(_chat_model):
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
		if _wants_no_think(_chat_model):
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
	var part := partition_think(whole)
	if part["thought"] != "":
		for chunk: String in stream_chunks(String(part["thought"])):
			if not _streaming:
				return true
			chat_thought.emit(chunk)
	for chunk: String in stream_chunks(String(part["speech"])):
		# A cancel() mid-stream is honoured on the mock too, or the two roads
		# would disagree about what cancelling means.
		if not _streaming:
			return true
		chat_token.emit(chunk)
	_streaming = false
	chat_done.emit(String(part["speech"]))
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

## Sets active I-Ching hexagram prior on the Q6 hypercube (0..63).
func set_hex_prior(hex_bits: int, beta: float = 1.0) -> bool:
	if hex_bits < 0 or hex_bits > 63:
		return false
	_hex_prior_bits = hex_bits
	_hex_prior_beta = maxf(0.0, beta)
	if available() and _android.has_method("set_hex_prior"):
		return bool(_android.call("set_hex_prior", hex_bits, beta))
	return true


func get_hex_prior() -> Dictionary:
	return {
		"hex_bits": _hex_prior_bits,
		"beta": _hex_prior_beta
	}


## Partitions text into reasoning thoughts (<think>...</think>) and speech.
static func partition_think(text: String) -> Dictionary:
	var open_tag := "<think>"
	var close_tag := "</think>"
	var b := text.find(open_tag)
	var e := text.find(close_tag)
	if b == -1:
		return {"thought": "", "speech": text.strip_edges()}
	if e == -1 or e < b:
		var thought_part := text.substr(b + open_tag.length()).strip_edges()
		var speech_part := text.substr(0, b).strip_edges()
		return {"thought": thought_part, "speech": speech_part}
	var thought_part := text.substr(b + open_tag.length(), e - (b + open_tag.length())).strip_edges()
	var speech_part := (text.substr(0, b) + text.substr(e + close_tag.length())).strip_edges()
	return {"thought": thought_part, "speech": speech_part}


## In-place Fast Walsh-Hadamard Transform (FWHT) over 64 elements.
## O(N log N) = 384 additions, 0 multiplications.
static func fwht_64(a: PackedFloat32Array) -> PackedFloat32Array:
	assert(a.size() == 64, "fwht_64 requires exactly 64 elements")
	var out := a.duplicate()
	var h := 1
	while h < 64:
		var step := h << 1
		var i := 0
		while i < 64:
			for j in range(i, i + h):
				var x: float = out[j]
				var y: float = out[j + h]
				out[j] = x + y
				out[j + h] = x - y
			i += step
		h <<= 1
	return out


## In-place Inverse Fast Walsh-Hadamard Transform (IFWHT): IFWHT(x) = (1/64) * FWHT(x).
static func ifwht_64(a: PackedFloat32Array) -> PackedFloat32Array:
	var out := fwht_64(a)
	for i in 64:
		out[i] /= 64.0
	return out


## Low-pass spectral filter on the Q6 hypercube Cayley graph.
static func q6_spectral_filter(prob_64: PackedFloat32Array, max_cutoff: int = 3) -> PackedFloat32Array:
	assert(prob_64.size() == 64, "q6_spectral_filter requires 64 elements")
	var spectral := fwht_64(prob_64)
	for i in 64:
		var w := 0
		var tmp := i
		while tmp > 0:
			w += (tmp & 1)
			tmp >>= 1
		var weight := 1.0 if (w <= max_cutoff) else 0.0
		spectral[i] *= (weight / 64.0)
	return fwht_64(spectral)


## Hamming distance between two 6-bit states
static func hamming_distance(a: int, b: int) -> int:
	var diff := (a ^ b) & 0x3F
	var d := 0
	while diff > 0:
		d += (diff & 1)
		diff >>= 1
	return d


## Pangtong (旁通) operator: Inverts all 6 lines (antipodal vertex ~x)
static func pangtong_invert(bits: int) -> int:
	return (~bits) & 0x3F


## Huguaci (互卦) Nuclear Core projection:
## Lower nuclear trigram = lines 1, 2, 3 (0-indexed)
## Upper nuclear trigram = lines 2, 3, 4 (0-indexed)
static func nuclear_core(bits: int) -> int:
	var lower := (bits >> 1) & 0x07
	var upper := (bits >> 2) & 0x07
	return (lower | (upper << 3)) & 0x3F


## Returns the 6 adjacent Hamming-1 neighbor states
static func hamming_neighbors(bits: int) -> PackedInt32Array:
	var neighbors := PackedInt32Array()
	neighbors.resize(6)
	for i in 6:
		neighbors[i] = (bits ^ (1 << i)) & 0x3F
	return neighbors


# =============================================================================
# TIER-2: CELLULAR SHEAF LAPLACIAN OVER Delta_2(Q6)
# =============================================================================

## Orthogonal restriction map F_{v <= e}: R^6 -> R^2
## Projects line k and its harmonic trigram partner (k+3)%6 with SO(2) rotation
static func sheaf_restrict(v: int, line_k: int, state_6d: PackedFloat32Array) -> Vector2:
	var k := line_k % 6
	var k_partner := (k + 3) % 6
	var x1 := state_6d[k] if k < state_6d.size() else 0.5
	var x2 := state_6d[k_partner] if k_partner < state_6d.size() else 0.5
	var theta := (PI / 3.0) * float(k)
	if ((v >> k) & 1) != 0:
		theta = -theta
	var c := cos(theta)
	var s := sin(theta)
	return Vector2(c * x1 - s * x2, s * x1 + c * x2)


## Local Sheaf Dirichlet Energy (Cognitive Dissonance / Disagreement)
## E_u(x) = sum_{k=0..5} || F_{v_k <= e_k} x_{v_k} - F_{u <= e_k} x_u ||^2
static func sheaf_local_energy(u: int, state_6d: PackedFloat32Array) -> float:
	var energy := 0.0
	for k in range(6):
		var v := (u ^ (1 << k)) & 0x3F
		var x_v := state_6d.duplicate()
		if k < x_v.size():
			x_v[k] = 1.0 - x_v[k]
		var r_u := sheaf_restrict(u, k, state_6d)
		var r_v := sheaf_restrict(v, k, x_v)
		var diff := r_v - r_u
		energy += diff.length_squared()
	return energy


## Single-step Sheaf Laplacian diffusion: x_u <- x_u - alpha * (L_F x)_u
## Regularizes continuous vitality trajectory while preventing oversmoothing
static func sheaf_diffuse_step(u: int, state_6d: PackedFloat32Array, alpha: float = 0.1) -> PackedFloat32Array:
	var grad := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for k in range(6):
		var v := (u ^ (1 << k)) & 0x3F
		var x_v := state_6d.duplicate()
		if k < x_v.size():
			x_v[k] = 1.0 - x_v[k]
		var r_u := sheaf_restrict(u, k, state_6d)
		var r_v := sheaf_restrict(v, k, x_v)
		var diff := r_v - r_u
		var k_partner := (k + 3) % 6
		var theta := (PI / 3.0) * float(k)
		if ((u >> k) & 1) != 0:
			theta = -theta
		var c := cos(theta)
		var s := sin(theta)
		grad[k] += (c * diff.x + s * diff.y)
		grad[k_partner] += (-s * diff.x + c * diff.y)

	var res := PackedFloat32Array()
	res.resize(6)
	for i in range(6):
		var val := state_6d[i] if i < state_6d.size() else 0.5
		res[i] = clampf(val + alpha * grad[i], 0.0, 1.0)
	return res


## Sheaf resonance metric between two hexagram states in [0.0, 1.0]
static func sheaf_resonance(a: int, b: int) -> float:
	var d := hamming_distance(a, b)
	var trigram_align := 1.0 if ((a ^ b) & 0b001001) == 0 else 0.7
	return clampf((1.0 - float(d) / 6.0) * trigram_align, 0.0, 1.0)

# =============================================================================
# TIER-3: E8 LIE GROUP EMBEDDING & E7 SYMPLECTIC SUBALGEBRA
# =============================================================================

## Embeds 6-bit hexagram state into an 8D root of the E8 Lie algebra.
## All roots have squared length 2.0 (norm sqrt(2)) and even coordinate sum.
## Total roots across both chiralities: 64 * 2 = 128 half-integer spinor roots of E8.
static func e8_root_embedding(hex_bits: int, yin_chiral: bool = false) -> PackedFloat32Array:
	var coords := PackedFloat32Array()
	coords.resize(8)
	var b := hex_bits & 0x3F
	var wt := 0
	var tmp := b
	while tmp > 0:
		wt += (tmp & 1)
		tmp >>= 1

	for i in range(6):
		coords[i] = -0.5 if (((b >> i) & 1) != 0) else 0.5

	if (wt % 2) != 0:
		# 3 - wt is even -> x6 + x7 must be 0
		coords[6] = -0.5 if yin_chiral else 0.5
		coords[7] = 0.5 if yin_chiral else -0.5
	else:
		# 3 - wt is odd -> x6 + x7 must be +/- 1
		coords[6] = -0.5 if yin_chiral else 0.5
		coords[7] = -0.5 if yin_chiral else 0.5

	return coords


## Inner product between two 8D E8 root vectors in R^8
static func e8_inner_product(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	assert(a.size() == 8 and b.size() == 8, "e8_inner_product requires 8D vectors")
	var sum := 0.0
	for i in range(8):
		sum += a[i] * b[i]
	return sum


## Tests whether a hexagram is one of the 8 pure doubled trigrams (Cartan diagonal)
static func is_pure_cartan_hexagram(hex_bits: int) -> bool:
	var lower := hex_bits & 0x07
	var upper := (hex_bits >> 3) & 0x07
	return lower == upper


## Chong Gua Transposition (swaps upper and lower trigrams)
static func chong_gua_transpose(hex_bits: int) -> int:
	var lower := hex_bits & 0x07
	var upper := (hex_bits >> 3) & 0x07
	return (lower << 3) | upper


## E7 Symplectic bilinear form Omega(a, b) on the 56 composite hexagrams
## Skew-symmetric: Omega(a, b) = -Omega(b, a), non-zero on Chong Gua conjugate pairs
static func e7_symplectic_form(a: int, b: int) -> float:
	a &= 0x3F
	b &= 0x3F
	if is_pure_cartan_hexagram(a) or is_pure_cartan_hexagram(b):
		return 0.0
	if b != chong_gua_transpose(a):
		return 0.0
	var lower := a & 0x07
	var upper := (a >> 3) & 0x07
	return 1.0 if (lower > upper) else -1.0


## E8 Harmonic Attention Kernel between two hexagrams: K(a, b) = exp(beta * <r_a, r_b>)
static func e8_harmonic_kernel(a: int, b: int, beta: float = 1.0) -> float:
	var r_a := e8_root_embedding(a, false)
	var r_b := e8_root_embedding(b, false)
	return exp(beta * e8_inner_product(r_a, r_b))



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


# ── MNN ENGINE EXTENSIONS: TOKENIZER, SAMPLING, PERF & CONTEXT ──────────────
var _can_cancel := false
var _can_tokenize := false
var _can_perf := false

var _sampling_params := {
	"temperature": 0.7,
	"top_p": 0.9,
	"repetition_penalty": 1.15
}

var _mock_history_count := 0
var _mock_vocab: Dictionary = {}
var _mock_inv_vocab: Dictionary = {}
var _last_perf: Dictionary = {
	"prompt_len": 0,
	"gen_seq_len": 0,
	"all_seq_len": 0,
	"prefill_ms": 0.0,
	"decode_ms": 0.0,
	"tps": 0.0,
	"status": 0
}


## Encodes a prompt string into model token IDs.
func tokenize(text: String) -> PackedInt32Array:
	if available() and _can_tokenize:
		var arr: Array = _android.call("tokenize", text)
		var out := PackedInt32Array()
		out.resize(arr.size())
		for i in arr.size():
			out[i] = int(arr[i])
		return out
	var out := PackedInt32Array()
	var words := text.split(" ", false)
	for w in words:
		var lower := w.to_lower().strip_edges()
		if not _mock_vocab.has(lower):
			var new_id := 1000 + int(_mock_vocab.size())
			_mock_vocab[lower] = new_id
			_mock_inv_vocab[new_id] = lower
		out.append(_mock_vocab[lower])
	return out


## Decodes a single token ID back into text.
func detokenize(token_id: int) -> String:
	if available() and _android.has_method("detokenize"):
		return String(_android.call("detokenize", token_id))
	if _mock_inv_vocab.has(token_id):
		return String(_mock_inv_vocab[token_id]) + " "
	return "[tok_" + str(token_id) + "] "


## Retrieves native C++ execution telemetry (prefill, decode latency, TPS, tokens).
func get_perf() -> Dictionary:
	if available() and _can_perf:
		var raw_json: String = String(_android.call("get_perf"))
		var parsed = JSON.parse_string(raw_json)
		if parsed is Dictionary:
			var d: Dictionary = parsed
			var p_us: float = float(d.get("prefill_us", 0))
			var d_us: float = float(d.get("decode_us", 0))
			var gen_len: int = int(d.get("gen_seq_len", 0))
			var tps: float = 0.0
			if d_us > 0.0 and gen_len > 0:
				tps = (float(gen_len) * 1000000.0) / d_us
			return {
				"prompt_len": int(d.get("prompt_len", 0)),
				"gen_seq_len": gen_len,
				"all_seq_len": int(d.get("all_seq_len", 0)),
				"prefill_ms": p_us / 1000.0,
				"decode_ms": d_us / 1000.0,
				"tps": snappedf(tps, 0.1),
				"status": int(d.get("status", 0))
			}
	return _last_perf.duplicate()


## Dynamically sets runtime sampling parameters (Temperature, Top-P, Repetition Penalty).
func set_sampling(temperature: float, top_p: float = 0.9, repetition_penalty: float = 1.15) -> bool:
	_sampling_params["temperature"] = clampf(temperature, 0.05, 2.0)
	_sampling_params["top_p"] = clampf(top_p, 0.1, 1.0)
	_sampling_params["repetition_penalty"] = clampf(repetition_penalty, 1.0, 2.0)
	if available() and _android.has_method("set_sampling"):
		return bool(_android.call("set_sampling", _sampling_params["temperature"], _sampling_params["top_p"], _sampling_params["repetition_penalty"]))
	return true


func get_sampling() -> Dictionary:
	return _sampling_params.duplicate()


## Current context history token count.
func get_history_count() -> int:
	if available() and _android.has_method("get_history_count"):
		return int(_android.call("get_history_count"))
	return _mock_history_count


## Trims sliding-window context history to prevent memory explosion on mobile devices.
func trim_history(begin: int, end: int) -> bool:
	if available() and _android.has_method("trim_history"):
		return bool(_android.call("trim_history", begin, end))
	var removed := maxi(0, end - begin)
	_mock_history_count = maxi(0, _mock_history_count - removed)
	return true


## Formats prompt using model's native ChatML template.
func apply_template(prompt: String) -> String:
	if available() and _android.has_method("apply_template"):
		return String(_android.call("apply_template", prompt))
	return "<|im_start|>user\n" + prompt.strip_edges() + "<|im_end|>\n<|im_start|>assistant\n"


func chat_loaded() -> bool:
	return chat_ready()


func embedding_name() -> String:
	return "mnn" if available() else "mock_hash"
