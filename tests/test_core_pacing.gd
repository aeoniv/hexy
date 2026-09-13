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
	var al: Alchemy = Alchemy.new()
	al.bind(store, rig)

	# Drive the senses until they settle on a target, keeping the phone still.
	var quiet: Dictionary = {"battery_pct": 8.0, "face_on": true, "touch_rate": 2.0,
		"accel": Vector3(0, 9.8, 0), "gravity": Vector3(0, 9.8, 0),
		"gyro": Vector3(0.001, 0.0, 0.0)}
	rig.tick(0, quiet)
	rig.tick(4000, quiet)
	check(rig.target_bits() == 42, "the senses ask for 42")

	var flips: Array[Dictionary] = []
	al.line_flipped.connect(func(f: Dictionary) -> void: flips.append(f))
	var t: int = 4000
	while t <= 60000:
		rig.tick(t, quiet)
		al.tick(t)
		t += 200
	check(not flips.is_empty(), "the body turns lines toward the target")
	check(store.body_bits() == 42, "and arrives at 42 (got %d)" % store.body_bits())
	check(String(store.body["source"]) == "senses", "the body's source is the senses")
	check(store.head_bits() == 0, "the head never moved")
	check(String(store.last_flip["reason"]) != "", "the store remembers why the last line turned")
	check(int(store.last_flip["when"]) > 0, "and when")

	# A head cast lands in the body whole, and the fire goes quiet.
	store.set_head({"bits": 0b111000, "moving": 0, "when": 70000})
	check(store.body_bits() == 0b111000, "a head cast is injected into the body")
	check(String(store.body["source"]) == "tap", "and the body says a person did it")
	check(al.pacing.bits == 0b111000, "the pacing re-anchored on the cast")
	check(al.tick(71000).is_empty(), "and both fires are locked out for 2.5 s")

	store.free()
	rig.free()
	al.free()


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
