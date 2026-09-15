@tool
extends EditorPlugin

## Ships the voice AAR (built from `android_plugin/ixvoice`) into the Android
## export and declares the microphone permission. Runtime half is
## `scripts/voice/voice_sense.gd`, which falls back to a stub off Android.
##
## There is no Maven dependency to declare beyond core-ktx: `android.speech`
## is the platform, and this plugin ships no weights at all.

var _export_plugin: IxVoiceExportPlugin

func _enter_tree() -> void:
	_export_plugin = IxVoiceExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class IxVoiceExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "IxVoice"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["ixvoice/bin/debug/ixvoice-debug.aar"])
		return PackedStringArray(["ixvoice/bin/release/ixvoice-release.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"androidx.core:core-ktx:1.15.0",
		])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"https://maven.google.com",
			"https://repo1.maven.org/maven2",
		])

	## THE ONE PLACE android.permission.RECORD_AUDIO IS DECLARED.
	##
	## Same rule the CAMERA declaration in addons/ixbody spells out: the
	## manifest merger merges attributes as well as names, so a second
	## declaration anywhere — with a maxSdkVersion, a tools:node, anything —
	## silently changes what the merged manifest asks for and no source file
	## shows the result. The microphone is this plugin's whole job, so it is
	## declared here, uncapped, once.
	##
	## Declaring the permission is not the same as holding it. IxVoice's
	## start_listen() requests it at runtime, the FIRST time a person holds the
	## stage with VOICE on, and never before.
	##
	## AND THE ONE PLACE android.permission.VIBRATE IS DECLARED (Phase 13).
	## The six-pulse haptic codec lives in this same plugin (see Pulse.kt for
	## why), so its permission is declared beside the microphone's, here, once,
	## uncapped. It is a NORMAL permission: it is granted at install and there
	## is no runtime dialog and no consent switch in front of it — a buzz is not
	## a recording. `tools/patch_android_manifest.ps1` is NOT touched: that
	## script patches the export TEMPLATE's activity attributes (launchMode,
	## configChanges), which is a different manifest and a different problem;
	## permissions belong to the plugin that uses them.
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return """
		<uses-permission android:name="android.permission.RECORD_AUDIO" />
		<uses-permission android:name="android.permission.VIBRATE" />
		"""
