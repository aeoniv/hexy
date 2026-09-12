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
## carries a `const NEEDS` with the string it was written against. At attach, and
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
