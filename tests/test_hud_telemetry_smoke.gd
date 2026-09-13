extends SceneTree

func _initialize() -> void:
	print("--- TESTING HUD TELEMETRY SMOKE ---")
	var main_scene = load("res://scenes/main.tscn")
	var node = main_scene.instantiate()
	root.add_child(node)
	
	# Wait for nodes to enter tree and ready
	await process_frame
	await process_frame
	
	var hud = node.get_node("HUD/MobileHUD")
	assert(hud != null, "HUD must exist")
	
	print("Switching to telemetry mode...")
	hud._switch_mode("telemetry")
	print("Telemetry thought text:")
	print(hud.lbl_thought.text)
	assert(hud.lbl_thought.text.contains("8x8 SENSOR-HABIT SYNERGY TELEMETRY"), "Must contain telemetry")
	assert(hud.lbl_thought.text.contains("WIRELESS MESH NETWORK"), "Must contain WMN text")
	
	print("Testing send_mesh_ping...")
	hud.send_mesh_ping()
	print("Last mesh event: ", hud.last_mesh_event)
	assert(hud.last_mesh_event.contains("Broadcast ping"), "Must have ping event")
	
	print("Testing oracle cast...")
	hud._switch_mode("companion")
	hud._on_cast_pressed()
	print("Last mesh event after cast: ", hud.last_mesh_event)
	assert(hud.last_mesh_event.contains("oracle_cast"), "Must have oracle_cast event")
	
	print("=== HUD TELEMETRY SMOKE TEST PASS ===")
	quit()
