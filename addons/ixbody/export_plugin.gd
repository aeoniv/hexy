@tool
extends EditorPlugin

## Ships the body-sense AAR (built from `android_plugin/ixbody`) into the
## Android export, declares its Maven dependencies so Godot's own Gradle build
## resolves them, and declares the camera permission. Runtime half is
## `addons/hexy_eye/`, which falls back to a mock off Android.

var _export_plugin: IxBodyExportPlugin

func _enter_tree() -> void:
	_export_plugin = IxBodyExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class IxBodyExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "IxBody"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["ixbody/bin/debug/ixbody-debug.aar"])
		return PackedStringArray(["ixbody/bin/release/ixbody-release.aar"])

	## Without these, Godot's Gradle bundles only the plugin's own classes and
	## every MediaPipe and CameraX symbol is missing at runtime — the same trap
	## ixmesh documents for Nearby and ixloc for FusedLocationProvider. The
	## versions must match android_plugin/ixbody/build.gradle.kts exactly:
	## compiling against one MediaPipe and running against another is a
	## NoSuchMethodError nothing catches at build time.
	func _get_android_dependencies(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"com.google.mediapipe:tasks-vision:0.10.14",
			"androidx.camera:camera-core:1.4.1",
			"androidx.camera:camera-camera2:1.4.1",
			"androidx.camera:camera-lifecycle:1.4.1",
			"androidx.core:core-ktx:1.15.0",
		])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"https://maven.google.com",
			"https://repo1.maven.org/maven2",
		])

	## THE ONE PLACE android.permission.CAMERA IS DECLARED.
	##
	## Same rule ixloc's ACCESS_FINE_LOCATION comment spells out at length: the
	## manifest merger merges attributes as well as names, so a second
	## declaration anywhere — with a maxSdkVersion, a tools:node, anything —
	## silently changes what the merged manifest asks for, and no source file
	## shows the result. The camera is this plugin's whole job, so it is
	## declared here, uncapped, once.
	##
	## Declaring the permission is not the same as holding it. IxBody.start()
	## requests it at runtime through Godot's own helper, the FIRST time a
	## person presses the workshop's camera toggle and never before — a
	## permission dialog that appears at launch is a companion asking to watch
	## you before you asked it to.
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return """
		<uses-permission android:name="android.permission.CAMERA" />
		"""
