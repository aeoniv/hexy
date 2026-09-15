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
const MIN_CHECKS := 30
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
	# The LAN backend reports loopback peers as "touch"; once the first-hand
	# envelope has named bravo, the class is filed under bravo's FABRIC id, which
	# is the key the radar plots by.
	var prox: Dictionary = a.peer_proximity_by_src()
	_check(prox.is_empty() or prox.values().all(func(v): return v in ["touch", "room", "far"]),
		"proximity by src only ever says touch/room/far")
	_check(prox.keys().all(func(k): return not String(k).begins_with("fab")),
		"proximity by src is keyed by fabric id, never transport id")
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

	# THE BODY'S PLACE IN THE DAY AND THE STORY, on the wire beside the heading.
	# Pure payload first: nothing here needs a radio.
	var bare: Dictionary = MeshFabric.bio_payload(0.5, 0.5)
	_check(float(bare["phase"]) == -1.0, "a pulse from a body with no clock says phase -1")
	_check(int(bare["stage"]) == -1, "and stage -1, rather than claiming chapter zero")
	var said: Dictionary = MeshFabric.bio_payload(1.0, 0.5, [], PackedFloat32Array(), 0, 0.256, 3)
	_check(is_equal_approx(float(said["phase"]), 0.26), "phase is snapped to a hundredth of a day")
	_check(int(said["stage"]) == 3, "the stage rides through untouched")
	_check(is_equal_approx(float(said["heading"]), 1.0) and said.has("habit_bias"),
		"and the old payload is unchanged around it")
	_check(float(MeshFabric.bio_payload(0.0, 0.5, [], PackedFloat32Array(), 0, 0.999, 0)["phase"]) == 0.0,
		"a phase that snaps up to a whole day comes back round to midnight")
	_check(float(MeshFabric.bio_payload(0.0, 0.5, [], PackedFloat32Array(), 0, -0.3, 0)["phase"]) == -1.0,
		"a negative phase is unknown, not a time of day")
	_check(int(MeshFabric.bio_payload(0.0, 0.5, [], PackedFloat32Array(), 0, 0.5, -7)["stage"]) == -1,
		"and any negative stage is the one word for unknown")

	# The real pulse, over the wire, and what the reader makes of it.
	var got_bio: Array[Dictionary] = []
	b.fabric_event.connect(func(src, kind, body, _p):
		if kind == "fly_bio_pulse":
			got_bio.append({"src": src, "body": body}))
	a.broadcast_bio_state(0.25, 0.6, [], PackedFloat32Array(), 0, 0.75, 4)
	await _wait(3.0, func(): return not got_bio.is_empty())
	_check(not got_bio.is_empty(), "bravo heard alpha's bio pulse")
	if not got_bio.is_empty():
		var bod: Dictionary = got_bio[0]["body"]
		_check(is_equal_approx(float(bod["phase"]), 0.75), "the phase survived the hop")
		_check(int(bod["stage"]) == 4, "and so did the stage")
	var ph: Dictionary = b.peer_phase_by_src()
	_check(ph.has(a.fabric_id) and is_equal_approx(float(ph[a.fabric_id]), 0.75),
		"peer_phase_by_src files it under the fabric id the app names them by")
	_check(int(b.peer_stage_by_src().get(a.fabric_id, -1)) == 4,
		"and peer_stage_by_src the same")
	a.broadcast_bio_state(0.25, 0.6)
	await _wait(3.0, func(): return not b.peer_phase_by_src().has(a.fabric_id))
	_check(not b.peer_phase_by_src().has(a.fabric_id),
		"a later pulse that says nothing takes the phase off the dial rather than freezing it")
	_check(not b.peer_stage_by_src().has(a.fabric_id), "and the stage with it")

	# A LOST PEER LEAVES NO PROXIMITY BEHIND. Bravo's link to alpha's transport
	# goes down; the fabric id it was filed under must fall out of
	# peer_proximity_by_src too, or a radar polling it would keep drawing a
	# blip for someone who is no longer there.
	var alpha_fid: String = a.fabric_id
	_check(b.peer_proximity_by_src().has(alpha_fid),
		"bravo has alpha's proximity class before the link drops")
	a.stop()
	await _wait(12.0, func(): return not b.peer_proximity_by_src().has(alpha_fid))
	_check(not b.peer_proximity_by_src().has(alpha_fid),
		"a lost peer's proximity class is gone, not resurrected under its fabric id")
	_check(not b.peer_headings.has(alpha_fid) and not b.peer_bio.has(alpha_fid),
		"a lost peer's heading and bio pulse are gone too")

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
