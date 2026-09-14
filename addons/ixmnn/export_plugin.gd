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
