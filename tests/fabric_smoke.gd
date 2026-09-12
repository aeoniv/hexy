extends SceneTree
## Three fabrics in a line: A --T1-- B --T2-- C. A and C use disjoint session
## tokens, so they never discover each other; the only way an event from A can
## reach C is B relaying it. Proves multi-hop delivery, ttl decrement, no
## echo back to the origin, and dedup killing the loop.
##
## B is a single fabric holding TWO transports — that is how one node bridges
## two link-local meshes, exactly what a phone in the middle of a room does.

const MeshFabric = preload("res://scripts/net/mesh_fabric.gd")
const Envelope = preload("res://scripts/net/event_envelope.gd")

var _fails := 0
## EVERY CHECK IS COUNTED. A compile error in a depended script makes a whole
## section skip silently, and a suite that prints ALL PASS because it ran nothing
## is worse than a red one. Raise this floor when checks are added.
const MIN_CHECKS := 19
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		printerr("FAIL ", what)


func _initialize() -> void:
	var stamp := Time.get_ticks_usec()
	var t1 := "fab1-%d" % stamp
	var t2 := "fab2-%d" % stamp

	var a := MeshFabric.new()
	var b := MeshFabric.new()
	var c := MeshFabric.new()
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)
	a.add_transport(t1)
	b.add_transport(t1)
	b.add_transport(t2)
	c.add_transport(t2)
	_check(a.start("alpha") == OK, "alpha transport up")
	_check(b.start("bravo") == OK, "bravo bridges two transports")
	_check(c.start("charlie") == OK, "charlie transport up")
	_check(b.transport_count() == 2, "bravo holds two transports")

	var got_a: Array[Dictionary] = []
	var got_b: Array[Dictionary] = []
	var got_c: Array[Dictionary] = []
	a.envelope_received.connect(func(e): got_a.append(e))
	b.envelope_received.connect(func(e): got_b.append(e))
	c.envelope_received.connect(func(e): got_c.append(e))

	await _wait(5.0, func(): return a.peer_count() >= 1 and c.peer_count() >= 1 \
		and b.peer_count() >= 2)
	_check(a.peer_count() == 1, "alpha sees only bravo")
	_check(c.peer_count() == 1, "charlie sees only bravo")
	_check(b.peer_count() == 2, "bravo sees alpha and charlie")

	var env := a.emit_event("greet", {"msg": "from-a"}, 3)
	await _wait(3.0, func(): return got_c.size() > 0)
	_check(got_b.size() == 1, "bravo received the event once")
	_check(got_c.size() == 1, "charlie received it via bravo's relay (two hops)")
	if got_c.size() == 1:
		_check(got_c[0]["src"] == a.fabric_id, "src still names alpha after the relay")
		_check(got_c[0]["kind"] == "greet" and got_c[0]["body"]["msg"] == "from-a",
			"payload intact across the hop")
		_check(got_c[0]["prov"] == Envelope.PROV_SELF, "provenance is self")
		_check(Envelope.ttl_of(got_b[0]) == 3, "bravo saw ttl 3")
		_check(Envelope.ttl_of(got_c[0]) == 2, "charlie saw ttl 2 — decremented once")

	# Bravo rebroadcasts on the transport it arrived on too; alpha must drop
	# its own event rather than deliver it back to itself.
	_check(got_a.is_empty(), "alpha never receives its own event back")

	# Replaying the identical envelope changes nothing: dedup is on eid, and
	# the transport reminted the seq, so only the seen-set can stop this.
	a._send(env)
	await _wait(1.5, func(): return false)
	_check(got_b.size() == 1 and got_c.size() == 1, "replayed eid deduped everywhere")

	# TTL floor: a one-hop event dies at bravo.
	a.emit_event("near", {}, 1)
	await _wait(1.5, func(): return false)
	_check(got_b.size() == 2, "bravo got the ttl-1 event")
	_check(got_c.size() == 1, "ttl exhausted — charlie never sees it")

	# Witnessing carries provenance outward, unchanged, in both directions.
	b.witness("rep", {"what": "squat"}, 2)
	await _wait(3.0, func(): return got_a.size() > 0 and got_c.size() > 1)
	_check(got_a.size() == 1 and got_a[0]["prov"] == Envelope.PROV_WITNESSED,
		"alpha received a witnessed event")
	_check(got_c.size() == 2 and got_c[-1]["prov"] == Envelope.PROV_WITNESSED,
		"charlie received the same witnessed event")
	_check(got_a[0]["src"] == b.fabric_id, "witness names bravo as origin")

	a.stop()
	b.stop()
	c.stop()
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
