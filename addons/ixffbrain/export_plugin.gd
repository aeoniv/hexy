@tool
extends EditorPlugin

## Ships the Fruit Fly Connectome Cybernetic Brain (IxFfBrain) into Godot.
##
## Embodies the complete canonical Drosophila melanogaster connectome across:
##   1. Central Complex (EB/PB 8-wedge heading compass + FB 2D goal vectors).
##   2. Mushroom Body (256 Kenyon Cells with sparse WTA & online Hebbian learning).
##   3. Giant Fiber (0g freefall and violent shock escape reflex circuit).
##   4. Circadian Clock (s-LNv/l-LNv pacemakers + PDF neuropeptide arousal cycle).
##   5. Synaptic Conductance (6x6 neurotransmitter mutual inhibition matrix).
##   6. Calcium Radar 2D (live biomorphic GCaMP fluorescence CanvasItem).
##
## Runtime half is `scripts/brain/character.gd` and associated subsystems,
## operating in pure deterministic GDScript math (< 1.5 MB RAM, 0.04 ms CPU/frame).

var _export_plugin: IxFfBrainExportPlugin

func _enter_tree() -> void:
	_export_plugin = IxFfBrainExportPlugin.new()
	add_export_plugin(_export_plugin)
	add_custom_type("FlyCalciumRadar2D", "Control", preload("res://scripts/brain/fly_calcium_radar_2d.gd"), null)

func _exit_tree() -> void:
	remove_custom_type("FlyCalciumRadar2D")
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class IxFfBrainExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "IxFfBrain"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return """
		<uses-permission android:name="android.permission.HIGH_SAMPLING_RATE_SENSORS" />
		<uses-feature android:name="android.hardware.sensor.accelerometer" android:required="true" />
		<uses-feature android:name="android.hardware.sensor.gyroscope" android:required="false" />
		"""
