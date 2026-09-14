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

	# Test 7: THE ONE GATE. Three phones, four tiers, one pure function.
	var GIB := 1024 * 1024 * 1024
	var plenty := 8 * GIB
	var a22 := int(3.8 * float(GIB))
	for t in ["floor", "embed"]:
		assert(ModelStore.tier_allowed(t, a22, plenty)["allowed"],
			"a 3.8 GB phone still gets %s" % t)
	for t in ["mid", "high"]:
		var v: Dictionary = ModelStore.tier_allowed(t, a22, plenty)
		print("Test 7 (3.8 GB, %s): %s" % [t, v["reason"]])
		assert(not v["allowed"], "a 3.8 GB phone may not be offered %s" % t)
		assert("RAM" in String(v["reason"]), "the refusal must name the RAM it wanted")
	var six := 6 * GIB
	assert(ModelStore.tier_allowed("mid", six, plenty)["allowed"], "6 GB clears mid")
	assert(not ModelStore.tier_allowed("high", six, plenty)["allowed"], "6 GB does not clear high")
	var fold_ram := int(11.8 * float(GIB))
	for t in ModelStore.TIER_ORDER:
		assert(ModelStore.tier_allowed(String(t), fold_ram, plenty)["allowed"],
			"11.8 GB carries every tier, including %s" % t)

	# Test 8: a full phone is refused whatever its RAM, and the reason says so.
	var cramped := ModelStore.tier_allowed("floor", fold_ram, 100 * 1024 * 1024)
	print("Test 8 (full disk): %s" % cramped["reason"])
	assert(not cramped["allowed"], "no room means no model")
	assert("free" in String(cramped["reason"]), "the refusal must name the storage")
	# Unmeasured storage is not a refusal.
	assert(ModelStore.tier_allowed("floor", fold_ram, -1)["allowed"],
		"a phone that will not say how full it is still gets to try")
	# A 32-bit phone carries nothing native.
	var armv7 := ModelStore.tier_allowed("floor", fold_ram, plenty, "armeabi-v7a")
	assert(not armv7["allowed"], "the native runtime is 64-bit only")
	assert(not ModelStore.tier_allowed("nonsense", fold_ram, plenty)["allowed"], "unknown tiers are refused")

	# Test 9: df read out of a page, not out of a guess.
	var df_page := "Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/fuse      110000000 9000000  50000000  16% /storage/emulated
"
	var avail := ModelStore.parse_df(df_page)
	print("Test 9 (df page): %d bytes (%.1f GiB)" % [avail, float(avail) / float(GIB)])
	assert(avail == 50000000 * 1024, "Available must be read as kB and returned as bytes")
	assert(ModelStore.parse_df("") == -1, "an empty page yields nothing, not a zero")

	# Test 10: the report keeps every tier, refused ones included.
	var report := ModelStore.tier_report(a22, plenty)
	assert(report.size() == ModelStore.TIER_ORDER.size(), "no tier is hidden from the list")

	print("--- ALL MODEL STORE TESTS PASSED PERFECTLY ---")
	quit(0)
