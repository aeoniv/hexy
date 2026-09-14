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
var _free_storage: int = -2


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

## [{id, params, dir, tier, allowed, reason}] read straight from ModelStore,
## floor first. EVERY ROW CARRIES ITS VERDICT, so a list can show the refused
## tiers greyed with the reason instead of offering a phone a model it cannot
## hold. The verdict comes from the one gate, ModelStore.tier_allowed().
func tiers() -> Array[Dictionary]:
	var ram: int = ram_bytes()
	var free: int = free_storage_bytes()
	var arch: String = Engine.get_architecture_name()
	var out: Array[Dictionary] = ([] as Array[Dictionary])
	for id in [TIER_FLOOR, TIER_MID, TIER_HIGH]:
		var lane: String = String(TIER_LANE[id])
		for row in ModelStore.CHAT_LANES:
			if String(row["lane"]) == lane:
				var v: Dictionary = ModelStore.tier_allowed(id, ram, free, arch)
				out.append({
					"id": id,
					"params": String(row["short"]).to_upper(),
					"dir": String(row["dir"]),
					"tier": String(row["tier"]),
					"allowed": bool(v["allowed"]),
					"reason": String(v["reason"]),
				})
				break
	var ve: Dictionary = ModelStore.tier_allowed(TIER_EMBED, ram, free, arch)
	out.append({
		"id": TIER_EMBED,
		"params": "gte",
		"dir": String(ModelStore.LANE_DIRS[ModelStore.LANE_EMBED]),
		"tier": "Embed",
		"allowed": bool(ve["allowed"]),
		"reason": String(ve["reason"]),
	})
	return out


## The RAM this phone is judged by: DeviceProfile.resolve() is the source of
## truth, so the lane the profile names and the tiers the list offers are read
## off the same number.
func ram_bytes() -> int:
	return int(DeviceProfile.resolve().get("resolved_ram_bytes", 0))


## Free bytes where the weights would land, or -1 when the phone will not say.
## Measured once; a df per frame would cost more than the answer is worth.
func free_storage_bytes() -> int:
	if _free_storage == -2:
		_free_storage = ModelStore.free_storage_bytes()
	return _free_storage


## Why a tier is or is not allowed on this phone. Empty string means allowed.
func tier_refusal(tier_id: String) -> String:
	var v: Dictionary = ModelStore.tier_allowed(
		tier_id, ram_bytes(), free_storage_bytes(), Engine.get_architecture_name())
	return "" if bool(v["allowed"]) else String(v["reason"])


## One line naming every tier and its verdict, for the boot lamp.
func tier_lamp_line() -> String:
	var parts: Array[String] = ([] as Array[String])
	for row in tiers():
		if bool(row["allowed"]):
			parts.append("%s=yes" % String(row["id"]))
		else:
			parts.append("%s=no(%s)" % [String(row["id"]), String(row["reason"])])
	var free: int = free_storage_bytes()
	parts.append("free_storage=%s" % ("unknown" if free < 0 else "%.1fGB" % (float(free) / 1073741824.0)))
	return "hexy tiers: " + " ".join(parts)


## True only when the IxMnn singleton is present AND weights are on disk.
func available() -> bool:
	if not _runtime.available():
		return false
	return ModelStore.check_model_files_exist(_runtime.chat_model())


func backend_name() -> String:
	return "mnn" if available() else "mock"


func tier() -> String:
	return _tier


## The lane the runtime resolved, plus HOW HARD THE DECODE LOOP HEARS THE CUBE.
##
## `q6_prior_weight` is 0 everywhere the native plugin is not: on desktop there
## is no decode loop to lean on, so there is nothing to report but zero. Above 0
## it is the w in `logits[figure word] += w * p[h] * 64`, added once per token
## inside ixmnn, to the 64 King Wen words and nothing else.
##
## Q6Core answers this statically -- the weight belongs to the one decode loop,
## not to whichever object holds the cube -- so reading it does not take the
## native lease away from Pacing.
func info() -> Dictionary:
	var out: Dictionary = _runtime.model_info().duplicate()
	out["q6_prior_weight"] = Q6Core.prior_weight()
	## The warm-state stamp the next prompt will carry, the stamp the native
	## side last saw with its figure words, and how often the decode loop had
	## to throw a stale warm cache away. Off device: 0 mismatches, version -1.
	out["q6_cast_version"] = Q6Core.cast_version()
	out["q6_figure_version"] = Q6Core.native_figure_version()
	out["q6_prior_mismatches"] = Q6Core.prior_mismatches()
	return out


## How hard Qwen hears the cube. 0 leaves every logit alone and runs MNN's own
## decode path, which is the default and the old behaviour exactly.
func set_prior_weight(w: float) -> void:
	Q6Core.set_prior_weight(w)


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
	## THE SAME GATE THE LIST USED. A tier the phone was never offered may not
	## be loaded by a caller that asked for it by name either; the mock takes
	## over and the app keeps speaking, which is what a refusal means here.
	var refusal: String = tier_refusal(tier_id)
	if refusal != "":
		push_warning("hexy tiers: %s refused, %s" % [tier_id, refusal])
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
			_runtime.chat_stream(prompt, Q6Core.cast_version())
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
