class_name ModelStore
extends RefCounted
## WHERE HEXY'S MIND LIVES ON DISK AND MEMORY GATES, mirrored from canonical ix64-hexy.
##
## Manages on-device model tiers for Alibaba MNN:
##   - Floor: Qwen3-0.6B (min_ram 0, fits 4 GB like Galaxy A22)
##   - Mid:   Qwen3.5-0.8B (min_ram 6 GiB, hybrid attention)
##   - High:  Qwen3-1.7B (min_ram 8 GiB, full reasoning capacity)
##   - Embed: gte-embedding-multilingual-base-mnn (768-dim)

const LANE_EMBED := "embed"
const LANE_CHAT := "chat"
const LANE_CHAT_BIG := "chat_big"
const LANE_CHAT_35 := "chat35"

const LANE_DIRS := {
	LANE_EMBED: "gte-embedding-mnn",
	LANE_CHAT: "qwen3-0.6b-mnn",
	LANE_CHAT_BIG: "qwen3-1.7b-mnn",
	LANE_CHAT_35: "qwen3.5-0.8b-mnn",
}

## RAM GATES (bytes)
const CHAT_BIG_MIN_RAM := 8 * 1024 * 1024 * 1024  # 8 GiB
const CHAT_35_MIN_RAM := 6 * 1024 * 1024 * 1024   # 6 GiB

## Ordered list, read top to bottom: first row whose weights exist on disk
## AND whose min_ram the device clears wins. The floor has min_ram 0.
const CHAT_LANES := [
	{
		"lane": LANE_CHAT_BIG,
		"dir": LANE_DIRS[LANE_CHAT_BIG],
		"short": "1.7b",
		"min_ram": CHAT_BIG_MIN_RAM,
		"tier": "High"
	},
	{
		"lane": LANE_CHAT_35,
		"dir": LANE_DIRS[LANE_CHAT_35],
		"short": "0.8b",
		"min_ram": CHAT_35_MIN_RAM,
		"tier": "Mid"
	},
	{
		"lane": LANE_CHAT,
		"dir": LANE_DIRS[LANE_CHAT],
		"short": "0.6b",
		"min_ram": 0,
		"tier": "Floor"
	},
]

const ENV_CHAT_MODEL := "HEXY_CHAT_MODEL"
const ENV_RAM := "HEXY_RAM_BYTES"
const MEMINFO := "/proc/meminfo"
const MEMINFO_KEY := "MemTotal:"

const PICK_ENV := "env"
const PICK_TABLE := "table"
const PICK_FALLBACK := "floor_fallback"


static func detect_total_ram_bytes() -> int:
	# 1. Environment override (for testing and desktop simulation)
	if OS.has_environment(ENV_RAM):
		var env_val: String = OS.get_environment(ENV_RAM).strip_edges()
		if env_val.is_valid_int():
			return env_val.to_int()
	
	# 2. Linux / Android /proc/meminfo
	if FileAccess.file_exists(MEMINFO):
		var f := FileAccess.open(MEMINFO, FileAccess.READ)
		if f:
			while not f.eof_reached():
				var line := f.get_line()
				if line.begins_with(MEMINFO_KEY):
					var parts := line.split(" ", false)
					if parts.size() >= 2 and parts[1].is_valid_int():
						var kb: int = parts[1].to_int()
						return kb * 1024
			f.close()
	
	# 3. Desktop / Engine heuristic fallback
	# If running on desktop without meminfo, treat as developer workstation (16 GiB)
	if OS.get_name() in ["Windows", "macOS", "Linux"]:
		return 16 * 1024 * 1024 * 1024
	
	# Safe default for unknown devices: assume 4 GB floor
	return 4 * 1024 * 1024 * 1024


static func get_external_storage_dir() -> String:
	if OS.get_name() == "Android":
		# Standard Android external files path: /storage/emulated/0/Android/data/<pkg>/files
		var user_data: String = OS.get_user_data_dir()
		# user_data is /data/user/0/<pkg>/files
		if "/data/user/0/" in user_data or "/data/data/" in user_data:
			var pkg := user_data.get_slice("/data/user/0/", 1).get_slice("/files", 0)
			if pkg == "":
				pkg = user_data.get_slice("/data/data/", 1).get_slice("/files", 0)
			if pkg != "":
				return "/storage/emulated/0/Android/data/%s/files" % pkg
		# Common fallback
		return "/storage/emulated/0/Android/data/app.ix64.hexy/files"
	return "user://models"


static func check_model_files_exist(dir_name: String) -> bool:
	if dir_name == "":
		return false
	
	# Check Android external files path
	var ext_root := get_external_storage_dir()
	var config_path := ext_root.path_join(dir_name).path_join("config.json")
	if FileAccess.file_exists(config_path):
		return true
		
	# Check alternative user://models path
	var local_config := "user://models".path_join(dir_name).path_join("config.json")
	if FileAccess.file_exists(local_config):
		return true
		
	# On desktop/mock environments, allow standard dirs
	if OS.get_name() != "Android":
		return true
		
	return false


static func resolve_chat_lane() -> Dictionary:
	var ram_bytes := detect_total_ram_bytes()
	var ram_gb: float = float(ram_bytes) / (1024.0 * 1024.0 * 1024.0)
	
	# 1. Check explicit environment override
	if OS.has_environment(ENV_CHAT_MODEL):
		var env_pick := OS.get_environment(ENV_CHAT_MODEL).strip_edges()
		if env_pick != "":
			for lane in CHAT_LANES:
				if lane["dir"] == env_pick or lane["short"] == env_pick:
					return {
						"dir": lane["dir"],
						"short": lane["short"],
						"tier": lane["tier"],
						"lane": lane["lane"],
						"pick_reason": PICK_ENV,
						"ram_bytes": ram_bytes,
						"ram_gb": ram_gb,
						"gated_by_ram": false
					}
			return {
				"dir": env_pick,
				"short": "custom",
				"tier": "Custom",
				"lane": "custom",
				"pick_reason": PICK_ENV,
				"ram_bytes": ram_bytes,
				"ram_gb": ram_gb,
				"gated_by_ram": false
			}
	
	# 2. Walk CHAT_LANES table top to bottom
	var tried_higher_tiers: Array[String] = []
	for lane in CHAT_LANES:
		var clears_ram: bool = ram_bytes >= lane["min_ram"]
		var files_exist: bool = check_model_files_exist(lane["dir"])
		
		if clears_ram and files_exist:
			var was_gated := tried_higher_tiers.size() > 0
			return {
				"dir": lane["dir"],
				"short": lane["short"],
				"tier": lane["tier"],
				"lane": lane["lane"],
				"pick_reason": PICK_TABLE,
				"ram_bytes": ram_bytes,
				"ram_gb": ram_gb,
				"gated_by_ram": was_gated,
				"skipped_higher": tried_higher_tiers
			}
		else:
			var reason := ""
			if not clears_ram:
				reason = "RAM insufficient (%0.2f GB < %0.2f GB req)" % [ram_gb, float(lane["min_ram"]) / (1024.0*1024.0*1024.0)]
			elif not files_exist:
				reason = "Weights not found on disk"
			tried_higher_tiers.append("%s (%s)" % [lane["short"], reason])
			
	# 3. Absolute floor fallback
	var floor_lane: Dictionary = CHAT_LANES[CHAT_LANES.size() - 1]
	return {
		"dir": floor_lane["dir"],
		"short": floor_lane["short"],
		"tier": floor_lane["tier"],
		"lane": floor_lane["lane"],
		"pick_reason": PICK_FALLBACK,
		"ram_bytes": ram_bytes,
		"ram_gb": ram_gb,
		"gated_by_ram": true,
		"skipped_higher": tried_higher_tiers
	}


static func wants_no_think(dir_name: String) -> bool:
	# Qwen3 uses soft switch " /no_think"
	# Qwen3.5 handles thinking via jinja in config.json and should not receive the literal string
	if "qwen3.5" in dir_name:
		return false
	if "qwen3" in dir_name:
		return true
	return false
