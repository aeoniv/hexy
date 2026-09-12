extends SceneTree
## Two LanMesh nodes in one process discover each other over loopback UDP and
## deliver an event both ways, with dedup. Prints === ALL PASS === or fails.

const LanMesh = preload("res://scripts/net/lan_mesh.gd")

var _fails := 0
## EVERY CHECK IS COUNTED. A compile error in a depended script makes a whole
## section skip silently, and a suite that prints ALL PASS because it ran nothing
## is worse than a red one. Raise this floor when checks are added.
const MIN_CHECKS := 5
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		printerr("FAIL ", what)


func _initialize() -> void:
	var a := LanMesh.new()
	var b := LanMesh.new()
	root.add_child(a)
	root.add_child(b)
	# A unique per-run token isolates this pair from any other hexy
	# instances (or phones) that may be beaconing on the same LAN ports,
	# so the test's peer set and event counts can't be polluted from
	# outside the test.
	var token := "test-%d" % Time.get_ticks_usec()
	_check(a.start("alpha", token) == OK, "alpha binds a port")
	_check(b.start("beta", token) == OK, "beta binds a second port")
	var got_a := {}
	var got_b := {}
	a.event_received.connect(func(id, d): got_a[d.get("msg", "")] = id)
	b.event_received.connect(func(id, d): got_b[d.get("msg", "")] = id)
	await _wait(3.0, func(): return a.peer_count() > 0 and b.peer_count() > 0)
	_check(a.peer_count() == 1, "alpha discovered beta")
	_check(b.peer_count() == 1, "beta discovered alpha")
	a.broadcast({"msg": "hi-from-a"})
	b.broadcast({"msg": "hi-from-b"})
	await _wait(2.0, func(): return got_a.has("hi-from-b") and got_b.has("hi-from-a"))
	_check(got_b.has("hi-from-a"), "event a->b delivered")
	_check(got_a.has("hi-from-b"), "event b->a delivered")
	var before := got_b.size()
	a._seq -= 1
	a.broadcast({"msg": "hi-from-a"})
	await _wait(1.0, func(): return false)
	_check(got_b.size() == before, "duplicate seq deduped")
	print("checks: ", _checks, " (floor ", MIN_CHECKS, ")")
	if _checks < MIN_CHECKS:
		_fails += 1
		printerr("FAIL only ", _checks, " checks ran; the floor is ", MIN_CHECKS)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


func _wait(seconds: float, done: Callable) -> void:
	var t := 0.0
	while t < seconds and not done.call():
		await process_frame
		t += 1.0 / 60.0
