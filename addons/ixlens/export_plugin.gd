@tool
extends EditorPlugin

## Ships the lens AAR (built from `android_plugin/ixlens`) into the Android
## export and declares its one Maven dependency so Godot's own Gradle build
## resolves it. Runtime half is `scripts/lens/lens_sense.gd`, which falls back to
## `scripts/lens/mock_lens.gd` off Android — and says "mock" while it does.

var _export_plugin: IxLensExportPlugin

func _enter_tree() -> void:
	_export_plugin = IxLensExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class IxLensExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "IxLens"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["ixlens/bin/debug/ixlens-debug.aar"])
		return PackedStringArray(["ixlens/bin/release/ixlens-release.aar"])

	## ONE DEPENDENCY, and the version must match
	## android_plugin/ixlens/build.gradle.kts exactly. There is deliberately no
	## CameraX here: ARCore owns the camera for itself while a session is open,
	## which is the whole reason LensSense refuses to start over ixbody or a
	## rolling rig. Two camera stacks pulled into one APK by one module is
	## exactly the fight the contention law exists to prevent.
	func _get_android_dependencies(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"com.google.ar:core:1.48.0",
			"androidx.core:core-ktx:1.15.0",
		])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"https://maven.google.com",
			"https://repo1.maven.org/maven2",
		])

	## THIS PLUGIN DECLARES NO PERMISSION, DELIBERATELY.
	##
	## android.permission.CAMERA is declared in addons/ixbody/export_plugin.gd
	## and nowhere else — ixcap says the same thing in the same words. The
	## manifest merger merges ATTRIBUTES as well as names, so a second
	## declaration here, even an identical one, is one refactor away from being
	## the bug that capped ACCESS_FINE_LOCATION at API 32 and cost Phase 3 a
	## release. The lens uses the back camera and body sense the front, but it is
	## ONE Android permission and it has ONE home.
	##
	## THE `com.google.ar.core` META-DATA IS NOT HERE EITHER, and this time that
	## IS an omission with a home: it lives in the AAR's own
	## `android_plugin/ixlens/src/main/AndroidManifest.xml`, where it is merged
	## in, and the reasoning is written out there.
	##
	## It used to be nowhere, on the ruling that declaring ARCore would make a
	## store listing refuse every uncertified phone — and the A22 is one, and
	## hexy runs on the A22. That is true of `value="required"`. It is the
	## opposite of true for `value="optional"`, which gates nothing and is what
	## `ArCoreApk.checkAvailability` REQUIRES to exist before it will answer at
	## all: without it the call throws rather than returning a state, and the
	## seam reads the throw as "no lens". A certified Fold spent a day that way.
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return ""
