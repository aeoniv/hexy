extends SceneTree

## HUD TELEMETRY SMOKE, against the scene that actually ships.
##
## This used to boot scenes/main.tscn and scripts/mobile_hud.gd, a second scene
## graph that nothing loaded. The shipping surface is scenes/hexy.tscn ->
## scripts/glass/app.gd -> Front, and the three dials are a PAGE behind that
## front: so the page is opened the way a finger opens it and the words are
## read off it -- the captions, the telemetry panel, and the connectome panel
## that reads the one fly brain through the character.

func _initialize() -> void:
	print("--- TESTING HUD TELEMETRY SMOKE ---")
	var main_scene = load("res://scenes/hexy.tscn")
	var node = main_scene.instantiate()
	root.add_child(node)

	await process_frame
	await process_frame

	var front = node.get_node("Hud")
	assert(front != null, "the front must exist under the app")
	var hud = front.open_dials()
	await process_frame
	assert(hud != null and hud is Hud3, "open_dials must put the dials page up")

	print("Figures: ", hud.figures_phrase())
	assert(hud.figures_phrase().length() > 0, "the captions must say something")
	assert(hud.head_cap.text.contains("HEAD"), "the head dial carries its own caption")
	assert(hud.body_cap.text.contains("BODY"), "the body dial carries its own caption")
	assert(hud.earth_cap.text.contains("EARTH"), "the earth dial carries its own caption")

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
