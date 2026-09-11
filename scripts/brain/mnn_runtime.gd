extends RefCounted
class_name MnnRuntime
## Alibaba MNN Runtime bridge for on-device Qwen LLM and GTE embeddings.
## Connects to the native IxMnn Android plugin on device, or uses an offline fallback.
## Integrates canonical ix64-hexy ModelStore for RAM-gated tiers (0.6B Floor, 0.8B Mid, 1.7B High).

const ModelStore = preload("res://scripts/brain/model_store.gd")

signal chat_token(text: String)
signal chat_done(text: String)

const EMBED_MODEL := "gte-embedding-mnn"
const CHAT_MODEL := "qwen3-0.6b-mnn"
const MOCK_DIM := 64
const QWEN_NO_THINK := " /no_think"

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
		_android = Engine.get_singleton("IxMnn")
		_can_stream = _android.has_signal("chat_token") and _android.has_signal("chat_done")
		if _can_stream:
			_android.connect("chat_token", _on_plugin_token)
			_android.connect("chat_done", _on_plugin_done)

func _on_plugin_token(text: String) -> void:
	if _streaming:
		chat_token.emit(text)

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

func chat(prompt: String) -> String:
	if available():
		if not _chat_ready:
			chat_start()
		var formatted := _format_prompt(prompt)
		var res: String = str(_android.call("chat", formatted))
		if res != "":
			return res
	return "The ancient Book of Changes whispers: Change is constant. When the rigid yields to the flexible, harmony and progress endure."

func chat_stream(prompt: String) -> bool:
	if not _can_stream or not available():
		# Fallback simulation
		_streaming = true
		chat_done.emit(chat(prompt))
		return true
	_streaming = true
	var formatted := _format_prompt(prompt)
	return bool(_android.call("chat_stream", formatted))

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
