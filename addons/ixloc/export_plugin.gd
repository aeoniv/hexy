@tool
extends EditorPlugin

## Ships the location AAR (built from `android_plugin/ixloc`) into the Android
## export, declares its Maven dependency (play-services-location) so Godot's own
## Gradle build resolves it, and declares the location permissions. Runtime half
## is `scripts/social/geo.gd`, which falls back to HEXY_LAT/HEXY_LON off Android.

var _export_plugin: IxLocExportPlugin

func _enter_tree() -> void:
	_export_plugin = IxLocExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class IxLocExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "IxLoc"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["ixloc/bin/debug/ixloc-debug.aar"])
		return PackedStringArray(["ixloc/bin/release/ixloc-release.aar"])

	## Without this, Godot's Gradle bundles only the plugin's own classes and
	## FusedLocationProvider is missing at runtime — the same trap IxMesh
	## documents for Nearby.
	func _get_android_dependencies(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"com.google.android.gms:play-services-location:21.3.0",
			"androidx.core:core-ktx:1.15.0",
		])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"https://maven.google.com",
			"https://repo1.maven.org/maven2",
		])

	## THE ONE PLACE ACCESS_FINE_LOCATION IS DECLARED, and it is declared
	## uncapped.
	##
	## It used to be declared only by addons/ixmesh with
	## android:maxSdkVersion="32", because Nearby Connections needs location
	## below API 33 and not above it. The manifest merger merges attributes as
	## well as names, so on both test phones (API 33 and 34) the merged manifest
	## carried FINE capped away: the app could only ever hold COARSE, the fused
	## provider had no reason to light the GNSS chip, every fix came back as a
	## cell/wifi centroid at acc≈2000 m, and Geo.is_placeable() (50 m) was false
	## for all time. That single attribute is why the radar never showed a
	## bearing or a distance on device.
	##
	## Location is this plugin's whole job, so the declaration lives here and
	## nowhere else — one uncapped `<uses-permission>` needs no `tools:replace`
	## or `tools:remove`, because there is no second declaration to merge with.
	## COARSE stays declared beside it: the runtime asks for both and a user who
	## grants only "approximate" gets exactly the pre-Phase-3 behaviour instead
	## of an error.
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return """
		<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
		<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
		"""
