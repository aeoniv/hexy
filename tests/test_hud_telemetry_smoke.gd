extends SceneTree

## HUD TELEMETRY SMOKE, against the scene that actually ships.
##
## This used to boot scenes/main.tscn and scripts/mobile_hud.gd, a second scene
## graph that nothing loaded. The shipping surface is scenes/hexy.tscn ->
## scripts/glass/app.gd -> Hud3, so that is what gets smoked here: the status
## strip, the telemetry panel, and the connectome panel that now reads the one
## fly brain through the character.

func _initialize() -> void:
	print("--- TESTING HUD TELEMETRY SMOKE ---")
	var main_scene = load("res://scenes/hexy.tscn")
	var node = main_scene.instantiate()
	root.add_child(node)

	await process_frame
	await process_frame

	var hud = node.get_node("Hud")
	assert(hud != null, "Hud3 must exist under the app")

	print("Status: ", hud.status_text())
	assert(hud.status_text().length() > 0, "Status strip must say something")

	var telem: String = hud.telemetry_text()
	print("Telemetry text:")
	print(telem)
	assert(telem.length() > 0, "Telemetry text must not be empty")

	var brain: String = hud.brain_text()
	print("Brain text:")
	print(brain)
	assert(brain.contains("BRAIN & CONNECTOME"), "Brain panel must have its heading")
	assert(brain.contains("DROSOPHILA CONNECTOME"), "Brain panel must reach the one fly brain")
	assert(brain.contains("EB/PB compass"), "Brain panel must print the compass heading")
	assert(brain.contains("giant fiber"), "Brain panel must print the giant fiber")

	print("Config text:")
	print(hud.config_text())
	assert(hud.config_text().contains("HEXY CONFIG"), "Config panel must have its heading")

	print("=== HUD TELEMETRY SMOKE TEST PASS ===")
	quit()
