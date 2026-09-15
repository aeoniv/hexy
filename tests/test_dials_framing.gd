extends SceneTree

const HexyApp = preload("res://scenes/hexy.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = HexyApp.instantiate()
	root.add_child(app)
	root.size = Vector2i(720, 1600)
	var front = app.get_node("Hud")
	await process_frame
	await process_frame
	
	assert(front._creature != null, "Front must have creature")
	var cam_front = front._creature.camera.position
	assert(cam_front.z > 5.0, "Front cam should be distant enough for radar")
	
	var dials = front.open_dials()
	await process_frame
	await process_frame
	
	assert(dials._creature != null, "Dials must have lent creature")
	assert(dials._creature.get_parent() == dials.view, "Creature must be child of dials view")
	var cam_dials = dials._creature.camera.position
	assert(cam_dials.z < 5.0, "Dials cam should be framed close to body dial")
	
	front.close_dials()
	await process_frame
	await process_frame
	
	assert(front._creature.get_parent() == front.view, "Creature must return to front view")
	var cam_back = front._creature.camera.position
	assert(absf(cam_back.z - cam_front.z) < 0.1, "Front cam must return to front framing")
	
	print("PASS: test_dials_framing passed all assertions.")
	app.queue_free()
	quit(0)
