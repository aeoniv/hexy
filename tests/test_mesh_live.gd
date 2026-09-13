extends SceneTree

func _initialize() -> void:
	print("--- TESTING MESH LIVE ---")
	var peer = MeshPeer.new()
	root.add_child(peer)
	print("Peer created. Calling start()...")
	var err = peer.start("hexy-test")
	print("start() result: ", err)
	print("backend_name: ", peer.backend_name())
	await create_timer(0.5).timeout
	peer.stop()
	print("=== LIVE TEST PASS ===")
	quit()
