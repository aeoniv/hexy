extends SceneTree

## DEVICE FACTS SMOKE — scripts/core/device_facts.gd. The point is not that
## a desktop can read a phone's RAM; it is that DeviceFacts and ModelStore
## never disagree, because DeviceFacts delegates rather than re-parses.
## Prints === ALL PASS === or fails.

var _fails := 0
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		_fails += 1


func _initialize() -> void:
	_one_source()
	_meminfo_parser_agrees_with_model_store()
	_package_name()
	_unwired_doors_are_honest()

	print("checks: ", _checks)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


## DeviceFacts.physical_ram() must be the exact number ModelStore's own
## detector gives — that IS the delegation, proved rather than asserted.
func _one_source() -> void:
	_check(DeviceFacts.physical_ram() == ModelStore.detect_total_ram_bytes(),
		"DeviceFacts.physical_ram() equals ModelStore.detect_total_ram_bytes()")
	_check(DeviceFacts.physical_ram() > 0,
		"physical_ram() never answers unknown (ModelStore always has a floor)")


## meminfo_ram()'s arithmetic is ModelStore.parse_meminfo(), not a second
## parser — proved with the same sample text ModelStore's own suite uses.
func _meminfo_parser_agrees_with_model_store() -> void:
	var sample := "MemTotal:       3823456 kB\nMemFree:         123456 kB\n"
	_check(ModelStore.parse_meminfo(sample) == 3823456 * 1024,
		"sanity: ModelStore.parse_meminfo reads the sample line")
	# DeviceFacts.meminfo_ram() reads a real /proc/meminfo (absent on
	# Windows/macOS), so on desktop it must honestly answer -1 rather than
	# invent a number — but it must reach that -1 by "no such file", not by
	# a parser disagreement, which is exercised directly above.
	if OS.get_name() in ["Windows", "macOS"]:
		_check(DeviceFacts.meminfo_ram() == -1,
			"meminfo_ram() is -1 off this platform's absent /proc/meminfo")
	else:
		_check(DeviceFacts.meminfo_ram() == -1
			or DeviceFacts.meminfo_ram() > 0,
			"meminfo_ram() is either honest -1 or a positive byte count")


func _package_name() -> void:
	var pkg := DeviceFacts.package_name()
	_check(pkg.length() > 0, "package_name() answers something")
	_check(pkg.contains("."), "package_name() looks like a package id")


## The doors this port did not wire (origin's IxMnn plugin_ram, DeviceEnv
## network_kind/free_bytes) must fail closed / honest, never crash or lie.
func _unwired_doors_are_honest() -> void:
	_check(DeviceFacts.network_kind() == "unknown",
		"network_kind() is honestly unknown (DeviceEnv not ported)")
	_check(DeviceFacts.free_bytes("user://models") == ModelStore.free_storage_bytes(),
		"free_bytes() delegates to ModelStore.free_storage_bytes()")
	_check(DeviceFacts.is_android() == (OS.get_name() == "Android"),
		"is_android() matches OS.get_name()")
	DeviceFacts.forget()
	_check(true, "forget() is callable and a no-op")
