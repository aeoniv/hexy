extends SceneTree

## Headless checks for THE SEAT BUS: one wire, three seats, one writer each.
##
## Every gesture on the glass is ANNOUNCED on `store.note_seat` and the seat's
## own writer answers. The BODY re-anchors the cube (W10d: through a plain
## Pacing wired to seat_landed/restored, the same way app.gd does it now that
## alchemy.gd is deleted); the HEAD and the EARTH belong to the store and must
## never touch the cube at all. A restore is not a gesture, so it re-anchors
## the cube whole.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST SEAT BUS (three seats, one writer each) ---")

	_test_body_seat()
	_test_head_seat()
	_test_earth_seat()
	_test_restore_reanchors()
	_test_dump_round_trip()
	_test_legacy_dump()
	_test_one_signal_each()

	if failures == 0:
		print("--- ALL SEAT BUS TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- SEAT BUS TESTS FAILED: ", failures, " ---\n")
		quit(1)


class Rig:
	var store: HexyStore = null
	var senses: Senses = null
	var pacing: Pacing = null

	func _init() -> void:
		store = preload("res://scripts/core/store.gd").new() as HexyStore
		senses = Senses.new()
		senses.bind(store)
		pacing = Pacing.new()
		pacing.reset(store.body_bits())
		store.seat_landed.connect(_on_seat_landed)
		store.restored.connect(_on_restored)

	func _on_seat_landed(seat: int, c: Dictionary) -> void:
		if seat != HexyStore.Seat.BODY:
			return
		pacing.inject(int(c.get("bits", 0)) & 63, int(c.get("when", 0)))
		if not pacing.journal.is_empty():
			pacing.journal[pacing.journal.size() - 1]["source"] = String(c.get("source", "tap"))

	func _on_restored() -> void:
		pacing.reset(store.body_bits())

	func drop() -> void:
		store.free()
		senses.free()


# -- 1. the body seat --------------------------------------------------------

func _test_body_seat() -> void:
	print("\n[ the body: announced by the glass, written by the wired cube ]")
	var r := Rig.new()
	r.pacing.journal_clear()

	r.store.note_seat(HexyStore.Seat.BODY, {
		"bits": 0b010101, "moving": 0, "when": 1000,
		"who": "me", "source": "wheel", "seq_index": 7,
	})

	check(r.pacing.bits == 0b010101,
		"a wheel write reached the cube (got %d)" % r.pacing.bits)
	check(r.store.body_bits() == 0b010101, "and the store body holds it")
	check(String(r.store.body.get("source", "")) == "wheel",
		"the body kept its source 'wheel', not coerced to 'tap'")
	check(int(r.store.body.get("seq_index", -1)) == 7,
		"and the seat it was walked to (got %d)" % int(r.store.body.get("seq_index", -1)))

	var last: Dictionary = r.pacing.journal[r.pacing.journal.size() - 1]
	check(String(last.get("op", "")) == "inject", "the journal records an inject")
	check(String(last.get("source", "")) == "wheel",
		"and the journal preserved the source (got '%s')" % String(last.get("source", "")))

	r.drop()


# -- 2. the head seat --------------------------------------------------------

func _test_head_seat() -> void:
	print("\n[ the head: free, and no cube ]")
	var r := Rig.new()
	var before: int = r.pacing.bits
	var body_hits: Array[int] = [0]
	r.store.body_changed.connect(func(_b: Dictionary) -> void: body_hits[0] += 1)

	r.store.note_seat(HexyStore.Seat.HEAD, {
		"bits": 0b111000, "moving": 0b000100, "when": 2000,
		"who": "me", "source": "tap", "sig": "abc", "seq_index": 11,
	})

	check(r.store.head_bits() == 0b111000, "the head was written")
	check(String(r.store.head.get("sig", "")) == "abc", "and kept its signature")
	check(int(r.store.head.get("seq_index", -1)) == 11, "and its head-wheel seat")
	check(r.pacing.bits == before, "the cube never moved for a head")
	check(body_hits[0] == 0, "and the body never heard about it")

	r.drop()


# -- 3. the earth seat -------------------------------------------------------

func _test_earth_seat() -> void:
	print("\n[ the earth: the altar, on the head's wheel ]")
	var r := Rig.new()
	var before: int = r.pacing.bits
	var head_hits: Array[int] = [0]
	r.store.head_changed.connect(func(_h: Dictionary) -> void: head_hits[0] += 1)

	r.store.note_seat(HexyStore.Seat.EARTH, {
		"bits": 0b001100, "moving": 0b000001, "when": 3000,
		"who": "me", "source": "tap", "sig": "z", "seq_index": 42,
	})

	check(r.store.earth_bits() == 0b001100, "the earth was written")
	check(int(r.store.earth.get("seq_index", -1)) == 42,
		"with the seat it was given, not one guessed off the body wheel (got %d)"
			% int(r.store.earth.get("seq_index", -1)))
	check(String(r.store.earth.get("sig", "")) == "z", "and it carries a signature")
	check(int(r.store.earth.get("moving", -1)) == 0b000001, "and its moving lines")
	check(r.pacing.bits == before, "the cube never moved for the altar")
	check(head_hits[0] == 0, "and the altar was never mistaken for the head")

	r.drop()


# -- 4. a restore is not a gesture -------------------------------------------

func _test_restore_reanchors() -> void:
	print("\n[ a restored body re-anchors the cube ]")
	var r := Rig.new()
	var v0: int = Q6Core.cast_version()
	r.store.load_dump({"body": {"bits": 0b100001, "when": 9000, "source": "restore"}})

	check(r.store.body_bits() == 0b100001, "the dump put the body back")
	check(r.pacing.bits == 0b100001,
		"and the cube re-anchored on it (got %d)" % r.pacing.bits)
	check(Q6Core.cast_version() != v0, "a restore makes a warm chat stale")

	r.drop()


# -- 5. the cube survives a dump ---------------------------------------------

func _test_dump_round_trip() -> void:
	print("\n[ the cube's anchor rides in the dump ]")
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	store.set_pacing_state(0b101101, {"op": "inject", "bits_after": 0b101101})
	var d: Dictionary = store.dump()
	check(d.has("pacing_bits") and int(d["pacing_bits"]) == 0b101101,
		"dump carries pacing_bits")
	check(d.has("journal_tail") and String((d["journal_tail"] as Dictionary).get("op", "")) == "inject",
		"dump carries the journal tail")

	var other: HexyStore = HexyStoreScript.new() as HexyStore
	other.load_dump(d)
	check(other.pacing_bits() == 0b101101,
		"and a load puts it back (got %d)" % other.pacing_bits())
	check(String(other.journal_tail().get("op", "")) == "inject", "tail and all")

	store.free()
	other.free()


# -- 6. the legacy dump ------------------------------------------------------

func _test_legacy_dump() -> void:
	print("\n[ a dump with an earth and a legacy body keeps both ]")
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	store.load_dump({
		"earth": {"bits": 0b000011},
		"hexagram": {"bits": 0b110011},
	})
	check(store.earth_bits() == 0b000011, "the earth came back")
	check(store.body_bits() == 0b110011,
		"and the legacy body was NOT dropped by the earth's branch (got %d)"
			% store.body_bits())
	store.free()


# -- 7. one signal each ------------------------------------------------------

func _test_one_signal_each() -> void:
	print("\n[ a body write fires each name exactly once ]")
	var r := Rig.new()
	var body_hits: Array[int] = [0]
	var hex_hits: Array[int] = [0]
	r.store.body_changed.connect(func(_b: Dictionary) -> void: body_hits[0] += 1)
	r.store.hexagram_changed.connect(func(_h: Dictionary) -> void: hex_hits[0] += 1)

	r.store.note_seat(HexyStore.Seat.BODY, {"bits": 0b011011, "when": 100, "source": "wheel"})

	check(body_hits[0] == 1, "body_changed fired once (got %d)" % body_hits[0])
	check(hex_hits[0] == 1, "hexagram_changed fired once (got %d)" % hex_hits[0])
	r.drop()
