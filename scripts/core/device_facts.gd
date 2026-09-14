class_name DeviceFacts
extends RefCounted

## WHAT THIS PHONE IS, ASKED ONCE. Ported from ix64-hexy's refactor R3.
##
## Base already has two places that know a fact this file would otherwise
## re-derive: [DeviceProfile] (aspect/RAM table -> device id -> chat-lane
## hint) and [ModelStore] (RAM detection and `/proc/meminfo` parsing, because
## the chat-lane gate needed the same number first). THIS FILE DOES NOT
## RE-PARSE EITHER: [method physical_ram] and [method meminfo_ram] delegate to
## [ModelStore], and a caller that wants the device's resolved profile /
## chat-lane hint asks [DeviceProfile] directly rather than through here.
##
## What IS new here, versus origin: [method package_name] (read off the user
## data dir, unique to this file in both repos) and the same doorway origin
## kept — a single, stubbable place to ask "what is this phone" that a test
## can override without a device.
##
## ORIGIN-ONLY SYSTEMS NOT PORTED: origin's `plugin_ram()` and
## `network_kind()` / `free_bytes()` read through `IxMnn` / `DeviceEnv`, two
## origin-only doors. Base's MNN integration (`scripts/brain/mnn_runtime.gd`)
## is owned by another in-flight change and is not read from here to avoid a
## second writer on that seam; `DeviceEnv` does not exist in base at all.
## Both are stubbed below as named, unimplemented doors rather than ported.

## Test/desktop override for installed RAM, in BYTES. Mirrors
## [ModelStore]'s own env override name so the two never disagree about which
## variable a suite is allowed to set.
const ENV_RAM := ModelStore.ENV_RAM

## Where Linux — and therefore Android — keeps the answer Godot will not give.
## Kept here as a constant for callers that want to name the path in a log
## line; the actual read and parse happen in [ModelStore].
const MEMINFO := ModelStore.MEMINFO
const MEMINFO_KEY := ModelStore.MEMINFO_KEY

## WHO ANSWERED THE RAM QUESTION. On the boot line, so the next time this gate
## behaves oddly on a device it is one grep and not a third guess.
const SRC_ENV := "env"
const SRC_GODOT := "godot"
const SRC_MEMINFO := "meminfo"
## THE PLUGIN ROAD, NOT WIRED. Kept as a name only — see the doc above.
const SRC_PLUGIN := "plugin"
const SRC_UNKNOWN := "unknown"

## THE UNWIRED DOOR TO THE ANDROID FRAMEWORK'S OWN RAM FIGURE. Origin's
## `plugin_ram()` opened this through `IxMnn`; base's MNN seam is owned
## elsewhere in flight, so this is a name and nothing behind it.
const DOOR_PLUGIN_RAM := "plugin_ram"
## THE UNWIRED NETWORK-KIND / FREE-SPACE DOOR. Origin's `DeviceEnv`; base has
## no such subsystem yet.
const DOOR_DEVICE_ENV := "device_env"

## Fallback package name when the derivation finds nothing recognisable.
## Matches `export_presets.cfg` -> `package/unique_name`.
const PACKAGE := "app.ix64.hexy"


## True on the one platform any of this is real on.
static func is_android() -> bool:
	return OS.get_name() == "Android"


## The Android package name, read off the user data dir rather than assumed —
## a debug export and a release export can differ, and a path that is wrong by
## one segment fails as "no model pushed?" rather than as anything findable.
static func package_name() -> String:
	var parts := OS.get_user_data_dir().replace("\\", "/").split("/", false)
	# .../<package>/files -> the segment before the last.
	if parts.size() >= 2 and String(parts[-1]) == "files":
		var pkg := String(parts[-2])
		if pkg.contains("."):
			return pkg
	return PACKAGE


## Installed physical RAM in bytes. DELEGATES ENTIRELY to
## [ModelStore.detect_total_ram_bytes] — that is the one place base already
## reads `OS.get_memory_info()` / the env override / `/proc/meminfo`, and a
## second implementation here is exactly the duplication this port must not
## introduce. Unlike origin's `physical_ram()`, ModelStore's detector never
## answers "unknown": its last resort is a platform heuristic (16 GiB desktop,
## 4 GiB unknown-device floor), so this never returns -1.
static func physical_ram() -> int:
	return ModelStore.detect_total_ram_bytes()


## THE SAME ANSWER, PLUS WHO GAVE IT: `[bytes, source]`. Reproduces
## [ModelStore.detect_total_ram_bytes]'s own source order (env, Godot,
## meminfo, platform-heuristic-as-fallback) rather than re-detecting: the
## fallback tiers there have no "unknown" case left in them, so
## SRC_UNKNOWN is unreachable in base and kept only for parity with origin's
## return shape.
static func physical_ram_from() -> Array:
	var override := OS.get_environment(ENV_RAM).strip_edges()
	if not override.is_empty() and override.is_valid_int():
		return [override.to_int(), SRC_ENV]
	var info := OS.get_memory_info()
	var physical := int(info.get("physical", -1))
	if physical > 0:
		return [physical, SRC_GODOT]
	var mem := meminfo_ram()
	if mem > 0:
		return [mem, SRC_MEMINFO]
	# ModelStore's own fallback (platform heuristic / 4 GiB floor) still
	# answers something; delegate to it rather than duplicate that ladder.
	return [ModelStore.detect_total_ram_bytes(), SRC_UNKNOWN]


## MemTotal from `/proc/meminfo`, or -1 where there is no such file or no
## parseable line. THE FILE IS READ HERE (there is no public read-and-cache
## seam on [ModelStore] to reuse), but THE PARSE IS NOT: this delegates the
## actual "kB line -> bytes" arithmetic to [ModelStore.parse_meminfo] so the
## two files can never disagree about what a MemTotal line means.
static func meminfo_ram() -> int:
	var f := FileAccess.open(MEMINFO, FileAccess.READ)
	if f == null:
		return -1
	var text := f.get_as_text()
	f.close()
	var bytes := ModelStore.parse_meminfo(text)
	return bytes if bytes > 0 else -1


## WHAT KIND OF NETWORK THIS IS. UNWIRED IN BASE — origin delegated this to
## `DeviceEnv`, which does not exist here. Always answers "unknown" rather
## than guessing.
static func network_kind() -> String:
	return "unknown"


## Usable bytes on the filesystem the models live on, or -1 when it cannot be
## told. Delegates to [ModelStore.free_storage_bytes], base's own equivalent
## of origin's `DeviceEnv.free_bytes` — the `path` argument is accepted for
## origin API parity but ModelStore always measures its own model directory,
## so it is otherwise unused here.
static func free_bytes(_path: String) -> int:
	return ModelStore.free_storage_bytes()


## FORGET WHAT WAS CACHED. Kept for API parity with origin's suite hook; this
## file caches nothing of its own (both cached reads now live in
## [ModelStore]), so this is a no-op.
static func forget() -> void:
	pass
