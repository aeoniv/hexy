extends SceneTree

## Headless checks for the Q6 WARM-STATE STAMP: the static counter that tells
## the native decode loop which cube a prompt was written under.
##
## The stamp is a property of the ONE cube, not of whichever object holds the
## native lease, so everything here is checked through the statics -- and a
## pure-desktop Q6Core.new(false) must read exactly the same number.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST Q6 CAST VERSION (the warm-state stamp) ---")

	_test_monotonic()
	_test_shared_static()
	_test_desktop_reads()
	_test_cube_writes_do_not_bump()
	_test_cast_bumps_once()

	if failures == 0:
		print("--- Q6 CAST VERSION TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- Q6 CAST VERSION TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _test_monotonic() -> void:
	print("\n[ the stamp only ever goes up ]")
	check(Q6Core.cast_version() >= 0, "the stamp starts at or above zero")
	var last: int = Q6Core.cast_version()
	var strict: bool = true
	for i in range(16):
		var got: int = Q6Core.bump_cast_version()
		if got <= last or Q6Core.cast_version() != got:
			strict = false
		last = got
	check(strict, "16 bumps are strictly monotonic and cast_version() agrees with each")


func _test_shared_static() -> void:
	print("\n[ one stamp, however many cubes ]")
	var before: int = Q6Core.cast_version()
	var pure: Q6Core = Q6Core.new(false)
	check(not pure.is_native(), "a Q6Core.new(false) runs the desktop arithmetic")
	check(Q6Core.cast_version() == before,
		"building one does not move the stamp (got %d, want %d)"
			% [Q6Core.cast_version(), before])
	Q6Core.bump_cast_version()
	check(Q6Core.cast_version() == before + 1,
		"and it reads the same static everybody else does")


func _test_desktop_reads() -> void:
	print("\n[ what the native readers say off device ]")
	check(Q6Core.prior_mismatches() == 0,
		"prior_mismatches() is 0 with no plugin (got %d)" % Q6Core.prior_mismatches())
	check(Q6Core.native_figure_version() == -1,
		"native_figure_version() is -1 with no plugin (got %d)"
			% Q6Core.native_figure_version())


func _test_cube_writes_do_not_bump() -> void:
	print("\n[ moving mass is not a new cube ]")
	var cube: Q6Core = Q6Core.new(false)
	var before: int = Q6Core.cast_version()
	cube.reset(0)
	cube.inject(21)
	var bias: PackedFloat64Array = Q6Core.bias_of(21, 1.0, 1.0)
	cube.anchor(21, Q6Core.ANCHOR)
	cube.step(bias, 0.5, Q6Core.DEFAULT_BETA)
	check(Q6Core.cast_version() == before,
		"reset/inject/step leave the stamp alone (got %d, want %d)"
			% [Q6Core.cast_version(), before])


func _test_cast_bumps_once() -> void:
	print("\n[ a cast makes a warm chat stale ]")
	var store: HexyStore = HexyStoreScript.new()
	var senses: Senses = Senses.new()
	var al: Alchemy = Alchemy.new()
	al.bind(store, senses)
	var before: int = Q6Core.cast_version()
	store.note_cast("cast_confirmed", {"bits": 42, "moving": 0, "when": 1000, "source": "tap"})
	check(Q6Core.cast_version() == before + 1,
		"one note_cast on a bound Alchemy bumps the stamp by exactly 1 (got %d, want %d)"
			% [Q6Core.cast_version(), before + 1])
	check(store.body_bits() == 42, "and the cast landed in the body")
	al.unbind()
