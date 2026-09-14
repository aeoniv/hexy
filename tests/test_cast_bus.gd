extends SceneTree

## Headless checks for THE CAST BUS: the one wire from a person's tap to the
## cube. The glass announces on store.cast_landed, Alchemy alone hears it and
## injects, and pacing re-anchors -- so a cast can never be overwritten by the
## next senses tick, and the glass never writes the body behind pacing's back.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST CAST BUS (tap -> store -> alchemy -> cube) ---")

	_test_cast_reaches_the_cube()
	_test_unbound_alchemy_never_hears()

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
	var al: Alchemy = Alchemy.new()
	al.bind(store, rig)

	check(store.has_signal("cast_landed"), "the store carries a cast_landed signal")

	var hex_hits: Array[int] = [0]
	store.hexagram_changed.connect(func(_h: Dictionary) -> void: hex_hits[0] += 1)

	al.pacing.journal_clear()
	store.note_cast("cast_confirmed", {"bits": 0b101010, "when": 1000})

	check(al.pacing.bits == 0b101010,
		"the cast re-anchored the cube (got %d)" % al.pacing.bits)
	check(store.body_bits() == 0b101010,
		"and the store body holds it (got %d)" % store.body_bits())
	check(hex_hits[0] == 1, "hexagram_changed fired exactly once (got %d)" % hex_hits[0])

	var injects: int = _count_injects(al.pacing.journal, 0b101010)
	check(injects == 1, "one inject entry in the journal (got %d)" % injects)

	# The same cast again: one more inject, and no re-entrancy -- the body is
	# already there, so the store stays quiet.
	store.note_cast("cast_confirmed", {"bits": 0b101010, "when": 1000})
	check(_count_injects(al.pacing.journal, 0b101010) == 2,
		"a second identical cast injects exactly once more")
	check(hex_hits[0] == 1, "and no second hexagram_changed: the body did not move")
	check(al.pacing.bits == 0b101010, "the cube is still on the cast")

	# The moving lines of a cast survive into the body through inject.
	store.note_cast("cast_confirmed", {"bits": 0b000111, "moving": 0b000010, "when": 2000})
	check(store.body_bits() == 0b000111, "a second figure lands whole")
	check(int(store.body["moving"]) == 0b000010, "and carries its moving line")

	store.free()
	rig.free()
	al.free()


# -- 2. the negative ---------------------------------------------------------

## With Alchemy unbound nothing is listening, so a cast is a reward and no more.
func _test_unbound_alchemy_never_hears() -> void:
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	var rig: Senses = Senses.new()
	rig.bind(store)
	var al: Alchemy = Alchemy.new()
	al.bind(store, rig)
	al.unbind()

	var before: int = al.pacing.bits
	store.note_cast("cast_confirmed", {"bits": 0b111000, "when": 3000})
	check(al.pacing.bits == before, "an unbound Alchemy never hears the cast")
	check(store.body_bits() != 0b111000, "and nothing writes the body in its place")

	store.free()
	rig.free()
	al.free()


static func _count_injects(journal: Array[Dictionary], bits_after: int) -> int:
	var n: int = 0
	for e in journal:
		if String(e.get("op", "")) == "inject" and int(e.get("bits_after", -1)) == bits_after:
			n += 1
	return n
