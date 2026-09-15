extends SceneTree

## Headless checks for scripts/core/iching/pacing.gd: the two fires, the one
## line they are allowed to turn, and the three clocks that hold them back.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST CORE PACING (civil fire, martial fire, lockout) ---")

	_test_civil_fire()
	_test_one_line_at_a_time()
	_test_rearm()
	_test_martial_fire()
	_test_inject_lockout()
	_test_reason_strings()
	_test_alchemy()
	_test_q6_limit()
	_test_q6_is_not_decorative()
	_test_pacing_rides_one_cube()
	_test_journal()

	if failures == 0:
		print("--- ALL CORE PACING TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CORE PACING TESTS FAILED: ", failures, " ---\n")
		quit(1)


## Walk a still body for `ms` milliseconds in 100 ms steps from `t0`, stopping
## at the first flip. Returns [result, now_ms].
func still_walk(p: Pacing, t0: int, ms: int, target: int, step: int = 100) -> Array:
	var t: int = t0
	while t <= t0 + ms:
		var out: Dictionary = p.tick(t, target, 1.0, 0.0)
		if not out.is_empty():
			return [out, t]
		t += step
	return [{}, t]


# -- 1. one resting breath ---------------------------------------------------

func _test_civil_fire() -> void:
	var p: Pacing = Pacing.new()
	p.reset(0)

	# The first tick only records the target; the dwell starts on the next.
	check(p.tick(0, 1, 1.0, 0.0).is_empty(), "the first tick never turns a line")

	# At perfect stillness the dwell banks delta * 1.15, so 2.5 s of dwell is
	# about 2.17 s of clock. Nothing may turn before then.
	var early: Array = still_walk(p, 100, 2000, 1)
	check((early[0] as Dictionary).is_empty(),
		"no line turns inside the first two seconds of stillness")

	var late: Array = still_walk(p, 2200, 2000, 1)
	var flip: Dictionary = late[0]
	check(not flip.is_empty(), "the civil fire turns a line once the breath is held")
	check(String(flip.get("kind", "")) == "civil", "and it is the civil fire that did it")
	check(int(flip.get("bits", -1)) == 1, "the body has walked one line toward the target")
	check(p.bits == 1, "and the pacing kept it")

	# Motion spends the dwell rather than banking it.
	var q: Pacing = Pacing.new()
	q.reset(0)
	q.tick(0, 1, 1.0, 0.0)
	var t: int = 100
	while t <= 6000:
		q.tick(t, 1, 0.2, 0.0)
		t += 100
	check(q.dwell() == 0.0, "a moving body banks no dwell at all")
	check(q.bits == 0, "and turns no line in six seconds of it")


# -- 2. the lowest differing bit, and only that one --------------------------

func _test_one_line_at_a_time() -> void:
	var p: Pacing = Pacing.new()
	p.reset(0b000000)
	var target: int = 0b101010

	check(Pacing.lowest_differing_bit(0b000000, 0b101010) == 1,
		"the lowest differing bit of 0 and 101010 is line 2")
	check(Pacing.lowest_differing_bit(0b101010, 0b101010) == -1,
		"an arrived figure has no differing bit")

	var seen: Array[int] = ([] as Array[int])
	var walk: Array[int] = ([] as Array[int])
	var t: int = 0
	while t <= 60000:
		var out: Dictionary = p.tick(t, target, 1.0, 0.0)
		if not out.is_empty():
			seen.append(int(out["line"]))
			walk.append(int(out["bits"]))
		t += 100
	check(seen == [1, 3, 5],
		"only the lowest differing line turns, three flips in order (got %s)" % str(seen))
	check(walk == [0b000010, 0b001010, 0b101010],
		"and the body walks to the target one line at a time (got %s)" % str(walk))
	check(p.bits == target, "the body arrives at the figure the senses asked for")

	var after: Dictionary = p.tick(70000, target, 1.0, 0.0)
	check(after.is_empty(), "an arrived body turns nothing more")


# -- 3. the rearm ------------------------------------------------------------

func _test_rearm() -> void:
	var p: Pacing = Pacing.new()
	p.reset(0b000000)
	var target: int = 0b000011
	p.tick(0, target, 1.0, 0.0)
	var first: Array = still_walk(p, 100, 5000, target)
	check(not (first[0] as Dictionary).is_empty(), "the first line turns")
	var t0: int = int(first[1])

	# Even with the dwell refilled, the 2 s rearm holds the next one back.
	var t: int = t0 + 100
	var second_at: int = -1
	while t <= t0 + 6000:
		var out: Dictionary = p.tick(t, target, 1.0, 0.0)
		if not out.is_empty():
			second_at = t
			break
		t += 100
	check(second_at >= 0, "a second line does turn eventually")
	check(second_at - t0 >= int(Pacing.REARM * 1000.0),
		"but not inside the 2 s rearm (waited %d ms)" % (second_at - t0))


# -- 4. the martial fire -----------------------------------------------------

func _test_martial_fire() -> void:
	var p: Pacing = Pacing.new()
	p.reset(0b000000)
	var target: int = 0b000111
	p.tick(0, target, 0.0, 0.0)
	check(p.tick(100, target, 0.0, 0.84).is_empty(),
		"excitation just under the threshold turns nothing")
	var hit: Dictionary = p.tick(200, target, 0.0, Pacing.MARTIAL_THRESHOLD)
	check(not hit.is_empty(), "excitation at 0.85 turns a line with no stillness at all")
	check(String(hit.get("kind", "")) == "martial", "and it is the martial fire")
	check(int(hit.get("line", -1)) == 0, "it takes the lowest differing line too")

	# The caller zeroes its own excitation; a caller that does not is still
	# held by the 3.5 s cooldown.
	check(p.tick(300, target, 0.0, 1.0).is_empty(),
		"a surge 100 ms later is inside the cooldown")
	check(p.tick(3600, target, 0.0, 1.0).is_empty(),
		"and still inside it at 3.4 s")
	check(not p.tick(3800, target, 0.0, 1.0).is_empty(),
		"past 3.5 s the martial fire may turn another line")


# -- 5. a cast lands, and both fires go quiet --------------------------------

func _test_inject_lockout() -> void:
	var p: Pacing = Pacing.new()
	p.reset(0b000000)
	var target: int = 0b111111

	# Bank a full dwell first, so nothing but the lockout can be holding it.
	still_walk(p, 0, 4000, target)
	p.inject(0b010101, 100000)
	check(p.bits == 0b010101, "inject sets the body to the head's figure")
	check(p.dwell() == 0.0, "and zeroes the dwell it was banking")

	var civil: Array = still_walk(p, 100100, 2300, target)
	check((civil[0] as Dictionary).is_empty(),
		"no civil flip inside 2.5 s of an inject")
	check(p.tick(101000, target, 0.0, 1.0).is_empty(),
		"and no martial flip either, however hard the phone is shaken")
	check(p.tick(102400, target, 0.0, 1.0).is_empty(),
		"still locked out at 2.4 s")
	check(not p.tick(102600, target, 0.0, 1.0).is_empty(),
		"past 2.5 s the fire is free again")


# -- 6. what the fire says it did --------------------------------------------

func _test_reason_strings() -> void:
	var p: Pacing = Pacing.new()

	# Line 3 (Breath) going to yang, by the martial fire.
	p.reset(0b000000)
	p.tick(0, 0b000100, 0.0, 0.0)
	var up: Dictionary = p.tick(100, 0b000100, 0.0, 1.0)
	var up_reason: String = String(up.get("reason", ""))
	check(int(up["line"]) == 2 and bool(up["to_yang"]),
		"line 3 turned, and it turned to yang")
	check(up_reason.contains("Line 3 (Breath)"),
		"the reason names the line by its habit (got %s)" % up_reason)
	check(up_reason.contains("Ignited into Yang"), "and says it ignited")
	check(up_reason.contains("Martial Fire"), "and which fire did it")

	# Line 1 (Body) going to yin, by the civil fire.
	var q: Pacing = Pacing.new()
	q.reset(0b000001)
	q.tick(0, 0b000000, 1.0, 0.0)
	var down: Dictionary = (still_walk(q, 100, 5000, 0b000000)[0] as Dictionary)
	var down_reason: String = String(down.get("reason", ""))
	check(int(down["line"]) == 0 and not bool(down["to_yang"]),
		"line 1 turned, and it turned to yin")
	check(down_reason.contains("Line 1 (Body)"), "the reason names line 1 as Body")
	check(down_reason.contains("Yielded into Yin"), "and says it yielded")
	check(down_reason.contains("Civil Fire"), "and that the civil fire did it")
	check(Pacing.LINE_NAMES.size() == 6 and Pacing.LINE_NAMES[5] == "Connection",
		"six habits, the top one Connection")


# -- 7. the hinge ------------------------------------------------------------

## Alchemy is the ONLY thing that writes the body from the senses, and the head
## is the only thing that writes it from a person.
func _test_alchemy() -> void:
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	var rig: Senses = Senses.new()
	rig.bind(store)
	## THE CUBE, ASKED FOR OUT LOUD. Pacing turns a line the beat the senses ask
	## for it -- alchemy.gd (the old hysteresis shim) is gone; W10d folded what
	## it still did into the store and deleted the rest.
	var p: Pacing = Pacing.new()
	p.reset(0)

	# Drive the senses until they settle on a target, keeping the phone still.
	var quiet: Dictionary = {"battery_pct": 8.0, "face_on": true, "touch_rate": 2.0,
		"accel": Vector3(0, 9.8, 0), "gravity": Vector3(0, 9.8, 0),
		"gyro": Vector3(0.001, 0.0, 0.0)}
	rig.tick(0, quiet)
	rig.tick(4000, quiet)
	check(rig.target_bits() == 42, "the senses ask for 42")

	var flips: Array[Dictionary] = []
	var t: int = 4000
	while t <= 60000:
		rig.tick(t, quiet)
		var out: Dictionary = p.tick(t, rig.target_bits(), rig.stillness(),
			rig.excitation(), rig.machine_margin(), rig.human_margin())
		if not out.is_empty():
			flips.append(out)
		t += 200
	check(not flips.is_empty(), "the body turns lines toward the target")
	## W8c -- THE CUBE ARRIVES, THE BODY IS NOT WRITTEN. Pacing walks the
	## 64-corner cube to the figure the senses ask for; it does not write that
	## figure into the store. The homeostat in scripts/brain is what a line
	## fill -- and therefore the body -- is made of now.
	check(p.bits == 42, "and the cube arrives at 42 (got %d)" % p.bits)
	check(store.body_bits() == 0,
		"while the store's body was never written from here (got %d)" % store.body_bits())
	check(store.head_bits() == 0, "the head never moved")
	check(String(flips[flips.size() - 1].get("reason", "")) != "",
		"every turned line still says why")
	check(int(flips[flips.size() - 1].get("line", -1)) >= 0, "and which line it was")

	# An injected cast re-anchors the cube; the figure itself is the body's own.
	p.inject(0b111000, 70000)
	check(store.body_bits() == 0, "an explicit cast writes no body here either")
	check(p.bits == 0b111000, "the pacing re-anchored on the cast")
	check(p.tick(71000, 0b111000, 1.0, 0.0).is_empty(), "and both fires are locked out for 2.5 s")

	store.free()
	rig.free()


# -- 8. the large-beta limit IS the owner's old rule --------------------------

## With beta large the Gibbs reweight swamps everything the diffusion did, and
## the neighbour holding the most mass is the one the original rule names: the
## LOWEST DIFFERING BIT. If this ever parts company, the cube has stopped being
## a generalisation of the rule and started being a different rule.
func _test_q6_limit() -> void:
	seed(20260913)
	var pairs: int = 0
	var agreed: int = 0
	for _i in range(400):
		var current: int = randi() % 64
		var target: int = randi() % 64
		if current == target:
			continue
		pairs += 1
		var p: Pacing = Pacing.new()
		p.reset(current)
		p.beta = 40.0
		# One martial surge, with the margins an unscaled caller would pass.
		p.tick(0, target, 0.0, 0.0)
		var out: Dictionary = p.tick(100, target, 0.0, 1.0)
		if out.is_empty():
			continue
		if int(out["line"]) == Pacing.lowest_differing_bit(current, target):
			agreed += 1
	check(pairs > 300, "several hundred random pairs were tried (got %d)" % pairs)
	check(agreed == pairs,
		"at beta 40 the cube turns the LOWEST differing line every time (%d of %d)"
			% [agreed, pairs])

	# And the same over a long civil walk: the body still arrives, one line at
	# a time, by the lowest differing bit each step.
	var q: Pacing = Pacing.new()
	q.reset(0b000000)
	q.beta = 40.0
	var target2: int = 0b101010
	var lines: Array[int] = ([] as Array[int])
	var t: int = 0
	while t <= 60000:
		var out2: Dictionary = q.tick(t, target2, 1.0, 0.0)
		if not out2.is_empty():
			lines.append(int(out2["line"]))
		t += 100
	check(lines == [1, 3, 5],
		"a civil walk at beta 40 turns lines 2, 4, 6 in that order (got %s)" % str(lines))
	check(q.bits == target2, "and arrives at the figure asked for")


# -- 9. and the cube is not decorative ---------------------------------------

## THE WIRING MUST BE ABLE TO DISAGREE. The two trigrams do not pull equally:
## a human election won by a mile outweighs a machine election won by a hair,
## so a differing line in the UPPER trigram can outrank a lower one. If no such
## case exists, the lattice is arithmetic nobody is listening to.
func _test_q6_is_not_decorative() -> void:
	# Body 0, target 0b101001: differing lines are 0 (machine, thin margin) and
	# 3 and 5 (human, wide margin). The old rule says line 0 without looking.
	var current: int = 0b000000
	var target: int = 0b101001
	check(Pacing.lowest_differing_bit(current, target) == 0,
		"the old rule would take line 1")

	var p: Pacing = Pacing.new()
	p.reset(current)
	p.beta = Pacing.DEFAULT_BETA
	p.tick(0, target, 0.0, 0.0, 0.05, 1.0)
	var out: Dictionary = p.tick(100, target, 0.0, 1.0, 0.05, 1.0)
	check(not out.is_empty(), "the martial fire turns a line under a lopsided bias")
	check(int(out["line"]) != 0,
		"and it is NOT the lowest differing line (got line %d)" % (int(out["line"]) + 1))
	check(int(out["line"]) == 3,
		"it is the lowest line of the trigram that actually won (got %d)"
			% int(out["line"]))

	# The same pair with the margins level goes back to the old answer, so the
	# difference is the MARGIN and nothing else.
	var q: Pacing = Pacing.new()
	q.reset(current)
	q.tick(0, target, 0.0, 0.0, 1.0, 1.0)
	var level: Dictionary = q.tick(100, target, 0.0, 1.0, 1.0, 1.0)
	check(int(level.get("line", -1)) == 0,
		"level margins take the lowest differing line again")

	# The bias itself is the 8x8 target, signed and scaled.
	var bias: PackedFloat64Array = Pacing.bias_of(0b111000, 0.25, 0.75)
	check(is_equal_approx(bias[0], -0.25) and is_equal_approx(bias[2], -0.25),
		"a yin machine line pulls down by the machine's margin")
	check(is_equal_approx(bias[3], 0.75) and is_equal_approx(bias[5], 0.75),
		"a yang human line pulls up by the human's margin")
	check(Pacing.CIVIL_T < Pacing.MARTIAL_T,
		"the held breath spreads less mass than the surge")


## THE CUBE IS ONE CUBE. Pacing no longer carries its own 64 numbers and its own
## copy of the anchor and neighbour rules: it holds a Q6Core, which is the native
## C++ Q6 inside the ixmnn plugin on device and q6_lattice.gd here. This checks
## that the move did not cost Pacing anything it used to guarantee -- the mass is
## still readable, still normalised, still anchored on the body, still the thing
## `best_neighbour` reads -- and that the SAME cube is the one an embedding and
## the decode-loop prior would see.
func _test_pacing_rides_one_cube() -> void:
	var p: Pacing = Pacing.new()
	p.reset(0b010101)
	check(p.cube != null, "Pacing carries a Q6Core")
	check(p.cube is Q6Core, "and it is the thin client, not a second arithmetic")
	check(p.mass.size() == Q6Core.STATES, "the mass is still 64 numbers")
	check(is_equal_approx(p.mass[0b010101], 1.0), "seeded on the body it was reset to")
	check(is_equal_approx(_sum(p.mass), 1.0), "and summing to one")

	# The mass is a READ of the cube, so the two can never disagree.
	var from_cube: PackedFloat64Array = p.cube.state()
	var same: bool = true
	for h in range(Q6Core.STATES):
		if absf(from_cube[h] - p.mass[h]) > 1e-15:
			same = false
	check(same, "Pacing.mass is the cube's own state, not a copy that may drift")

	# A TICK MOVES THE CUBE, every tick, gate or no gate, and leaves it anchored
	# on the body rather than piled on the target.
	for i in range(8):
		p.tick(i * 100, 0b101010, 1.0, 0.0, 1.0, 1.0)
	check(is_equal_approx(_sum(p.mass), 1.0), "eight ticks later it still sums to one")
	# THE ANCHOR KEEPS THE NEIGHBOURHOOD READABLE. It does not hold the argmax --
	# under a strong bias the Gibbs pull carries that to the target, which is the
	# point of the bias -- but every one of the six corners one line from the body
	# must still hold real mass, because a neighbourhood of zeros is a tie the
	# cube never meant to call.
	check(p.mass[p.bits] > 0.0, "the body's own corner still holds mass")
	var thinnest: float = INF
	for i in range(Q6Core.LINES):
		thinnest = minf(thinnest, p.mass[p.bits ^ (1 << i)])
	check(thinnest > 0.0,
		"and so does every one of its six neighbours (thinnest %s)" % thinnest)
	check(p.best_neighbour() == p.cube.best_neighbour(p.bits),
		"Pacing's neighbour rule IS the cube's neighbour rule")

	# THE SAME STATE IS THE EMBEDDING and, on device, the decode-loop prior.
	var e: PackedFloat32Array = p.cube.embed()
	check(e.size() == Q6Core.EMBED_DIM, "the cube embeds to 32 floats")
	check(absf(float(e[0]) - 1.0) < 1e-6, "whose zeroth is the total mass")
	check(Q6Embed.cloud(p.cube).size() == Q6Embed.DIM,
		"and Q6Embed.cloud reads the same cube at the same width")
	check(p.cube.tension() >= 0.0 and p.cube.tension() <= 1.0, "tension is in [0, 1]")

	# `inject` re-anchors the whole cloud, which is what a cast is for.
	p.inject(0b111000, 4000)
	check(is_equal_approx(p.mass[0b111000], 1.0), "a cast puts the whole cloud on the figure thrown")

	# ON DESKTOP THERE IS NO DECODE LOOP, so the prior weight is zero and saying
	# otherwise is the lie this check exists to catch.
	check(is_equal_approx(Q6Core.prior_weight(), 0.0),
		"with no plugin there is no decode loop to lean on, and the weight says so")
	Q6Core.set_prior_weight(0.7)
	check(is_equal_approx(Q6Core.prior_weight(), 0.0),
		"and setting it changes nothing there is nothing to set")


# -- 10. the replay log -------------------------------------------------------

## Reset, inject, then a civil-fire walk to a target one line away: the
## journal should hold the reset, the inject, at least one step, and exactly
## one flip, in a monotone clock, and the flip's bits_after should be the
## bits Pacing actually settled on.
func _test_journal() -> void:
	var p: Pacing = Pacing.new()
	p.reset(0b000000, 0)
	p.inject(0b000001, 10)
	var target: int = 0b000011
	still_walk(p, 100, 4000, target)

	var j: Array[Dictionary] = p.journal_snapshot()
	check(not j.is_empty(), "the journal is not empty")

	var ops: Array[String] = ([] as Array[String])
	for e in j:
		ops.append(String(e["op"]))
	check(ops.count("reset") == 1, "exactly one reset entry (got %d)" % ops.count("reset"))
	check(ops.count("inject") == 1, "exactly one inject entry (got %d)" % ops.count("inject"))
	check(ops.count("step") >= 1, "at least one step entry (got %d)" % ops.count("step"))
	check(ops.count("flip") == 1, "exactly one flip entry (got %d)" % ops.count("flip"))

	var t_ms: Array[int] = ([] as Array[int])
	for e in j:
		t_ms.append(int(e["t_ms"]))
	var monotone: bool = true
	for i in range(1, t_ms.size()):
		if t_ms[i] < t_ms[i - 1]:
			monotone = false
	check(monotone, "the journal's clock never runs backward (got %s)" % str(t_ms))

	var flip_entry: Dictionary = {}
	for e in j:
		if String(e["op"]) == "flip":
			flip_entry = e
	check(not flip_entry.is_empty(), "there is a flip entry to check")
	check(int(flip_entry.get("bits_after", -1)) == p.bits,
		"the flip's bits_after matches where Pacing actually settled (got %d, p.bits %d)"
			% [int(flip_entry.get("bits_after", -1)), p.bits])
	check(String(flip_entry.get("kind", "")) == "civil", "and it was the civil fire")
	check(flip_entry.has("line") and flip_entry.has("to_yang") and flip_entry.has("reason"),
		"a flip entry carries line, to_yang and reason")

	# journal_snapshot is a duplicate: clearing the live journal must not
	# touch the snapshot already taken.
	var before_clear: int = j.size()
	p.journal_clear()
	check(p.journal.is_empty(), "journal_clear empties the live journal")
	check(j.size() == before_clear, "but not a snapshot already taken")

	# replay re-drives reset/inject/flip and lands on the same bits.
	var q: Pacing = Pacing.new()
	q.replay(j)
	check(q.bits == p.bits, "replay lands on the same figure the journal recorded (got %d, want %d)"
		% [q.bits, p.bits])


static func _sum(v: PackedFloat64Array) -> float:
	var t: float = 0.0
	for x in v:
		t += x
	return t
