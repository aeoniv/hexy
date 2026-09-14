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
	
	# 2. The engine's own figure, where the platform gives one.
	var physical: int = int(OS.get_memory_info().get("physical", -1))
	if physical > 0:
		return physical

	# 3. Linux / Android /proc/meminfo, OPENED WITHOUT ASKING FIRST. On Android
	# FileAccess.file_exists() answers false for a procfs entry that opens and
	# reads perfectly well, so the gate that used to stand here threw the real
	# number away and left the phone on the 4 GiB floor.
	var text: String = _read_meminfo()
	var parsed: int = parse_meminfo(text)
	if parsed > 0:
		return parsed
	
	# 4. Desktop / Engine heuristic fallback
	# If running on desktop without meminfo, treat as developer workstation (16 GiB)
	if OS.get_name() in ["Windows", "macOS", "Linux"]:
		return 16 * 1024 * 1024 * 1024
	
	# Safe default for unknown devices: assume 4 GB floor
	return 4 * 1024 * 1024 * 1024


## The text of /proc/meminfo, by whichever door the platform leaves open:
## FileAccess first, then a plain `cat`. Empty when there is no such file.
static func _read_meminfo() -> String:
	var f := FileAccess.open(MEMINFO, FileAccess.READ)
	if f != null:
		var text: String = f.get_as_text()
		f.close()
		if text.strip_edges() != "":
			return text
	var out: Array = []
	if OS.execute("cat", [MEMINFO], out, false) == 0 and not out.is_empty():
		return String(out[0])
	return ""


## MemTotal, in bytes, from the text of a meminfo file. Zero when the text
## carries no such line. Pure, so a headless test can hold it to a fixed page.
static func parse_meminfo(text: String) -> int:
	for raw in text.split("
"):
		var line: String = String(raw).strip_edges()
		if not line.begins_with(MEMINFO_KEY):
			continue
		var parts: PackedStringArray = line.split(" ", false)
		if parts.size() >= 2 and parts[1].is_valid_int():
			return parts[1].to_int() * 1024
	return 0


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


# -- WHAT EACH TIER ASKS OF THE PHONE ----------------------------------------
##
## One row per tier id, and the only place a requirement is written down. The
## chat rows mirror CHAT_LANES' min_ram; the embed row is deliberately free of
## a RAM gate, because a 768-dim encoder is small enough for the floor phone
## and the recall lane is the one thing a 4 GB device should still get.

const TIER_FLOOR := "floor"
const TIER_MID := "mid"
const TIER_HIGH := "high"
const TIER_EMBED := "embed"

const TIER_ORDER := [TIER_FLOOR, TIER_MID, TIER_HIGH, TIER_EMBED]

## Headroom kept free beyond the weights themselves: tokenizer, mmap scratch,
## and the room a half-finished download needs before it can be renamed.
const STORAGE_HEADROOM := 256 * 1024 * 1024

const TIER_SPECS := {
	TIER_FLOOR: {
		"lane": LANE_CHAT,
		"dir": LANE_DIRS[LANE_CHAT],
		"short": "0.6b",
		"min_ram": 0,
		"bytes": 580 * 1024 * 1024,
		"needs_native": true,
		"arch": "arm64",
		"min_api": 24,
	},
	TIER_MID: {
		"lane": LANE_CHAT_35,
		"dir": LANE_DIRS[LANE_CHAT_35],
		"short": "0.8b",
		"min_ram": CHAT_35_MIN_RAM,
		"bytes": 780 * 1024 * 1024,
		"needs_native": true,
		"arch": "arm64",
		"min_api": 24,
	},
	TIER_HIGH: {
		"lane": LANE_CHAT_BIG,
		"dir": LANE_DIRS[LANE_CHAT_BIG],
		"short": "1.7b",
		"min_ram": CHAT_BIG_MIN_RAM,
		"bytes": 1450 * 1024 * 1024,
		"needs_native": true,
		"arch": "arm64",
		"min_api": 24,
	},
	TIER_EMBED: {
		"lane": LANE_EMBED,
		"dir": LANE_DIRS[LANE_EMBED],
		"short": "gte",
		"min_ram": 0,
		"bytes": 320 * 1024 * 1024,
		"needs_native": true,
		"arch": "arm64",
		"min_api": 24,
	},
}


static func _gb(bytes: int) -> String:
	return "%.1f GB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))


## THE ONE GATE. Pure: the same three numbers always give the same verdict, so
## the list, the download and the load can each ask it and none of them can
## disagree with the others. free_storage_bytes < 0 means "not measured", which
## is not a refusal -- a phone that will not say how full it is still gets to
## try. Returns {allowed: bool, reason: String, tier: String}.
static func tier_allowed(tier: String, ram_bytes: int, free_storage_bytes: int = -1, arch: String = "arm64") -> Dictionary:
	if not TIER_SPECS.has(tier):
		return {"allowed": false, "reason": "no such tier", "tier": tier}
	var spec: Dictionary = TIER_SPECS[tier]
	if arch != "" and not arch.begins_with("arm64") and not arch.begins_with("x86_64"):
		return {"allowed": false, "reason": "needs a 64-bit phone, this one is %s" % arch, "tier": tier}
	var min_ram: int = int(spec["min_ram"])
	if min_ram > 0 and ram_bytes < min_ram:
		return {
			"allowed": false,
			"reason": "needs %s RAM, this phone has %s" % [_gb(min_ram), _gb(ram_bytes)],
			"tier": tier,
		}
	var need: int = int(spec["bytes"]) + STORAGE_HEADROOM
	if free_storage_bytes >= 0 and free_storage_bytes < need:
		return {
			"allowed": false,
			"reason": "needs %s free, this phone has %s" % [_gb(need), _gb(free_storage_bytes)],
			"tier": tier,
		}
	return {"allowed": true, "reason": "", "tier": tier}


## Free bytes on the volume the models live on. -1 when nothing will say.
## Android gives no DirAccess space call, so the same door the meminfo fix used
## is taken here: read the number out of `df`, and say -1 rather than guess.
static func free_storage_bytes() -> int:
	var target: String = get_external_storage_dir()
	if OS.get_name() != "Android":
		target = OS.get_user_data_dir()
	## BY WHICHEVER DOOR THE PLATFORM LEAVES OPEN. On Android a bare "df" is not
	## on the exec PATH the app inherits, so the phone answered "unknown" while
	## /system/bin/df sat right there and printed the number; the same lesson
	## the meminfo read had to learn.
	for bin_path in ["df", "/system/bin/df", "/system/xbin/df", "/bin/df"]:
		var out: Array = []
		if OS.execute(bin_path, ["-k", target], out, false) == 0 and not out.is_empty():
			var parsed: int = parse_df(String(out[0]))
			if parsed >= 0:
				return parsed
	return -1


## The "Available" column of `df -k`, in bytes, from the text of its output.
## -1 when the page carries no data row. Pure, so a headless test can hold it
## to a fixed page.
static func parse_df(text: String) -> int:
	var lines: PackedStringArray = text.split("\n", false)
	for i in range(lines.size()):
		var line: String = lines[i].strip_edges()
		if line == "" or line.begins_with("Filesystem"):
			continue
		var parts: PackedStringArray = line.split(" ", false)
		# Filesystem 1K-blocks Used Available Use% Mounted
		if parts.size() >= 4 and parts[3].is_valid_int():
			return parts[3].to_int() * 1024
	return -1


## Every tier with its verdict, in TIER_ORDER, for a list that must show the
## refused rows greyed rather than hide them.
static func tier_report(ram_bytes: int, free_storage_bytes_in: int = -1, arch: String = "arm64") -> Array:
	var out: Array = []
	for t in TIER_ORDER:
		var v: Dictionary = tier_allowed(String(t), ram_bytes, free_storage_bytes_in, arch)
		v["short"] = String(TIER_SPECS[t]["short"])
		v["dir"] = String(TIER_SPECS[t]["dir"])
		out.append(v)
	return out
