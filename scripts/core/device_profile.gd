class_name DeviceProfile
extends RefCounted
## TABLE-DRIVEN DEVICE PROFILE for hexy, mirrored from canonical ix64-hexy.
##
## Adding support for a new device = adding one row to PROFILES. Pure static,
## deterministic when parameters are supplied, no disk / Android calls beyond
## the OS / DisplayServer accessors that already exist elsewhere in hexy.
##
## Resolution order (see resolve()):
##   1. Explicit override: env HEXY_DEVICE or ProjectSettings "hexy/device_override"
##   2. Aspect + RAM match against PROFILES (skipping fallback rows)
##   3. generic_slab / desktop fallback

const ModelStoreScript := preload("res://scripts/brain/model_store.gd")

const ENV_DEVICE := "HEXY_DEVICE"
const PROJECT_SETTING_DEVICE := "hexy/device_override"

const GIB := 1024 * 1024 * 1024

## Required keys every PROFILES row must carry (schema test enforces this).
const REQUIRED_KEYS := [
	"id", "name", "min_ram_bytes", "max_ram_bytes", "screen_aspects",
	"has_hinge", "flex_hinge_deg", "dual_pane_min_width_px",
	"civil_fire_flex_multiplier", "target_fps", "chat_lane_hint",
]

## Each row's screen_aspects is an Array of [min, max] aspect ranges
## (height / width) that identify the device. has_hinge rows carry
## flex_hinge_deg as the hinge-angle band ([75, 115]) that counts as
## "flex mode"; rows without a hinge still carry a placeholder range.
const PROFILES := [
	{
		"id": "galaxy_z_fold4",
		"name": "Samsung Galaxy Z Fold 4",
		"min_ram_bytes": 10 * GIB,
		"max_ram_bytes": 14 * GIB,
		# Cover screen ~2.23-2.56:1 (tall slab), unfolded ~1.20:1 (near-square tablet)
		"screen_aspects": [[2.10, 2.60], [1.10, 1.30]],
		"has_hinge": true,
		"flex_hinge_deg": [75, 115],
		"dual_pane_min_width_px": 1200,
		"civil_fire_flex_multiplier": 2.0,
		"target_fps": 60,
		"chat_lane_hint": "high",
	},
	{
		"id": "galaxy_z_fold5",
		"name": "Samsung Galaxy Z Fold 5",
		# Same external display class as Fold 4; shares its aspect band until
		# a Fold 5-specific measurement says otherwise.
		"min_ram_bytes": 10 * GIB,
		"max_ram_bytes": 14 * GIB,
		"screen_aspects": [[2.10, 2.60], [1.10, 1.30]],
		"has_hinge": true,
		"flex_hinge_deg": [75, 115],
		"dual_pane_min_width_px": 1200,
		"civil_fire_flex_multiplier": 2.0,
		"target_fps": 60,
		"chat_lane_hint": "high",
	},
	{
		"id": "galaxy_z_fold6",
		"name": "Samsung Galaxy Z Fold 6",
		# Same external display class as Fold 4; shares its aspect band until
		# a Fold 6-specific measurement says otherwise.
		"min_ram_bytes": 10 * GIB,
		"max_ram_bytes": 14 * GIB,
		"screen_aspects": [[2.10, 2.60], [1.10, 1.30]],
		"has_hinge": true,
		"flex_hinge_deg": [75, 115],
		"dual_pane_min_width_px": 1200,
		"civil_fire_flex_multiplier": 2.0,
		"target_fps": 60,
		"chat_lane_hint": "high",
	},
	{
		"id": "galaxy_a22",
		"name": "Samsung Galaxy A22",
		"min_ram_bytes": 0,
		"max_ram_bytes": 5 * GIB,
		# 720x1600-class slab, ~2.22:1
		"screen_aspects": [[2.05, 2.40]],
		"has_hinge": false,
		"flex_hinge_deg": [0, 0],
		"dual_pane_min_width_px": 1200,
		"civil_fire_flex_multiplier": 1.0,
		"target_fps": 60,
		"chat_lane_hint": "floor",
	},
	{
		"id": "generic_slab",
		"name": "Generic Slab (fallback)",
		"min_ram_bytes": 0,
		"max_ram_bytes": -1,
		"screen_aspects": [],
		"has_hinge": false,
		"flex_hinge_deg": [0, 0],
		"dual_pane_min_width_px": 1200,
		"civil_fire_flex_multiplier": 1.0,
		"target_fps": 60,
		"chat_lane_hint": "mid",
	},
	{
		"id": "desktop",
		"name": "Desktop / Workstation",
		"min_ram_bytes": 16 * GIB,
		"max_ram_bytes": -1,
		"screen_aspects": [],
		"has_hinge": false,
		"flex_hinge_deg": [0, 0],
		"dual_pane_min_width_px": 1200,
		"civil_fire_flex_multiplier": 1.0,
		"target_fps": 60,
		"chat_lane_hint": "high",
	},
]


static func _get_row(id: String) -> Dictionary:
	for row in PROFILES:
		if row["id"] == id:
			return row
	return {}


static func _aspect_matches(row: Dictionary, aspect: float) -> bool:
	for band in row["screen_aspects"]:
		if aspect >= band[0] and aspect <= band[1]:
			return true
	return false


static func _ram_matches(row: Dictionary, ram_bytes: int) -> bool:
	if ram_bytes < row["min_ram_bytes"]:
		return false
	if row["max_ram_bytes"] >= 0 and ram_bytes > row["max_ram_bytes"]:
		return false
	return true


static func _resolve_chat_lane_for_ram(ram_bytes: int) -> String:
	# Mirrors ModelStore.resolve_chat_lane()'s RAM gating without touching disk.
	if ram_bytes >= ModelStoreScript.CHAT_BIG_MIN_RAM:
		return "high"
	if ram_bytes >= ModelStoreScript.CHAT_35_MIN_RAM:
		return "mid"
	return "floor"


static func _explicit_override() -> String:
	if OS.has_environment(ENV_DEVICE):
		var env_val := OS.get_environment(ENV_DEVICE).strip_edges()
		if env_val != "":
			return env_val
	if ProjectSettings.has_setting(PROJECT_SETTING_DEVICE):
		var setting_val: String = String(ProjectSettings.get_setting(PROJECT_SETTING_DEVICE, ""))
		if setting_val.strip_edges() != "":
			return setting_val.strip_edges()
	return ""


## Resolves the device profile row for the given (or live) parameters.
## Returns the row's dictionary plus resolved fields: is_dual_pane, chat_lane,
## layout. Deterministic and side-effect free whenever ram_bytes/viewport/
## os_name are supplied explicitly.
static func resolve(ram_bytes: int = -1, viewport: Vector2i = Vector2i.ZERO, os_name: String = "") -> Dictionary:
	var resolved_ram := ram_bytes
	if resolved_ram < 0:
		resolved_ram = ModelStoreScript.detect_total_ram_bytes()

	var resolved_viewport := viewport
	if resolved_viewport == Vector2i.ZERO:
		resolved_viewport = DisplayServer.window_get_size()

	var resolved_os := os_name
	if resolved_os == "":
		resolved_os = OS.get_name()

	var row := {}

	# 1. Explicit override
	var override_id := _explicit_override()
	if override_id != "":
		row = _get_row(override_id)

	# 2. Aspect + RAM match (skip fallback rows, which have empty screen_aspects)
	if row.is_empty():
		var aspect := 0.0
		if resolved_viewport.x > 0:
			aspect = float(resolved_viewport.y) / float(resolved_viewport.x)
		for candidate in PROFILES:
			if candidate["screen_aspects"].is_empty():
				continue
			if _aspect_matches(candidate, aspect) and _ram_matches(candidate, resolved_ram):
				row = candidate
				break

	# 3. Fallback: desktop if non-Android with big RAM, else generic_slab
	if row.is_empty():
		if resolved_os != "Android" and resolved_ram >= (16 * GIB):
			row = _get_row("desktop")
		else:
			row = _get_row("generic_slab")

	var result := row.duplicate(true)
	result["is_dual_pane"] = resolved_viewport.x > int(row["dual_pane_min_width_px"])
	result["chat_lane"] = _resolve_chat_lane_for_ram(resolved_ram)
	if row["has_hinge"] and result["is_dual_pane"]:
		result["layout"] = "dual_pane"
	elif row["has_hinge"]:
		result["layout"] = "tall_slab"
	elif result["is_dual_pane"]:
		result["layout"] = "tablet"
	else:
		result["layout"] = "tall_slab"
	result["resolved_ram_bytes"] = resolved_ram
	result["resolved_viewport"] = resolved_viewport
	result["resolved_os_name"] = resolved_os
	return result
