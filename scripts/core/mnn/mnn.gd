class_name Mnn
extends Node

## The neural runtime, seen from the core as one small door.
##
## Wraps scripts/brain/mnn_runtime.gd (the IxMnn bridge) and
## scripts/brain/model_store.gd (the RAM-gated tier table) by composition, and
## keeps a MockLlm behind them. When no model is on the device, `generate()`
## still answers, so nothing upstream ever has to branch on availability.
##
## Only scripts/core/qwen talks to this node.

const MnnRuntimeScript = preload("res://scripts/brain/mnn_runtime.gd")

signal token(t: String)
signal done(text: String)

const TIER_FLOOR: String = "floor"
const TIER_MID: String = "mid"
const TIER_HIGH: String = "high"
const TIER_EMBED: String = "embed"

const TIER_LANE: Dictionary = {
	TIER_FLOOR: ModelStore.LANE_CHAT,
	TIER_MID: ModelStore.LANE_CHAT_35,
	TIER_HIGH: ModelStore.LANE_CHAT_BIG,
}

var _runtime: MnnRuntime = null
var _mock: MockLlm = null
var _tier: String = ""
var _loaded: bool = false
var _live: bool = false


func _init() -> void:
	_runtime = MnnRuntimeScript.new()
	_runtime.chat_token.connect(_on_runtime_token)
	_runtime.chat_done.connect(_on_runtime_done)


func _ready() -> void:
	_ensure_mock()


func _ensure_mock() -> void:
	if _mock != null:
		return
	_mock = MockLlm.new()
	_mock.name = "MockLlm"
	_mock.token.connect(_on_mock_token)
	_mock.done.connect(_on_mock_done)
	add_child(_mock)


# --- what the device can carry ----------------------------------------------

## [{id, params, dir, tier}] read straight from ModelStore, floor first.
func tiers() -> Array[Dictionary]:
	var out: Array[Dictionary] = ([] as Array[Dictionary])
	for id in [TIER_FLOOR, TIER_MID, TIER_HIGH]:
		var lane: String = String(TIER_LANE[id])
		for row in ModelStore.CHAT_LANES:
			if String(row["lane"]) == lane:
				out.append({
					"id": id,
					"params": String(row["short"]).to_upper(),
					"dir": String(row["dir"]),
					"tier": String(row["tier"]),
				})
				break
	out.append({
		"id": TIER_EMBED,
		"params": "gte",
		"dir": String(ModelStore.LANE_DIRS[ModelStore.LANE_EMBED]),
		"tier": "Embed",
	})
	return out


## True only when the IxMnn singleton is present AND weights are on disk.
func available() -> bool:
	if not _runtime.available():
		return false
	return ModelStore.check_model_files_exist(_runtime.chat_model())


func backend_name() -> String:
	return "mnn" if available() else "mock"


func tier() -> String:
	return _tier


func info() -> Dictionary:
	return _runtime.model_info()


# --- loading ----------------------------------------------------------------

## Bring up one tier by id ("floor" | "mid" | "high"). Returns false when the
## weights are not there; the mock takes over and the app keeps speaking.
func load_tier(tier_id: String = TIER_FLOOR) -> bool:
	_tier = tier_id
	var dir: String = ""
	for row in tiers():
		if String(row["id"]) == tier_id:
			dir = String(row["dir"])
			break
	if dir == "" or tier_id == TIER_EMBED:
		_loaded = false
		return false
	if not available():
		_loaded = false
		return false
	_loaded = _runtime.chat_start(dir)
	return _loaded


# --- speaking ---------------------------------------------------------------

## Start a generation. Emits `token` per piece and `done(text)` at the end.
## The returned Signal is `done`, so callers can `await mnn.generate(p)`.
func generate(prompt: String, max_tokens: int = 80) -> Signal:
	_ensure_mock()
	if available():
		if not _loaded:
			load_tier(_tier if _tier != "" else TIER_FLOOR)
		if _loaded:
			_live = true
			_runtime.chat_stream(prompt)
			return done
	_live = false
	_mock.start(prompt, max_tokens)
	return done


func cancel() -> void:
	_runtime.cancel()
	if _mock != null:
		_mock.cancel()


func _on_runtime_token(t: String) -> void:
	if _live:
		token.emit(t)


func _on_runtime_done(text: String) -> void:
	if not _live:
		return
	_live = false
	done.emit(text)


func _on_mock_token(t: String) -> void:
	if not _live:
		token.emit(t)


func _on_mock_done(text: String) -> void:
	if not _live:
		done.emit(text)


# --- embedding --------------------------------------------------------------

func embed(text: String) -> PackedFloat32Array:
	return _runtime.embed(text)


func embed_dim() -> int:
	return _runtime.embed_dim()
