extends MainLoop

const DeviceProfileScript := preload("res://scripts/core/device_profile.gd")

var passes := 0
var failures := 0

const GIB := 1024 * 1024 * 1024


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func _process(_delta: float) -> bool:
	print("HEXY_TEST: Running Device Profile Test Suite...")
	OS.unset_environment("HEXY_DEVICE")

	_test_fold4_unfolded()
	_test_fold4_cover()
	_test_a22()
	_test_unknown_generic()
	_test_desktop()
	_test_schema()
	_test_env_override()

	print("\n=== DEVICE PROFILE TEST RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Device Profile Verified)")
	return true


func _test_fold4_unfolded() -> void:
	print("\n• Fold 4 unfolded 1812x2176 + 12 GiB...")
	var r := DeviceProfileScript.resolve(int(12.0 * GIB), Vector2i(1812, 2176), "Android")
	check(r["id"] == "galaxy_z_fold4", "resolves to galaxy_z_fold4 (got %s)" % r["id"])
	check(r["layout"] == "dual_pane", "layout is dual_pane (got %s)" % r["layout"])
	check(r["is_dual_pane"] == true, "is_dual_pane true")
	check(r["chat_lane"] == "high", "chat_lane is high (got %s)" % r["chat_lane"])


func _test_fold4_cover() -> void:
	print("\n• Fold 4 cover 904x2316 + 12 GiB...")
	var r := DeviceProfileScript.resolve(int(12.0 * GIB), Vector2i(904, 2316), "Android")
	check(r["id"] == "galaxy_z_fold4", "resolves to galaxy_z_fold4 (got %s)" % r["id"])
	check(r["layout"] == "tall_slab", "layout is tall_slab (got %s)" % r["layout"])


func _test_a22() -> void:
	print("\n• Galaxy A22 720x1600 + 3.5 GiB...")
	var r := DeviceProfileScript.resolve(int(3.5 * GIB), Vector2i(720, 1600), "Android")
	check(r["id"] == "galaxy_a22", "resolves to galaxy_a22 (got %s)" % r["id"])
	check(r["chat_lane"] == "floor", "chat_lane is floor (got %s)" % r["chat_lane"])


func _test_unknown_generic() -> void:
	print("\n• Unknown device 1080x2400 + 6 GiB...")
	var r := DeviceProfileScript.resolve(int(6.0 * GIB), Vector2i(1080, 2400), "Android")
	check(r["id"] == "generic_slab", "resolves to generic_slab (got %s)" % r["id"])
	check(r["chat_lane"] == "mid", "chat_lane is mid (got %s)" % r["chat_lane"])


func _test_desktop() -> void:
	print("\n• Desktop: Linux + 16 GiB...")
	var r := DeviceProfileScript.resolve(int(16.0 * GIB), Vector2i(1920, 1080), "Linux")
	check(r["id"] == "desktop", "resolves to desktop (got %s)" % r["id"])


func _test_schema() -> void:
	print("\n• PROFILES schema check (every row has required keys)...")
	var all_ok := true
	for row in DeviceProfileScript.PROFILES:
		for key in DeviceProfileScript.REQUIRED_KEYS:
			if not row.has(key):
				all_ok = false
				printerr("    row %s missing key %s" % [row.get("id", "?"), key])
	check(all_ok, "all PROFILES rows carry the required schema keys")


func _test_env_override() -> void:
	print("\n• Env override HEXY_DEVICE=galaxy_a22 wins...")
	OS.set_environment("HEXY_DEVICE", "galaxy_a22")
	# Deliberately pass Fold-4-shaped params; override must still win.
	var r := DeviceProfileScript.resolve(int(12.0 * GIB), Vector2i(1812, 2176), "Android")
	check(r["id"] == "galaxy_a22", "env override wins over aspect/RAM match (got %s)" % r["id"])
	OS.unset_environment("HEXY_DEVICE")
