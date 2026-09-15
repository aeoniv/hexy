extends SceneTree

## THE FLY IS FED IN THE SHIPPING SCENE. The unit tests feed Character by hand
## and pass whether or not the app ever does; this boots hexy.tscn and checks
## the app builds the oracle, binds it, and ticks the homeostat, so a fly that
## is built and never fed cannot ship again.

var passes := 0
var failures := 0


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func _init() -> void:
	print("HEXY_TEST: fly boot wiring")
	var scene: PackedScene = load("res://scenes/hexy.tscn")
	var app: Node = scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var oracle: Node = app.get_node_or_null("Oracle")
	check(oracle != null, "HexyApp builds an Oracle child")
	check(oracle != null and oracle.get("store") != null, "the oracle is bound to the store")

	var store: Node = app.get_node_or_null("Store")
	check(store != null and store.has_method("get_character"), "the store hands out the character")
	var ch: Variant = store.get_character() if store != null else null
	check(ch != null and ch.has_method("get_fly_state"), "the character exposes get_fly_state")

	# Feed a few frames and one ticker beat, then the state must be populated.
	for i in 30:
		await process_frame
	if app.has_method("_on_tick"):
		app._on_tick()
	var fs: Dictionary = ch.get_fly_state() if ch != null else {}
	check(fs.has("heading_rad") and fs.has("dopamine") and fs.has("phase"), "get_fly_state carries heading, dopamine, phase after boot")
	check(oracle != null and float(oracle.get("solar_hour")) > 0.0, "the oracle read the clock")
	var last_tick: Variant = ch.get("_last_tick_ms") if ch != null else -1
	check(int(last_tick) >= 0, "the homeostat has been ticked by the app (got %s)" % str(last_tick))

	var hud: Node = app.get_node_or_null("Hud")
	var radar: Variant = hud.get("radar") if hud != null else null
	check(radar != null, "the glass mounted the calcium radar")
	check(radar != null and bool(radar.get("_fed")), "the radar has been fed a state at least once")

	var wmn: Node = app.get_node_or_null("Wmn")
	check(wmn != null and wmn.has_method("has_bus") and wmn.has_bus(), "the wmn has a bus attached at boot")

	print("=== FLY BOOT WIRING: passed %d, failed %d ===" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS ===")
	quit(0 if failures == 0 else 1)
