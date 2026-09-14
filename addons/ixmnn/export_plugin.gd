@tool
extends EditorPlugin

## Ships the MNN AAR (built from `android_plugin/ixmnn`) into the Android
## export. Unlike the mesh plugin there is no Maven dependency to declare:
## MNN publishes no artifact at all, so its .so files ride inside this AAR's
## own jni/ folder. Runtime half is `scripts/brain/mnn_runtime.gd`.

var _export_plugin: IxMnnExportPlugin

func _enter_tree() -> void:
	_export_plugin = IxMnnExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class IxMnnExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "IxMnn"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["ixmnn/bin/debug/ixmnn-debug.aar"])
		return PackedStringArray(["ixmnn/bin/release/ixmnn-release.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray(["androidx.core:core-ktx:1.15.0"])

	## The fly brain (scripts/brain/fly_*.gd) reads the accelerometer and
	## gyroscope at high rate for the giant-fiber reflex and the heading ring.
	## It is native GDScript, not a plugin, so its manifest needs ride here.
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return """
		<uses-permission android:name="android.permission.HIGH_SAMPLING_RATE_SENSORS" />
		<uses-feature android:name="android.hardware.sensor.accelerometer" android:required="true" />
		<uses-feature android:name="android.hardware.sensor.gyroscope" android:required="false" />
		"""
