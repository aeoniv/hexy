extends SceneTree

## Headless checks for THE CAST BUS: the one wire from a person's tap to the
## cube. The glass announces on store.seat_landed, the app alone hears it and
## injects, and pacing re-anchors -- so a cast can never be overwritten by the
## next senses tick, and the glass never writes the body behind pacing's back.
##
## W10d -- alchemy.gd (the old pressure shim) is deleted. This file now wires
## the same seat_landed -> inject path app.gd does (see `_on_seat_landed_pacing`
## there), by hand, rather than through a core object.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST CAST BUS (tap -> store -> pacing -> cube) ---")

	_test_cast_reaches_the_cube()
	_test_unwired_store_writes_its_own_body()

	if failures == 0:
		print("--- ALL CAST BUS TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CAST BUS TESTS FAILED: ", failures, " ---\n")
		quit(1)


# -- 1. the wire -------------------------------------------------------------

func _test_cast_reaches_the_cube() -> void:
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	var rig: Senses = Senses.new()
	rig.bind(store)
	var p: Pacing = Pacing.new()
	p.reset(0)
	store.seat_landed.connect(func(seat: int, c: Dictionary) -> void:
		if seat == HexyStore.Seat.BODY:
			p.inject(int(c.get("bits", 0)) & 63, int(c.get("when", 0))))

	check(store.has_signal("cast_landed"), "the store carries a cast_landed signal")

	var hex_hits: Array[int] = [0]
	store.hexagram_changed.connect(func(_h: Dictionary) -> void: hex_hits[0] += 1)

	p.journal_clear()
	store.note_cast("cast_confirmed", {"bits": 0b101010, "when": 1000})

	check(p.bits == 0b101010,
		"the cast re-anchored the cube (got %d)" % p.bits)
	check(store.body_bits() == 0b101010,
		"and the store body holds it (got %d)" % store.body_bits())
	check(hex_hits[0] == 1, "hexagram_changed fired exactly once (got %d)" % hex_hits[0])

	var injects: int = _count_injects(p.journal, 0b101010)
	check(injects == 1, "one inject entry in the journal (got %d)" % injects)

	# The same cast again: one more inject, and no re-entrancy -- the body is
	# already there, so the store stays quiet.
	store.note_cast("cast_confirmed", {"bits": 0b101010, "when": 1000})
	check(_count_injects(p.journal, 0b101010) == 2,
		"a second identical cast injects exactly once more")
	check(hex_hits[0] == 1, "and no second hexagram_changed: the body did not move")
	check(p.bits == 0b101010, "the cube is still on the cast")

	# The moving lines of a cast survive into the body through inject.
	store.note_cast("cast_confirmed", {"bits": 0b000111, "moving": 0b000010, "when": 2000})
	check(store.body_bits() == 0b000111, "a second figure lands whole")
	check(int(store.body["moving"]) == 0b000010, "and carries its moving line")

	store.free()
	rig.free()


# -- 2. the negative ---------------------------------------------------------

## With nothing listening to seat_landed, no cube hears the cast -- but the
## store still writes its own announcement, having never been claimed.
func _test_unwired_store_writes_its_own_body() -> void:
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	var rig: Senses = Senses.new()
	rig.bind(store)
	var p: Pacing = Pacing.new()
	p.reset(0)
	# Deliberately never connected to store.seat_landed.

	var before: int = p.bits
	store.note_cast("cast_confirmed", {"bits": 0b111000, "when": 3000})
	check(p.bits == before, "an unwired cube never hears the cast")
	## W8c -- THE CLAIM IS GONE, AND SO IS THE HOLE IT LEFT. `note_seat` writes
	## no body itself unless nothing has claimed it; one writer, and never none.
	check(store.body_bits() == 0b111000,
		"and the store writes the announcement itself, having never been claimed")

	store.free()
	rig.free()


static func _count_injects(journal: Array[Dictionary], bits_after: int) -> int:
	var n: int = 0
	for e in journal:
		if String(e.get("op", "")) == "inject" and int(e.get("bits_after", -1)) == bits_after:
			n += 1
	return n
