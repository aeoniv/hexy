extends SceneTree

func _init() -> void:
	print("--- TEST MODEL STORE RAM GATES ---")
	
	# Test 1: Simulated 3.5 GB device (like Galaxy A22)
	OS.set_environment("HEXY_RAM_BYTES", str(int(3.5 * 1024 * 1024 * 1024)))
	var lane_a22 := ModelStore.resolve_chat_lane()
	print("Test 1 (3.5 GB): Picked %s [%s Tier], Gated=%s" % [
		lane_a22["dir"], lane_a22["tier"], lane_a22["gated_by_ram"]
	])
	assert(lane_a22["dir"] == "qwen3-0.6b-mnn", "A22 must resolve to 0.6b floor")
	assert(lane_a22["tier"] == "Floor", "Tier must be Floor")
	assert(lane_a22["gated_by_ram"] == true, "Must flag that higher tiers were gated")
	
	# Test 2: Simulated 7.0 GB device (Mid tier)
	OS.set_environment("HEXY_RAM_BYTES", str(int(7.0 * 1024 * 1024 * 1024)))
	var lane_mid := ModelStore.resolve_chat_lane()
	print("Test 2 (7.0 GB): Picked %s [%s Tier], Gated=%s" % [
		lane_mid["dir"], lane_mid["tier"], lane_mid["gated_by_ram"]
	])
	# On desktop/test mock, check_model_files_exist returns true for desktop
	assert(lane_mid["dir"] == "qwen3.5-0.8b-mnn", "7GB must resolve to 0.8b mid tier")
	assert(lane_mid["tier"] == "Mid", "Tier must be Mid")
	
	# Test 3: Simulated 12.0 GB device (High tier)
	OS.set_environment("HEXY_RAM_BYTES", str(int(12.0 * 1024 * 1024 * 1024)))
	var lane_high := ModelStore.resolve_chat_lane()
	print("Test 3 (12.0 GB): Picked %s [%s Tier], Gated=%s" % [
		lane_high["dir"], lane_high["tier"], lane_high["gated_by_ram"]
	])
	assert(lane_high["dir"] == "qwen3-1.7b-mnn", "12GB must resolve to 1.7b high tier")
	assert(lane_high["tier"] == "High", "Tier must be High")
	
	# Test 4: Environment Override
	OS.set_environment("HEXY_CHAT_MODEL", "qwen3-0.6b-mnn")
	var lane_override := ModelStore.resolve_chat_lane()
	print("Test 4 (Override): Picked %s [%s Tier]" % [
		lane_override["dir"], lane_override["tier"]
	])
	assert(lane_override["dir"] == "qwen3-0.6b-mnn", "Explicit env override must take precedence")
	OS.unset_environment("HEXY_CHAT_MODEL")
	OS.unset_environment("HEXY_RAM_BYTES")
	
	# Test 5: MemTotal read out of a meminfo PAGE, not out of a file gate.
	# The Fold answers false to FileAccess.file_exists("/proc/meminfo") and -1
	# to OS.get_memory_info()["physical"], so the only number it will ever give
	# comes from parsing this page; when the parse was skipped the phone sat on
	# the 4 GiB floor and resolved generic_slab instead of galaxy_z_fold4.
	var page := "MemTotal:       11522060 kB
MemFree:         1234 kB
"
	var parsed := ModelStore.parse_meminfo(page)
	print("Test 5 (meminfo page): %d bytes (%.1f GiB)" % [
		parsed, float(parsed) / (1024.0 * 1024.0 * 1024.0)])
	assert(parsed == 11522060 * 1024, "MemTotal must be read as kB and returned as bytes")
	assert(ModelStore.parse_meminfo("") == 0, "an empty page must yield nothing, not a guess")
	assert(ModelStore.parse_meminfo("MemFree: 12 kB") == 0, "only MemTotal counts")

	# Test 6: a Fold-sized page resolves the Fold, not the fallback slab.
	var fold := DeviceProfile.resolve(parsed, Vector2i(904, 2316), "Android")
	print("Test 6 (Fold cover): profile=%s layout=%s lane=%s" % [
		fold["id"], fold["layout"], fold["chat_lane"]])
	assert(fold["id"] == "galaxy_z_fold4", "11 GiB at 2.562:1 is the Fold, not a generic slab")
	assert(fold["layout"] == "tall_slab", "the cover screen is a tall slab")

	print("--- ALL MODEL STORE TESTS PASSED PERFECTLY ---")
	quit(0)
