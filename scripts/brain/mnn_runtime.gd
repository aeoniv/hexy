extends RefCounted
class_name MnnRuntime
## Alibaba MNN Runtime bridge for on-device Qwen LLM and GTE embeddings.
## Connects to the native IxMnn Android plugin on device, or uses an offline fallback.
## Integrates canonical ix64-hexy ModelStore for RAM-gated tiers (0.6B Floor, 0.8B Mid, 1.7B High).

const ModelStore = preload("res://scripts/brain/model_store.gd")
const Seam = preload("res://scripts/seam.gd")

signal chat_token(text: String)
## The reasoning half of a streamed turn, separated from the speech. Emitted
## only while `_streaming`; a plugin with no `chat_thought` simply never fires.
signal chat_thought(text: String)
signal chat_done(text: String)

const EMBED_MODEL := "gte-embedding-mnn"
const CHAT_MODEL := "qwen3-0.6b-mnn"
const MOCK_DIM := 64
const QWEN_NO_THINK := " /no_think"

## THE AAR THIS SCRIPT WAS WRITTEN AGAINST, checked at attach by
## `scripts/seam.gd`. A stale ixmnn answers `has_singleton` true and then loses
## whichever new method this script needs, silently; the handshake is what turns
## that into one loud line and an honest mock.
##
## NAMED `REQUIRES`, NOT `NEEDS`. `NEEDS` is already the fly-brain's six need
## lines (`scripts/creature/reading_words.gd`), and one word cannot mean both.
const REQUIRES := "ixmnn/2"

## The plugin name and version this seam requires, split. Read by
## `tests/plugin_version_smoke.gd` so the handshake string can never rot into a
## shape `seam.gd` would compare but nobody could parse.
const REQUIRES_TAG := "mnn"

var _android: Object = null
var _dim := MOCK_DIM
var _chat_ready := false
var _chat_model := ""
var _lane_info: Dictionary = {}
var _streaming := false
var _can_stream := false

func _init() -> void:
	# Initialise default lane info
	_lane_info = ModelStore.resolve_chat_lane()
	_chat_model = _lane_info.get("dir", CHAT_MODEL)
	
	if Engine.has_singleton("IxMnn"):
		var node: Object = Engine.get_singleton("IxMnn")
		# THE VERSION HANDSHAKE, BEFORE A SINGLE SIGNAL IS CONNECTED. On a
		# mismatch `seam.gd` prints the loud line and we keep `_android` null,
		# which `available()` already reads as "run the mock". A mock that says
		# it is a mock beats a plugin that lies about its age.
		if not Seam.check(node, REQUIRES, REQUIRES_TAG):
			return
		_android = node
		_can_stream = _android.has_signal("chat_token") and _android.has_signal("chat_done")
		if _can_stream:
			_android.connect("chat_token", _on_plugin_token)
			_android.connect("chat_done", _on_plugin_done)
		if _android.has_signal("chat_thought"):
			_android.connect("chat_thought", _on_plugin_thought)

func _on_plugin_token(text: String) -> void:
	if _streaming:
		chat_token.emit(text)

func _on_plugin_thought(text: String) -> void:
	if _streaming:
		chat_thought.emit(text)

func _on_plugin_done(text: String) -> void:
	if not _streaming:
		return
	_streaming = false
	chat_done.emit(text)

func cancel() -> void:
	_streaming = false

func available() -> bool:
	return _android != null and _android.call("runtime_ready")

func backend_name() -> String:
	return "mnn" if available() else "mock"

func model_info() -> Dictionary:
	return _lane_info

func tier_name() -> String:
	return str(_lane_info.get("tier", "Floor"))

func short_name() -> String:
	return str(_lane_info.get("short", "0.6b"))

func detected_ram_gb() -> float:
	return float(_lane_info.get("ram_gb", 0.0))

func is_gated() -> bool:
	return bool(_lane_info.get("gated_by_ram", false))

func embed_start(model_name: String = EMBED_MODEL) -> int:
	if available():
		var ret: int = int(_android.call("embed_start", model_name))
		if ret > 0:
			_dim = ret
		return _dim
	_dim = MOCK_DIM
	return _dim

func embed_dim() -> int:
	return _dim

func embed(text: String) -> PackedFloat32Array:
	if available():
		var raw = _android.call("embed", text)
		if raw is PackedFloat32Array:
			return raw
	# Fallback deterministic mock
	var vec := PackedFloat32Array()
	vec.resize(_dim)
	var hash_val := text.hash()
	var sum_sq := 0.0
	for i in range(_dim):
		var v := sin(float((hash_val ^ (i * 7919)) % 65536))
		vec[i] = v
		sum_sq += v * v
	var norm := sqrt(sum_sq)
	if norm > 0.0001:
		for i in range(_dim):
			vec[i] /= norm
	return vec

func chat_start(model_name: String = "") -> bool:
	if model_name == "":
		_lane_info = ModelStore.resolve_chat_lane()
		_chat_model = _lane_info.get("dir", CHAT_MODEL)
	else:
		_chat_model = model_name
		
	print("HEXY_MNN: Resolving Chat Lane -> %s [%s Tier] (Pick: %s, RAM: %0.2f GB)" % [
		_chat_model,
		tier_name(),
		_lane_info.get("pick_reason", "direct"),
		detected_ram_gb()
	])
	
	if available():
		_chat_ready = bool(_android.call("chat_start", _chat_model))
		return _chat_ready
	_chat_ready = true
	return true

func chat_ready() -> bool:
	return _chat_ready

func chat_model() -> String:
	return _chat_model if _chat_model != "" else CHAT_MODEL

func _format_prompt(prompt: String) -> String:
	if ModelStore.wants_no_think(_chat_model):
		return prompt + QWEN_NO_THINK
	return prompt

## Formats prompt with dynamic Drosophila biological state context
func format_biological_prompt(user_query: String, bio_telemetry: Dictionary) -> String:
	var mood_prefix := ""
	if not bio_telemetry.is_empty():
		var da := int(bio_telemetry.get("da", 0.5) * 100.0)
		var oa := int(bio_telemetry.get("oa", 0.5) * 100.0)
		var dfb := int(bio_telemetry.get("dfb", 0.2) * 100.0)
		var compass: String = bio_telemetry.get("compass_trigram", "Heaven 乾")
		var posture: String = bio_telemetry.get("posture", "Upright")
		var circadian: String = bio_telemetry.get("circadian_phase", "Day")
		mood_prefix = "[Organism State: DA=%d%%, OA=%d%%, Rest=%d%% | Heading: %s | Posture: %s | Phase: %s]\n" % [
			da, oa, dfb, compass, posture, circadian
		]
	return _format_prompt(mood_prefix + user_query)

## `cast_version` is the Q6 warm-state stamp the prompt was written under; the
## native side drops a kv-cache warmed under an older cube rather than answer
## for a figure the body has left. -1 means "don't care", which is the old
## behaviour exactly, and is also what a plugin without `chat_at` gets.
func chat(prompt: String, cast_version: int = -1) -> String:
	if available():
		if not _chat_ready:
			chat_start()
		var formatted := _format_prompt(prompt)
		# NO has_method HERE. A JNISingleton answers has_method FALSE for every
		# @UsedByGodot method it owns, so the guard that used to stand here took
		# the else branch on every real phone and silently dropped the Q6
		# cast-version cache guard. The handshake at `_init` is the only gate:
		# past it, `chat_at` exists because ixmnn/2 owns it.
		var res: String = str(_android.call("chat_at", formatted, cast_version))
		if res != "":
			return res
	return "The ancient Book of Changes whispers: Change is constant. When the rigid yields to the flexible, harmony and progress endure."

func chat_stream(prompt: String, cast_version: int = -1) -> bool:
	if not _can_stream or not available():
		# Fallback simulation
		_streaming = true
		chat_done.emit(chat(prompt, cast_version))
		return true
	_streaming = true
	var formatted := _format_prompt(prompt)
	# Handshake-gated, not has_method-gated — see `chat()` above.
	return bool(_android.call("chat_stream_at", formatted, cast_version))

static func cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var dot := 0.0
	var norm_a := 0.0
	var norm_b := 0.0
	for i in range(a.size()):
		dot += a[i] * b[i]
		norm_a += a[i] * a[i]
		norm_b += b[i] * b[i]
	var denom := sqrt(norm_a) * sqrt(norm_b)
	return dot / denom if denom > 0.00001 else 0.0


# ── MNN ENGINE EXTENSIONS: TOKENIZER, SAMPLING, PERF & CONTEXT ──────────────
#
# Every one of these calls a method the ixmnn/2 aar owns. `REQUIRES` above is
# THE ONLY GATE. There is no second has_method fence, and there must not be: a
# JNISingleton answers `has_method` FALSE for every @UsedByGodot method it
# owns, so that fence fired on every real phone and sent the whole extension
# surface to the desktop mock while blaming a stale aar that was fine. If the
# handshake at `_init` passed at REQUIRES, every /2 method is called bare; if
# the singleton is absent (desktop, headless), `available()` is false and the
# mock below answers. Those are the two states, and there is no third.

## Desktop truth for the sampling knobs: the plugin does not own a getter, so
## the last values set are kept here and handed back by [get_sampling].
var _sampling_params := {
	"temperature": 0.7,
	"top_p": 0.9,
	"repetition_penalty": 1.15,
}

var _mock_history_count := 0
var _mock_vocab: Dictionary = {}
var _mock_inv_vocab: Dictionary = {}
var _last_perf := {
	"prompt_len": 0,
	"gen_seq_len": 0,
	"all_seq_len": 0,
	"prefill_ms": 0.0,
	"decode_ms": 0.0,
	"tps": 0.0,
	"status": 0,
}


## THE ONLY GATE, kept as a name so every extension below reads the same way.
## True means: a singleton is here and it passed the REQUIRES handshake, so the
## whole ixmnn/2 method surface may be called bare. False means desktop/headless
## and the mock answers. `method` is documentation for the reader, not a probe.
func _plugin_owns(method: String) -> bool:
	return available()


## TEST SEAM. Attaches `node` exactly the way `_init` attaches a real
## singleton — version handshake first, signals after — so a headless test can
## pin the on-device branch without an aar. Returns whether the handshake passed.
func _attach_plugin_for_test(node: Object) -> bool:
	_android = null
	_can_stream = false
	if node == null:
		return false
	if not Seam.check(node, REQUIRES, REQUIRES_TAG):
		return false
	_android = node
	_can_stream = node.has_signal("chat_token") and node.has_signal("chat_done")
	if _can_stream:
		node.connect("chat_token", _on_plugin_token)
		node.connect("chat_done", _on_plugin_done)
	return true


## True between `chat_stream()` and its `chat_done`.
func streaming() -> bool:
	return _streaming


## The same question `chat_ready()` answers, under the name the agent loop asks.
func chat_loaded() -> bool:
	return chat_ready()


func embedding_name() -> String:
	return "mnn" if available() else "mock_hash"


## THE PROMPT SWITCH, FENCED BY FAMILY. True only for the Qwen3 line, the only
## line that reads `/no_think` as a command rather than as words. The dash does
## the work: "qwen3-" excludes "qwen3.5-0.8b-mnn", which has no such switch.
static func _wants_no_think(dir: String) -> bool:
	return dir.begins_with("qwen3-")


## Splits a reply into its reasoning (`<think>...</think>`) and its speech.
## Pure, so a test can pin the shape without owning a model.
static func partition_think(text: String) -> Dictionary:
	var open_tag := "<think>"
	var close_tag := "</think>"
	var b := text.find(open_tag)
	var e := text.find(close_tag)
	if b == -1:
		return {"thought": "", "speech": text.strip_edges()}
	if e == -1 or e < b:
		return {
			"thought": text.substr(b + open_tag.length()).strip_edges(),
			"speech": text.substr(0, b).strip_edges(),
		}
	var thought := text.substr(b + open_tag.length(), e - (b + open_tag.length()))
	var speech := text.substr(0, b) + text.substr(e + close_tag.length())
	return {"thought": thought.strip_edges(), "speech": speech.strip_edges()}


## THE MOCK'S TOKENS, a pure function so a test can pin the shape of a stream.
## Words with their trailing space kept on the chunk — the shape a real
## tokenizer produces, and therefore the shape a sentence splitter must survive.
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


## Encodes a prompt into model token ids. The mock keeps a growing word->id
## vocabulary, so the same word is the same id for the life of the runtime.
func tokenize(text: String) -> PackedInt32Array:
	if _plugin_owns("tokenize"):
		# The engine marshals a Kotlin IntArray as PackedInt32Array, but an older
		# aar may hand back a plain Array; both are accepted rather than assumed.
		var raw: Variant = _android.call("tokenize", text)
		if raw is PackedInt32Array:
			return raw
		var ids := PackedInt32Array()
		if raw is Array:
			var arr: Array = raw
			ids.resize(arr.size())
			for i in arr.size():
				ids[i] = int(arr[i])
		return ids
	var out := PackedInt32Array()
	for w in text.split(" ", false):
		var lower := String(w).to_lower().strip_edges()
		if lower == "":
			continue
		if not _mock_vocab.has(lower):
			var new_id := 1000 + int(_mock_vocab.size())
			_mock_vocab[lower] = new_id
			_mock_inv_vocab[new_id] = lower
		out.append(int(_mock_vocab[lower]))
	return out


## Decodes one token id back into text. Round-trips whatever [tokenize] made.
func detokenize(token_id: int) -> String:
	if _plugin_owns("detokenize"):
		return String(_android.call("detokenize", token_id))
	if _mock_inv_vocab.has(token_id):
		return String(_mock_inv_vocab[token_id]) + " "
	return "[tok_%d] " % token_id


## Native execution telemetry: prefill/decode latency, tokens per second and the
## three sequence lengths. Milliseconds out, microseconds in.
func get_perf() -> Dictionary:
	if _plugin_owns("get_perf"):
		var parsed: Variant = JSON.parse_string(String(_android.call("get_perf")))
		if parsed is Dictionary:
			var d: Dictionary = parsed
			var p_us := float(d.get("prefill_us", 0))
			var d_us := float(d.get("decode_us", 0))
			var gen_len := int(d.get("gen_seq_len", 0))
			var tps := 0.0
			if d_us > 0.0 and gen_len > 0:
				tps = (float(gen_len) * 1000000.0) / d_us
			_last_perf = {
				"prompt_len": int(d.get("prompt_len", 0)),
				"gen_seq_len": gen_len,
				"all_seq_len": int(d.get("all_seq_len", 0)),
				"prefill_ms": p_us / 1000.0,
				"decode_ms": d_us / 1000.0,
				"tps": snappedf(tps, 0.1),
				"status": int(d.get("status", 0)),
			}
	return _last_perf.duplicate()


## Sets runtime sampling. The clamps are this seam's, not the plugin's, so the
## mock and the phone agree about what a legal temperature is.
func set_sampling(temperature: float, top_p: float = 0.9, repetition_penalty: float = 1.15) -> bool:
	_sampling_params["temperature"] = clampf(temperature, 0.05, 2.0)
	_sampling_params["top_p"] = clampf(top_p, 0.1, 1.0)
	_sampling_params["repetition_penalty"] = clampf(repetition_penalty, 1.0, 2.0)
	if _plugin_owns("set_sampling"):
		return bool(_android.call("set_sampling",
			_sampling_params["temperature"],
			_sampling_params["top_p"],
			_sampling_params["repetition_penalty"]))
	return true


func get_sampling() -> Dictionary:
	return _sampling_params.duplicate()


## How many tokens of context history the session is carrying.
func get_history_count() -> int:
	if _plugin_owns("get_history_count"):
		return int(_android.call("get_history_count"))
	return _mock_history_count


## Trims the sliding window [begin, end) out of the kv-cache, so a long turn on
## a phone does not grow until the OS takes the process away.
func trim_history(begin: int, end: int) -> bool:
	if _plugin_owns("trim_history"):
		return bool(_android.call("trim_history", begin, end))
	_mock_history_count = maxi(0, _mock_history_count - maxi(0, end - begin))
	return true


## Formats a prompt with the model's own ChatML template. The mock writes the
## Qwen shape by hand so a caller can be tested against a real-looking string.
func apply_template(prompt: String) -> String:
	if _plugin_owns("apply_template"):
		return String(_android.call("apply_template", prompt))
	return "<|im_start|>user\n" + prompt.strip_edges() + "<|im_end|>\n<|im_start|>assistant\n"


## THE DESKTOP FALLBACKS, named so a caller can reach them on purpose. Enough
## shape to write and test against, never enough to be mistaken for thought.
func _mock_chat(prompt: String) -> String:
	if prompt.strip_edges().is_empty():
		return ""
	_mock_history_count += tokenize(prompt).size()
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
	if norm > 0.00001:
		for i in MOCK_DIM:
			v[i] /= norm
	return v
