@tool
extends EditorPlugin

## Ships the mesh AAR (built from `android_plugin/ixmesh`) into the Android
## export, declares its Maven dependency (play-services-nearby) so Godot's own
## Gradle build resolves it, and declares the Nearby permissions. Runtime half
## is `scripts/net/mesh_peer.gd`, which falls back to LanMesh off Android.

var _export_plugin: IxMeshExportPlugin

func _enter_tree() -> void:
	_export_plugin = IxMeshExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class IxMeshExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "IxMesh"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["ixmesh/bin/debug/ixmesh-debug.aar"])
		return PackedStringArray(["ixmesh/bin/release/ixmesh-release.aar"])

	## Without this, Godot's Gradle bundles only the plugin's own classes and
	## Nearby Connections is missing at runtime — the trap the avatar repo's
	## brain plugin hit with MediaPipe.
	func _get_android_dependencies(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"com.google.android.gms:play-services-nearby:19.3.0",
			"androidx.core:core-ktx:1.15.0",
		])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"https://maven.google.com",
			"https://repo1.maven.org/maven2",
		])

	## Nearby Connections needs the full radio set. It does NOT declare
	## ACCESS_FINE_LOCATION, and that omission is the whole geolocation fix.
	##
	## This plugin used to declare it with android:maxSdkVersion="32" (Nearby
	## only needs location below API 33). The manifest merger takes the union of
	## the *attributes* too, so on an API 33+ phone the merged manifest carried a
	## capped FINE permission — the OS dropped it, the app could only ever hold
	## COARSE, FusedLocationProvider answered with cell/wifi centroids at
	## acc≈2000 m, Geo.is_placeable() was permanently false, and every peer sat on
	## the radar's "direction unknown" ring. Two phones on one table, no bearing,
	## no distance, forever.
	##
	## So FINE is declared in exactly one place — addons/ixloc/export_plugin.gd —
	## uncapped, for every API level. That covers Nearby's own pre-33 need as
	## well: one uncapped declaration is strictly more permissive than a capped
	## one, and IxMesh.requiredPermissions() still only *asks* for FINE below
	## API 31, so nothing about the Nearby flow changes on a modern phone.
	## (Verified at API 35 on a Fold 4: Nearby needs the neverForLocation
	## Bluetooth flags, not location.)
	##
	## The neverForLocation flags are load-bearing, not decoration: without them
	## Nearby rejects startDiscovery() on Android 13+ with
	## MISSING_PERMISSION_ACCESS_COARSE_LOCATION (verified on a Fold 4, API 35).
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform,
			_debug: bool) -> String:
		return """
		<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
		<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
		<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
			android:usesPermissionFlags="neverForLocation" />
		<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
		<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
		<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
			android:usesPermissionFlags="neverForLocation" />
		"""
