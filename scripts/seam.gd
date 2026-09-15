extends RefCounted
## THE VERSION HANDSHAKE, ONE FUNCTION, ELEVEN CALLERS.
##
## THE DEFECT THIS CLOSES. Every plugin AAR under `addons/*/bin/` is gitignored
## build output. `docs/FIELD.md` asked, in prose, for a copy after every Kotlin
## change, and nothing enforced it. A forgotten copy ships an OLD plugin under a
## NEW script, and the failure is SILENT in the worst way: `Engine.has_singleton`
## still answers true, `attach()` still prints `source=ixbody`, signals that the
## old AAR happens to have still connect — and the one new method the new script
## needs lands nowhere. Hours went into "the Kotlin change did nothing".
##
## THE ARRANGEMENT. Each plugin carries `const val PLUGIN_VERSION = "<name>/<n>"`
## and answers it through `@UsedByGodot fun plugin_version()`. Each GDScript seam
## carries a `const REQUIRES` with the string it was written against. At attach, and
## only at attach, [check] compares them. On a mismatch the seam prints one loud
## line, drops the singleton and runs its mock — a mock that says it is a mock is
## strictly better than a plugin that lies about its age.
##
## WHY THE CALL IS NOT GUARDED, and this is the same law body_sense.gd,
## pose_sense.gd and lens_sense.gd all record in their own words: a JNISingleton
## answers `has_method` FALSE for every `@UsedByGodot` method it owns. A
## has_method guard here would be a handshake that never happens on exactly the
## device it exists for. So the call goes out bare. An AAR too old to have
## `plugin_version` at all makes the engine print its own error above our line
## and hands back `null` — which [check] reads as "too old", which is the right
## answer, and the noise is the point.
##
## THE GATE LIVES AT ATTACH, BESIDE THE has_signal GATING, and nowhere else. No
## call site anywhere in this app asks the version again; a seam that got past
## attach has already been told it may speak.
##
## AND IT IS THE ONLY GATE. A per-call `has_method` fence is not a safety net on
## top of the handshake, it is the handshake's opposite: it answers false for
## every method the plugin really owns, so it fires on the phone and never on
## the desktop — the exact inversion of the behaviour anyone writing it wanted.
## `scripts/brain/mnn_runtime.gd` carried such a fence over its whole ixmnn/2
## extension surface (tokenize, get_perf, set_sampling, trim_history,
## apply_template, and the versioned `chat_at`/`chat_stream_at`) and every
## device silently ran the desktop mock while blaming a stale aar. Two states
## only: handshake passed, call bare; no singleton, run the mock.

## The method every plugin answers. Named once, here.
const CALL := "plugin_version"

## What a seam whose plugin was too old to answer at all reports as its version.
const UNKNOWN := "(no plugin_version — the aar predates the handshake)"


## What the plugin says it is, or [UNKNOWN] when it cannot say. Never null:
## a caller comparing against a null is a caller that will compare wrong once.
static func version_of(node: Object) -> String:
	if node == null:
		return UNKNOWN
	var got: Variant = node.call(CALL)
	if typeof(got) != TYPE_STRING or String(got).is_empty():
		return UNKNOWN
	return String(got)


## THE ONE LOUD LINE. Deliberately long and deliberately naming the fix: the
## person reading it in logcat is three hours from the answer otherwise.
static func mismatch_line(tag: String, needs: String, got: String) -> String:
	return "%s: STALE PLUGIN — this script needs %s, the aar answers %s. " % [
		tag, needs, got] + \
		"Falling back to mock. Run `./gradlew exportAllAars` and re-export."


## True when the seam may keep its singleton. False means: set `_android = null`
## and degrade to the mock, which the caller does so the degrade is visible in
## the seam's own file rather than hidden in this one.
static func check(node: Object, needs: String, tag: String) -> bool:
	var got := version_of(node)
	if got == needs:
		return true
	print(mismatch_line(tag, needs, got))
	return false


# ── THE ONE IXMNN, HANDSHAKEN ONCE ─────────────────────────────────────────
#
# THREE FILES SHARE THIS SINGLETON and each of them used to reach for it alone
# behind a `has_method` probe: `core/iching/q6.gd` (the cube's native lease),
# `core/mic.gd` (the recogniser) and `sensor_oracle.gd` (lux, proximity,
# battery). On a phone every one of those probes answers false, so the cube ran
# in GDScript, the mic ran its mock and the three sensors stayed at their
# defaults — silently, on the device the code was written for.
#
# The fix is NOT three more handshakes. `brain/mnn_runtime.gd` already carries
# the one `REQUIRES` for this aar, so that constant is the single source and
# this accessor is the single door. Checked once, cached, and after that every
# ixmnn/2 method is called bare.

## The handshake's verdict, cached: null means "no plugin, run your mock".
## The extra flag is what separates "checked, and it is null" from "not asked
## yet", which a plain null cannot say.
static var _ixmnn: Object = null
static var _ixmnn_asked: bool = false


## THE SINGLETON, OR NULL. Never raises, never probes, never asks twice.
## The require string is loaded, not preloaded, because `mnn_runtime.gd`
## preloads this file and a preload back would be a cycle.
static func ixmnn() -> Object:
	if _ixmnn_asked:
		return _ixmnn
	_ixmnn_asked = true
	_ixmnn = null
	if not Engine.has_singleton("IxMnn"):
		return null
	var node: Object = Engine.get_singleton("IxMnn")
	var runtime: Script = load("res://scripts/brain/mnn_runtime.gd")
	var needs := String(runtime.get_script_constant_map()["REQUIRES"])
	var tag := String(runtime.get_script_constant_map()["REQUIRES_TAG"])
	if not check(node, needs, tag):
		return null
	_ixmnn = node
	return _ixmnn


## TEST SEAM. Stands `node` in for the singleton, handshake and all, so a
## headless test can pin the on-device branch of every caller at once.
## Returns whether the handshake passed.
static func _attach_for_test(node: Object) -> bool:
	_ixmnn_asked = true
	_ixmnn = null
	if node == null:
		return false
	var runtime: Script = load("res://scripts/brain/mnn_runtime.gd")
	var needs := String(runtime.get_script_constant_map()["REQUIRES"])
	var tag := String(runtime.get_script_constant_map()["REQUIRES_TAG"])
	if not check(node, needs, tag):
		return false
	_ixmnn = node
	return true


## Forgets the verdict, so the next [ixmnn] asks again. For tests only.
static func reset_for_test() -> void:
	_ixmnn = null
	_ixmnn_asked = false
