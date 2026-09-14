extends SceneTree
## The WMN core, proved without a phone in the room.
##
## Five sections. Four of them are pure and deterministic -- the envelope, the
## clock, the ledger and the room never touch a socket -- and the fifth puts two
## real Wmn nodes on loopback UDP, because the one thing a pure test cannot
## prove is that the composition over MeshFabric is wired the right way round.

const HexyStoreScript = preload("res://scripts/core/store.gd")
const WmnScript = preload("res://scripts/core/wmn/wmn.gd")

const LEDGER_PATH := "user://test_wmn_ledger.json"

var _fails := 0
## EVERY CHECK IS COUNTED. A compile error in a depended script makes a whole
## section skip silently, and a suite that prints ALL PASS because it ran
## nothing is worse than a red one. Raise this floor when checks are added.
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
	print("\n--- TEST CORE WMN ---")
	_test_envelope6()
	_test_chirp_clock()
	_test_ledger()
	_test_room()
	_test_presence()
	await _test_loopback()

	print("checks: ", _checks, " (floor ", MIN_CHECKS, ")")
	if _checks < MIN_CHECKS:
		_fails += 1
		printerr("FAIL only ", _checks, " checks ran; the floor is ", MIN_CHECKS)
	if _fails == 0:
		print("=== ALL PASS ===")
	else:
		printerr("=== ", _fails, " FAILED ===")
	quit(0 if _fails == 0 else 1)


# --- 1. the one-byte word ---------------------------------------------------

func _test_envelope6() -> void:
	var bad_head := 0
	var bad_payload := 0
	var bad_len := 0
	for kind in range(4):
		for bits in range(64):
			var payload := {"moving": bits ^ 63, "n": kind, "who": "a-b_c"}
			var raw := Envelope6.pack(kind, bits, payload)
			if int(raw[0]) != ((kind << 6) | bits):
				bad_head += 1
			var got := Envelope6.unpack(raw)
			if int(got["kind"]) != kind or int(got["bits"]) != bits:
				bad_head += 1
			if not _same_payload(got["payload"], payload):
				bad_payload += 1
			var wired := Envelope6.from_wire(Envelope6.to_wire(kind, bits, payload))
			if int(wired["kind"]) != kind or int(wired["bits"]) != bits \
					or not _same_payload(wired["payload"], payload):
				bad_payload += 1
			if Envelope6.pack(kind, bits, {}).size() != 1:
				bad_len += 1
	_check(bad_head == 0, "Envelope6 head round trips 64 figures x 4 kinds")
	_check(bad_payload == 0, "Envelope6 payload round trips, raw and base64")
	_check(bad_len == 0, "a bare figure costs exactly one byte")
	var empty := Envelope6.unpack(PackedByteArray())
	_check(int(empty["bits"]) == 0 and (empty["payload"] as Dictionary).is_empty(),
		"an empty datagram unpacks to a zero figure, not an error")
	var truncated := PackedByteArray([(1 << 6) | 42, 0x41, 0x42])
	var t := Envelope6.unpack(truncated)
	_check(int(t["bits"]) == 42 and int(t["kind"]) == 1,
		"a truncated tail keeps the word in byte 0")
	_check(Envelope6.kind_name(Envelope6.KIND_FIGURE) == "figure"
		and Envelope6.kind_name(Envelope6.KIND_CHIRP) == "chirp",
		"the four kinds have names")


## JSON hands every number back as a float, so a payload that went out as ints
## comes back numerically equal and not identically typed. The wire promises
## the VALUES, which is what is compared here -- and it is why every reader in
## wmn.gd coerces with int() rather than trusting the parsed type.
func _same_payload(got: Variant, want: Dictionary) -> bool:
	if not (got is Dictionary):
		return false
	var g: Dictionary = got
	if g.size() != want.size():
		return false
	for k in want:
		if not g.has(k):
			return false
		if want[k] is int:
			if int(g[k]) != int(want[k]):
				return false
		elif String(g[k]) != String(want[k]):
			return false
	return true


# --- 2. the room clock ------------------------------------------------------

func _test_chirp_clock() -> void:
	var c := ChirpClock.new()
	const OFFSET := 12345
	# A four-timestamp exchange with a slightly lopsided flight each way.
	for i in range(9):
		var t1 := 1000 + i * 100
		var out_leg := 20 + (i % 3)
		var back_leg := 20 - (i % 3)
		var t2 := t1 + out_leg + OFFSET
		var t3 := t2 + 5
		var t4 := t3 - OFFSET + back_leg
		c.note(t3, t4, t2, t1)
	_check(absi(c.offset_ms() - OFFSET) <= 2,
		"clock converges to a known offset (got %d, want %d)" % [c.offset_ms(), OFFSET])
	# Two phones whose radios stalled. The median must not hand the stall on.
	c.note(0, 0, 0, 0)
	c.note(99999, 0, 0, 0)
	_check(absi(c.offset_ms() - OFFSET) <= 2,
		"two wild samples do not move the median (got %d)" % c.offset_ms())
	_check(c.sample_count() == 11, "every sample is kept up to the cap")
	var one_way := ChirpClock.new()
	one_way.note(5000 + 700, 700)
	one_way.note(5000 + 800, 800)
	one_way.note(5000 + 900, 900)
	_check(one_way.offset_ms() == 5000, "a one-way beacon still estimates an offset")
	var near := ChirpClock.new()
	near.note(100, 100, 100, 100)
	_check(near.now_ms() - Time.get_ticks_msec() == near.offset_ms(),
		"now_ms is the local tick plus the offset")
	c.clear()
	_check(c.offset_ms() == 0 and c.sample_count() == 0, "a cleared clock is at zero")


# --- 3. the ledger ----------------------------------------------------------

func _test_ledger() -> void:
	var l := Ledger.new()
	var h := {"bits": 42, "moving": 5, "throws": [9, 8, 7, 8, 9, 8],
		"when": 1700000000000, "who": "alpha", "source": "tap", "sig": ""}
	var id := l.append(h, ["bravo"])
	_check(id.length() == 64, "the id is a sha256 hex digest")
	_check(id == Ledger.id_of(h), "the id is a pure function of the cast")
	_check(l.append(h.duplicate(true), []) == id and l.size() == 1,
		"the same cast appended twice is one entry")
	var other := h.duplicate(true)
	other["sig"] = "a-signature"
	_check(l.append(other, []) == id, "a signature does not rename a cast")
	other = h.duplicate(true)
	other["when"] = 1700000000001
	_check(l.append(other, []) != id and l.size() == 2,
		"a different millisecond is a different cast")

	_check(l.witness(id, "charlie", "sig-c"), "a witness is recorded")
	_check(not l.witness("nope", "charlie", ""), "an unknown id cannot be witnessed")
	_check(l.witnesses_of(id) == ["bravo", "charlie"], "witnesses come back sorted")
	l.witness(id, "charlie", "")
	_check(String((l.get_cast(id)["witnesses"] as Dictionary)["charlie"]) == "sig-c",
		"an unsigned witness never overwrites a signature")
	_check(l.verify(id), "a well-formed entry verifies")
	_check(l.verify_all(), "the whole ledger verifies")
	_check(not l.verify("nope"), "an unknown id does not verify")

	_check(l.save(LEDGER_PATH) == OK, "the ledger saves")
	var back := Ledger.new()
	_check(back.load_file(LEDGER_PATH) == OK, "the ledger loads")
	_check(back.size() == l.size(), "save and load keep every entry")
	_check(back.get_cast(id) == l.get_cast(id), "an entry survives the round trip")
	_check(back.witnesses_of(id) == ["bravo", "charlie"], "witnesses survive too")
	_check(back.verify_all(), "the reloaded ledger verifies")

	# A file edited behind the ledger back is exactly what the structural
	# check exists for.
	var tampered: Dictionary = back.to_dict()
	(tampered["casts"] as Array)[0]["bits"] = 1
	var bent := Ledger.new()
	bent.from_dict(tampered)
	_check(not bent.has(id), "a tampered entry does not answer to the old id")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER_PATH))


# --- 4. the room ------------------------------------------------------------

func _test_room() -> void:
	var r := Room.new()
	r.set_peer("p1", 0b000111, 0, 1000)
	r.set_peer("p2", 0b001111, 0, 1000)
	r.set_peer("p3", 0b000011, 0, 1000)
	_check(r.peer_count() == 3, "three peers are in the room")
	var f := r.figure()
	_check(int(f["bits"]) == 0b000111,
		"the room figure is the per-line majority (got %d)" % int(f["bits"]))
	_check(r.names() == ["p1", "p2", "p3"], "peers come back sorted")
	_check(r.drifting().is_empty(), "nobody is drifting in an agreeing room")

	var r2 := Room.new()
	r2.set_peer("a", 0b000111, 0, 1000)
	r2.set_peer("b", 0b000111, 0, 1000)
	r2.set_peer("c", 0b000111, 0, 1000)
	r2.set_peer("far", 0b111000, 0, 1000)
	_check(int(r2.figure()["bits"]) == 0b000111, "one dissenter does not move the room")
	_check(r2.drifting() == ["far"],
		"a peer more than two hops out is drifting (got %s)" % str(r2.drifting()))

	r2.set_self(0b000111, 0, 1000)
	_check(r2.all_bits().size() == 5, "our own figure is counted in the room")
	_check(r2.peer_count() == 4, "but not counted as a peer")
	_check(not r2.drifting().has(Room.SELF_KEY), "we cannot drift from our own room")
	var store_room := r2.as_store_room()
	_check(int(store_room["bits"]) == 0b000111 and int(store_room["peers"]) == 4,
		"as_store_room is the shape HexyStore takes")

	# THE MAJORITY IS A HEAD COUNT, line by line, and a tie goes to yang.
	var maj := Room.new()
	maj.set_peer("a", 0b000111, 0, 1000)
	maj.set_peer("b", 0b000101, 0, 1000)
	maj.set_peer("c", 0b000001, 0, 1000)
	_check(maj.majority() == 0b000101,
		"a line more than half the room carries is yang (got %d)" % maj.majority())
	var tie := Room.new()
	tie.set_peer("a", 0b111000, 0, 1000)
	tie.set_peer("b", 0b000111, 0, 1000)
	_check(tie.majority() == 0b111111, "a tied line goes to yang")
	_check(Room.new().majority() == 0, "an empty room is the Receptive")

	var gone := r2.expire(1000 + Room.EXPIRY_MS + 1)
	_check(gone == ["a", "b", "c", "far"], "peers unheard for 30 s expire")
	_check(r2.has(Room.SELF_KEY), "we never expire ourselves")
	_check(r2.expire(1000).is_empty(), "a fresh room expires nobody")

	# A tie is settled by the SET, not by whoever happens to be listed first:
	# each phone lists itself first, so "the first peer" is a different person
	# on every device, and the room would quietly disagree with itself.
	var alpha := Room.new()
	alpha.set_self(0b111000, 0, 1000, "aaa")
	alpha.set_peer("zzz", 0b000111, 0, 1000)
	var beta := Room.new()
	beta.set_self(0b000111, 0, 1000, "zzz")
	beta.set_peer("aaa", 0b111000, 0, 1000)
	_check(alpha.all_ids() == ["aaa", "zzz"] and beta.all_ids() == ["aaa", "zzz"],
		"both phones read the room in the same id order")
	_check(alpha.figure() == beta.figure(),
		"two phones in one room cast ONE figure (a=%s b=%s)"
			% [str(alpha.figure()), str(beta.figure())])
	_check(int(alpha.figure()["bits"]) == 0b111000,
		"a tied line is taken from the smallest who")

	var solo := Room.new()
	solo.set_self(0b101010, 0, 1000, "solo")
	_check(int(solo.figure()["bits"]) == 0b101010, "a room of one is that one figure")
	_check(int(solo.figure()["moving"]) == 0,
		"one voice has nobody to be thin against, so nothing moves")


# --- 5. presence ------------------------------------------------------------

func _test_presence() -> void:
	_check(Presence.band(0) == "here" and Presence.band(4999) == "here",
		"a peer heard in the last five seconds is here")
	_check(Presence.band(6000) == "near" and Presence.band(14999) == "near",
		"a peer heard in the last fifteen seconds is near")
	_check(Presence.band(20000) == "gone" and Presence.band(-1) == "gone",
		"silence is gone")
	_check(Presence.band(1000, -95) == "near",
		"a weak signal demotes here to near, never the other way")
	_check(Presence.band(1000, -1) == "here",
		"an absent rssi changes nothing")
	var p := Presence.new()
	_check(p.due(100000), "the first beat is due at once")
	_check(not p.due(100001), "a second beat is not due a millisecond later")
	_check(p.due(100000 + Presence.HEARTBEAT_MS), "the next beat is due after two seconds")


# --- 6. two nodes on loopback ----------------------------------------------

func _test_loopback() -> void:
	var token := "wmn-%d" % Time.get_ticks_usec()
	var a: Node = WmnScript.new()
	var b: Node = WmnScript.new()
	a.session_token = token
	b.session_token = token
	a.force_lan = true
	b.force_lan = true
	a.keep_ledger = true
	b.keep_ledger = true
	root.add_child(a)
	root.add_child(b)
	var store_a: Node = HexyStoreScript.new()
	var store_b: Node = HexyStoreScript.new()
	root.add_child(store_a)
	root.add_child(store_b)

	_check(a.start("alpha") == OK, "alpha joins the mesh")
	_check(b.start("beta") == OK, "beta joins the mesh")
	_check(a.fabric_id() != b.fabric_id(), "two named instances are two people")
	a.bind(store_a)
	b.bind(store_b)

	var heard_a: Array[Dictionary] = []
	var heard_b: Array[Dictionary] = []
	a.peer_figure.connect(func(_w, h): heard_a.append(h))
	b.peer_figure.connect(func(_w, h): heard_b.append(h))

	await _wait(6.0, func(): return a.fabric.peer_count() >= 1 and b.fabric.peer_count() >= 1)
	var linked: bool = a.fabric.peer_count() >= 1 and b.fabric.peer_count() >= 1
	_check(linked, "the two nodes find each other on loopback")

	# TWO DIFFERENT FIGURES, one line apart. With two voices that line is a
	# tie, and a tie is now read off the id set rather than off whoever the
	# local phone happens to list first -- so disagreement is exactly the
	# state worth proving: both phones must still hold the SAME room.
	# BYTE 0 IS THE HEAD; the body rides in the payload beside it.
	store_a.set_head({"bits": 0b101101, "moving": 0b000100})
	var h := {"bits": 0b010010, "moving": 0b000100,
		"throws": [7, 8, 9, 7, 8, 7], "when": 1700000000000,
		"who": "alpha", "source": "tap", "sig": ""}
	store_a.set_hexagram(h)
	store_b.set_head({"bits": 0b100101, "moving": 0b000001})
	var hb := {"bits": 0b001001, "moving": 0b000001,
		"throws": [9, 8, 7, 8, 8, 7], "when": 1700000000001,
		"who": "beta", "source": "tap", "sig": ""}
	store_b.set_hexagram(hb)

	# Two broadcasts leave each phone: the head moving, then the body. Wait for
	# the one that carries both.
	await _wait(6.0, func(): return heard_a.size() >= 2 and heard_b.size() >= 2)
	_check(not heard_b.is_empty(), "beta hears alpha figure")
	_check(not heard_a.is_empty(), "alpha hears beta figure")
	if not heard_b.is_empty():
		var got: Dictionary = heard_b[heard_b.size() - 1]
		_check(int(got["bits"]) == 0b101101 and int(got["moving"]) == 0b000100,
			"byte 0 is alpha's HEAD, unchanged (got %d)" % int(got["bits"]))
		_check(int(got["body"]) == 0b010010 and int(got["body_moving"]) == 0b000100,
			"the payload carries alpha's BODY (got %d)" % int(got["body"]))
		_check(got["throws"] == [7, 8, 9, 7, 8, 7] and int(got["when"]) == 1700000000000,
			"the payload carries throws and when")
		_check(String(got["who"]) == "alpha" and String(got["source"]) == "tap",
			"the payload carries who and source")

	await _wait(3.0, func(): return int(store_a.room["peers"]) == 1 and int(store_b.room["peers"]) == 1)
	_check(store_a.room == store_b.room,
		"both stores hold the IDENTICAL room (a=%s b=%s)" % [str(store_a.room), str(store_b.room)])
	# Two heads, one line apart: the majority ties on it, and a tie is yang.
	_check(int(store_a.room["bits"]) == 0b101101,
		"the room's bits are the per-line majority over the HEADS (got %d)"
			% int(store_a.room["bits"]))
	_check(int(store_a.room["moving"]) == (0b101101 ^ 0b100101),
		"the one line the two disagree on is the one that moves (got %d)"
			% int(store_a.room["moving"]))
	_check(a.peer_count() == 1 and b.peer_count() == 1, "each sees exactly one peer")
	var row: Array = a.peers()
	_check(row.size() == 1 and String(row[0]["who"]) == b.fabric_id()
		and int(row[0]["rssi"]) == -1 and String(row[0]["band"]) == "here",
		"peers() names the peer, admits no rssi, and bands it here")
	_check(row.size() == 1 and int(row[0]["bits"]) == 0b100101
		and int(row[0]["body"]) == 0b001001,
		"a peer row carries their head AND their body")
	_check(row.size() == 1 and row[0].has("cls") and row[0].has("heading_rad"),
		"a peer row also carries cls and heading_rad -- who/where/which-way in one place")
	_check(String(row[0]["cls"]) in ["", "touch", "room", "far"],
		"cls is empty (unplaced) or one of touch/room/far (got %s)" % String(row[0]["cls"]))
	_check(row[0]["heading_rad"] == null or row[0]["heading_rad"] is float,
		"heading_rad is null (no bio pulse yet) or a float, never a guess")
	_check(a.ledger.size() >= 2, "the ledger kept our cast and the one we heard")

	# The chirps have been flying at 2 Hz since start(); by now the clock has
	# samples from a peer whose tick count is genuinely different from ours.
	await _wait(5.0, func(): return a.clock.sample_count() > 0 and b.clock.sample_count() > 0)
	_check(a.clock.sample_count() > 0, "alpha clock has heard a chirp")
	_check(b.clock.sample_count() > 0, "beta clock has heard a chirp")

	# The network-free door, proving the same path a datagram takes.
	var before: int = b.peer_count()
	b.ingest("ghost-peer", {"e6": Envelope6.to_wire(Envelope6.KIND_FIGURE, 0b011010,
		{"moving": 0, "body": 0b000001, "body_moving": 0,
		"throws": [7, 7, 7, 7, 7, 7], "when": 1, "who": "ghost",
		"source": "room", "sig": ""})})
	_check(b.peer_count() == before + 1, "an injected figure joins the room")
	_check(b.room.drifting().has("ghost-peer"),
		"a figure six hops out is drifting (got %s)" % str(b.room.drifting()))

	# Silence, not a goodbye, is what drops a peer -- expire() is the only
	# door, and peer_gone is Wmn's own signal for a radar to hang drop_peer off.
	var went_gone: Array[String] = []
	b.peer_gone.connect(func(who): went_gone.append(who))
	var ghost_before: int = b.peer_count()
	b.room.peers["ghost-peer"]["seen"] = b.now_ms() - Room.EXPIRY_MS - 1000
	b._process(0.0)
	_check(b.peer_count() == ghost_before - 1, "an unheard peer expires out of the room")
	_check(went_gone.has("ghost-peer"), "peer_gone names the one who went quiet")
	_check(not b.peers().any(func(p): return String(p["who"]) == "ghost-peer"),
		"a gone peer no longer has a row")

	a.stop()
	b.stop()
	a.queue_free()
	b.queue_free()
	store_a.queue_free()
	store_b.queue_free()


func _wait(seconds: float, done: Callable) -> void:
	var t := 0.0
	while t < seconds and not done.call():
		await process_frame
		t += 1.0 / 60.0
