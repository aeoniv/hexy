extends SceneTree
## THE ONE CUBE, FROM THE GODOT SIDE — scripts/core/iching/q6.gd.
##
## Q6Core is a thin client over ONE implementation of Q6 per platform: the
## native C++ cube inside the ixmnn plugin on device, q6_lattice.gd on desktop.
## Two arithmetics that are supposed to be the same arithmetic is exactly the
## situation where a build goes quietly wrong, so both are pinned to the same
## file of numbers:
##
##   tools/q6_golden.gd        writes tests/golden/q6_golden.json
##   THIS SUITE                checks the Godot client against it
##   tests/native/q6_test.cpp  checks the C++ against the same file
##
## What is checked here:
##
##   1. GOLDEN AGREEMENT — eight fixed cases replayed op for op, and every one
##      of the 64 corners, the argmax, the tension, the line that turns and all
##      32 Walsh coefficients compared against the file.
##   2. THE OPERATIONS THEMSELVES — reset and inject put all the mass on one
##      corner, uniform spreads it, anchor is a convex mix, step keeps the sum
##      at one, and set_state round-trips.
##   3. THE EMBEDDING — 32 wide, out[0] is the total mass for any normalised
##      state, a delta and its opposite do NOT embed to the same point, and two
##      different clouds do not collide.
##   4. THE NEIGHBOUR RULE — a cube sitting on one corner names no neighbour,
##      and a cube leaning one line over names that line.
##   5. THE NATIVE LEASE — exactly one client may hold it, and a client that
##      does not still answers every question.
##   6. PACING STILL READS THE SAME CUBE — the mass property, the anchor and
##      the neighbour rule come out of Q6Core now, and the large-beta limit is
##      still the owner's original rule.
##
## Prints === ALL PASS === or fails.

const GOLDEN_PATH: String = "res://tests/golden/q6_golden.json"
const Lattice := preload("res://scripts/core/iching/q6_lattice.gd")

var _fails: int = 0
var _checks: int = 0
## EVERY CHECK IS COUNTED. A suite that prints ALL PASS because the golden file
## was missing and the loop never ran is worse than a red one.
const MIN_CHECKS: int = 150


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		printerr("FAIL ", what)


## Counted, printed only when it fails, for the inside of a 64-long loop.
func _quiet(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL ", what)


func _initialize() -> void:
	print("\n--- Q6 CORE (the one cube, thin client) ---")
	_test_golden()
	_test_operations()
	_test_embedding()
	_test_neighbour()
	_test_lease()
	_test_pacing_reads_the_cube()

	print("checks: %d (floor %d)" % [_checks, MIN_CHECKS])
	if _checks < MIN_CHECKS:
		printerr("FAIL too few checks ran: %d < %d" % [_checks, MIN_CHECKS])
		_fails += 1
	if _fails == 0:
		print("=== ALL PASS ===")
	else:
		printerr("=== %d FAILED ===" % _fails)
	quit(1 if _fails > 0 else 0)


# -- 1. the golden file ------------------------------------------------------

func _test_golden() -> void:
	print("\n-- the golden vectors --")
	_check(FileAccess.file_exists(GOLDEN_PATH), "the golden file is on disk")
	var f: FileAccess = FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if f == null:
		_check(false, "the golden file opens")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_check(false, "the golden file is a JSON object")
		return
	var doc: Dictionary = parsed as Dictionary
	_check(int(doc.get("states", 0)) == Q6Core.STATES, "the file and the client agree on 64 corners")
	_check(int(doc.get("lines", 0)) == Q6Core.LINES, "and on six lines")
	_check(int(doc.get("embed_dim", 0)) == Q6Core.EMBED_DIM, "and on a 32-float embedding")

	var cases: Array = doc.get("cases", []) as Array
	_check(cases.size() >= 8, "the file carries all eight cases (got %d)" % cases.size())
	for c in cases:
		_golden_case(c as Dictionary)


func _golden_case(c: Dictionary) -> void:
	var name: String = String(c.get("name", "?"))
	var cube: Q6Core = _replay(c.get("ops", []) as Array)

	var want_p: Array = c.get("p", []) as Array
	var got_p: PackedFloat64Array = cube.state()
	var worst: float = 0.0
	for h in range(Q6Core.STATES):
		worst = maxf(worst, absf(got_p[h] - float(want_p[h])))
	_check(worst < 1e-12, "%s: every one of the 64 corners matches (worst %s)" % [name, worst])

	_check(cube.argmax() == int(c.get("argmax", -1)), "%s: the corner holding the most mass" % name)
	_check(
		absf(cube.tension() - float(c.get("tension", -1.0))) < 1e-12,
		"%s: tension" % name
	)
	_check(
		cube.best_neighbour(int(c.get("from", 0))) == int(c.get("best_neighbour", -1)),
		"%s: the line that turns" % name
	)

	var want_e: Array = c.get("embed", []) as Array
	var got_e: PackedFloat32Array = cube.embed()
	var worst_e: float = 0.0
	for i in range(Q6Core.EMBED_DIM):
		worst_e = maxf(worst_e, absf(float(got_e[i]) - float(want_e[i])))
	_check(worst_e < 1e-6, "%s: all 32 Walsh coefficients match (worst %s)" % [name, worst_e])


## Replay a golden case's ops through a fresh desktop-side cube.
func _replay(ops: Array) -> Q6Core:
	var cube: Q6Core = Q6Core.new(false)
	for op in ops:
		var a: Array = op as Array
		match String(a[0]):
			"reset":
				cube.reset(int(a[1]))
			"inject":
				cube.inject(int(a[1]))
			"uniform":
				cube.uniform()
			"anchor":
				cube.anchor(int(a[1]), float(a[2]))
			"step":
				cube.step(
					Q6Core.bias_of(int(a[1]), float(a[2]), float(a[3])),
					float(a[4]), float(a[5])
				)
			_:
				_check(false, "unknown golden op: " + String(a[0]))
	return cube


# -- 2. the operations -------------------------------------------------------

func _test_operations() -> void:
	print("\n-- reset, inject, uniform, anchor, step --")
	var cube: Q6Core = Q6Core.new(false)

	cube.reset(0b101010)
	_check(absf(cube.at(0b101010) - 1.0) < 1e-15, "reset puts all the mass on one corner")
	_check(cube.argmax() == 0b101010, "and that corner is the argmax")
	_check(cube.tension() < 1e-12, "a cube on one corner has made up its mind")

	cube.inject(0b000111)
	_check(cube.argmax() == 0b000111, "inject moves the whole cloud to the cast figure")
	_check(absf(_sum(cube.state()) - 1.0) < 1e-15, "and it still sums to one")

	cube.reset(99)  # out of range on purpose
	_check(cube.argmax() == (99 & 63), "a figure out of range is masked to six lines")

	cube.uniform()
	_check(absf(cube.tension() - 1.0) < 1e-12, "uniform has nothing to say")
	for h in range(Q6Core.STATES):
		_quiet(absf(cube.at(h) - 1.0 / 64.0) < 1e-15, "uniform corner %d" % h)
	_check(true, "and every one of the 64 corners holds the same mass")

	# ANCHOR IS A CONVEX MIX and nothing else.
	cube.reset(0)
	cube.anchor(1, 0.5)
	_check(absf(cube.at(0) - 0.5) < 1e-15, "anchor leaves half of what was there")
	_check(absf(cube.at(1) - 0.5) < 1e-15, "and puts the other half on the body's corner")
	_check(absf(_sum(cube.state()) - 1.0) < 1e-15, "and does not change the total")
	cube.reset(7)
	cube.anchor(7, 1.0)
	_check(absf(cube.at(7) - 1.0) < 1e-15, "anchoring all the way is a delta")

	# STEP PRESERVES MASS at every fire's own time.
	for t in [0.0, 0.06, 0.9, 4.0]:
		cube.reset(0b010101)
		cube.step(Q6Core.bias_of(0b101010, 1.0, 1.0), float(t), Q6Core.DEFAULT_BETA)
		_quiet(absf(_sum(cube.state()) - 1.0) < 1e-12, "step at t=%s sums to one" % t)
		_quiet(cube.tension() >= 0.0 and cube.tension() <= 1.0, "tension at t=%s in [0,1]" % t)
	_check(true, "one step sums to one and has a tension in [0, 1] at every fire's time")

	# A LONG ENOUGH STEP FORGETS EVERYTHING it was told about where it started.
	cube.reset(0)
	var zero_bias: PackedFloat64Array = PackedFloat64Array()
	zero_bias.resize(6)
	zero_bias.fill(0.0)
	cube.step(zero_bias, 40.0, Q6Core.DEFAULT_BETA)
	_check(cube.tension() > 1.0 - 1e-9, "a long step with no bias forgets where it started")

	# SET_STATE round-trips, so a saved cloud comes back the cloud it was.
	var saved: PackedFloat64Array = cube.state()
	cube.reset(33)
	cube.set_state(saved)
	var back: PackedFloat64Array = cube.state()
	var d: float = 0.0
	for h in range(Q6Core.STATES):
		d = maxf(d, absf(back[h] - saved[h]))
	_check(d < 1e-15, "a saved cloud comes back the cloud it was")
	cube.set_state(PackedFloat64Array([1.0, 2.0]))
	var still: PackedFloat64Array = cube.state()
	var d2: float = 0.0
	for h in range(Q6Core.STATES):
		d2 = maxf(d2, absf(still[h] - saved[h]))
	_check(d2 < 1e-15, "and a wrong-sized one is refused rather than half-applied")


# -- 3. the embedding --------------------------------------------------------

func _test_embedding() -> void:
	print("\n-- the cloud as a point in R^32 --")
	var cube: Q6Core = Q6Core.new(false)

	cube.reset(0)
	var e: PackedFloat32Array = cube.embed()
	_check(e.size() == Q6Core.EMBED_DIM, "the embedding is 32 floats wide")
	_check(absf(float(e[0]) - 1.0) < 1e-6, "out[0] is the total mass, which is one")

	# THE INDICES ARE THE DOCUMENTED ONES: ascending k, popcount <= 3, first 32.
	var kept: Array[int] = ([] as Array[int])
	for k in range(Q6Core.STATES):
		if kept.size() >= Q6Core.EMBED_DIM:
			break
		if Lattice.popcount(k) <= 3:
			kept.append(k)
	_check(kept.size() == 32, "exactly 32 indices are kept")
	# THE ORDER IS ASCENDING k, not ascending popcount: the cut falls at k = 41
	# and the 32 kept are 1 + 6 + 13 + 12 by popcount. Writing the number down
	# is the only way a later reordering cannot pass quietly.
	var by_pop: Array[int] = [0, 0, 0, 0]
	for k in kept:
		by_pop[Lattice.popcount(k)] += 1
	_check(
		by_pop == ([1, 6, 13, 12] as Array[int]) and kept[31] == 37,
		"and they are 1 + 6 + 13 + 12 by popcount, cut at k = 37 (got %s, last k %d)"
			% [str(by_pop), kept[31]]
	)
	var c_full: PackedFloat64Array = Lattice.fwht(cube.state())
	for i in range(Q6Core.EMBED_DIM):
		_quiet(
			absf(float(e[i]) - float(c_full[kept[i]])) < 1e-6,
			"embed[%d] is Walsh coefficient k=%d" % [i, kept[i]]
		)
	_check(true, "and each slot is the Walsh coefficient of its own k, low frequency first")

	# DIFFERENT FIGURES ARE DIFFERENT POINTS. An embedding that collapsed a
	# figure onto its opposite would be worse than no embedding.
	cube.reset(0b000000)
	var a: PackedFloat32Array = cube.embed()
	cube.reset(0b111111)
	var b: PackedFloat32Array = cube.embed()
	_check(_max_diff(a, b) > 0.5, "a figure and its opposite are far apart")
	cube.uniform()
	var u: PackedFloat32Array = cube.embed()
	_check(_max_diff(a, u) > 0.5, "a delta and a cloud with nothing to say are far apart")
	_check(absf(float(u[0]) - 1.0) < 1e-6, "and the cloud's own total is still one")
	var flat: bool = true
	for i in range(1, Q6Core.EMBED_DIM):
		if absf(float(u[i])) > 1e-6:
			flat = false
	_check(flat, "uniform has no harmonics above the zeroth, which is what uniform means")


# -- 4. the neighbour rule ---------------------------------------------------

func _test_neighbour() -> void:
	print("\n-- the line that turns --")
	var cube: Q6Core = Q6Core.new(false)

	cube.reset(0)
	_check(cube.best_neighbour(0) == 0, "a cube sitting on one corner names no line but the first")

	for line in range(6):
		cube.reset(1 << line)
		_check(
			cube.best_neighbour(0) == line,
			"a cube leaning one line over names line %d" % line
		)

	# TIES GO TO THE LOWEST LINE, and the test is relative: at a large beta all
	# six neighbours sit around 1e-68 and an absolute epsilon would call every
	# pair of them equal.
	var tiny: PackedFloat64Array = PackedFloat64Array()
	tiny.resize(64)
	tiny.fill(0.0)
	for line in range(6):
		tiny[1 << line] = 1e-68
	cube.set_state(tiny)
	_check(cube.best_neighbour(0) == 0, "six neighbours at 1e-68 is a tie, and a tie goes to line 1")
	tiny[1 << 3] = 1e-68 * 2.0
	cube.set_state(tiny)
	_check(cube.best_neighbour(0) == 3, "and a neighbour twice the others at 1e-68 still wins")


# -- 5. the native lease -----------------------------------------------------

func _test_lease() -> void:
	print("\n-- the native lease --")
	var a: Q6Core = Q6Core.new(false)
	var b: Q6Core = Q6Core.new(false)
	_check(not a.is_native(), "a client that did not ask for the plugin is not native")
	a.reset(1)
	b.reset(2)
	_check(a.argmax() == 1 and b.argmax() == 2, "two desktop clients do not share a state")
	# On desktop Engine has no IxMnn singleton, so asking for it changes nothing
	# and every question is still answered.
	var c: Q6Core = Q6Core.new(true)
	_check(
		not c.is_native() or Engine.has_singleton("IxMnn"),
		"a client is only native when the plugin is actually there"
	)
	c.reset(5)
	c.anchor(4, 0.5)
	_check(absf(_sum(c.state()) - 1.0) < 1e-12, "and it answers every question either way")


# -- 6. Pacing still reads the same cube -------------------------------------

func _test_pacing_reads_the_cube() -> void:
	print("\n-- Pacing reads the cube --")
	var p: Pacing = Pacing.new()
	p.reset(0b000000)
	_check(p.cube != null, "Pacing carries a Q6Core")
	_check(p.mass.size() == 64, "and its mass is still 64 numbers")
	_check(absf(p.mass[0] - 1.0) < 1e-15, "seeded on the body it was reset to")

	p.inject(0b101010, 0)
	_check(p.bits == 0b101010, "a cast lands in the body")
	_check(absf(p.mass[0b101010] - 1.0) < 1e-15, "and the cloud re-anchors on it")

	# THE LARGE-BETA LIMIT IS THE OWNER'S ORIGINAL RULE: the lowest line that
	# differs. This is the claim the whole cube is measured against, and it must
	# survive the move into C++.
	var agreed: int = 0
	var tried: int = 0
	for from_bits in range(64):
		for to_bits in range(64):
			if from_bits == to_bits:
				continue
			var q: Pacing = Pacing.new()
			q.reset(from_bits)
			q.beta = 40.0
			for _i in range(3):
				q.tick(_i * 100, to_bits, 1.0, 0.0, 1.0, 1.0)
			tried += 1
			if q.best_neighbour() == Pacing.lowest_differing_bit(from_bits, to_bits):
				agreed += 1
	_check(
		agreed == tried,
		"at beta 40 the cube turns the LOWEST differing line every time (%d of %d)"
			% [agreed, tried]
	)


# -- helpers -----------------------------------------------------------------

static func _sum(v: PackedFloat64Array) -> float:
	var t: float = 0.0
	for x in v:
		t += x
	return t


static func _max_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var d: float = 0.0
	for i in range(mini(a.size(), b.size())):
		d = maxf(d, absf(float(a[i]) - float(b[i])))
	return d
