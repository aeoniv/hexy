extends SceneTree

## THE BODY IS WHAT YOU KEEP DOING, and this is the file that says so.
##
## A line used to turn on one loud afternoon. With `alchemy.flip_days` above
## zero it cannot: evidence lands as a signed mark, the mark has to lean past
## `alchemy.mark_threshold`, and the run feeding it has to have been fed on that
## many separate DAYS. Time is driven from here -- every stamp is a millisecond
## this file chose -- so a fortnight of forgetting costs one integer.
##
## The old body is still reachable and still checked: with flip_days at zero a
## line turns the beat it is asked to, which is what every test written before
## this one expects.

const HexyStoreScript = preload("res://scripts/core/store.gd")

const DAY: int = 86_400_000

var passes: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func near(a: float, b: float, eps: float, label: String) -> void:
	check(absf(a - b) <= eps, "%s (got %.4f, want %.4f +-%.4f)" % [label, a, b, eps])


func _initialize() -> void:
	print("\n--- TEST ALCHEMY HYSTERESIS (the body keeps its own counsel) ---")

	_test_defaults()
	_test_one_day_is_not_enough()
	_test_three_days_turn_the_line()
	_test_decay_forgets()
	_test_a_broken_run_starts_again()
	_test_flip_days_zero_is_the_old_body()
	_test_state_exposes_the_pressure()
	_test_a_cast_spends_the_pressure()

	HexyConfig.forget()
	print("\nPassed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("--- ALL ALCHEMY HYSTERESIS TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- ALCHEMY HYSTERESIS TESTS FAILED: ", failures, " ---\n")
		quit(1)


## A bound Alchemy over a fresh store, with the three dials set from here.
func _rig(flip_days: int, threshold: float = 0.6, decay_days: float = 14.0) -> Alchemy:
	HexyConfig.forget()
	var cfg: HexyConfig = HexyConfig.instance()
	cfg.autosave = false
	cfg.reset()
	cfg.set_value("alchemy.flip_days", flip_days)
	cfg.set_value("alchemy.mark_threshold", threshold)
	cfg.set_value("alchemy.mark_decay_days", decay_days)
	var al: Alchemy = Alchemy.new()
	al.bind(HexyStoreScript.new(), Senses.new())
	return al


func _test_defaults() -> void:
	print("\n[ the dials exist and read as documented ]")
	HexyConfig.forget()
	var cfg: HexyConfig = HexyConfig.instance()
	cfg.autosave = false
	cfg.reset()
	check(int(cfg.get_value("alchemy.flip_days")) == 3, "alchemy.flip_days defaults to 3")
	near(float(cfg.get_value("alchemy.mark_threshold")), 0.6, 1e-6,
		"alchemy.mark_threshold defaults to 0.6")
	near(float(cfg.get_value("alchemy.mark_decay_days")), 14.0, 1e-6,
		"alchemy.mark_decay_days defaults to 14")
	check(cfg.groups().has("alchemy"), "and they arrive as their own group on the dashboard")
	check(int(cfg.row("alchemy.flip_days")["min"]) == 0,
		"flip_days may be taken all the way down to the old body")
	var al: Alchemy = Alchemy.new()
	check(Alchemy.FLIP_DAYS_DEFAULT == 3, "the node's own const agrees with the drawer's default")
	al.bind(HexyStoreScript.new(), Senses.new())
	check(al.flip_days == 3, "and takes the config's word once it is bound")
	near(al.mark_threshold, 0.6, 1e-6, "threshold follows too")
	near(al.mark_decay_days, 14.0, 1e-6, "and so does the leak")
	cfg.set_value("alchemy.flip_days", 7)
	check(al.flip_days == 7, "a dial turned later reaches a bound Alchemy live")
	al.unbind()


func _test_one_day_is_not_enough() -> void:
	print("\n[ one loud afternoon is not a body ]")
	var al: Alchemy = _rig(3)
	var heard: Array = []
	al.line_flipped.connect(func(f: Dictionary) -> void: heard.append(f))
	var moved: Array = []
	al.mark_moved.connect(func(line: int, m: float) -> void: moved.append([line, m]))
	var t: int = 10 * DAY
	check(not al.nudge(2, true, 1.0, t), "one push does not turn line 2")
	check(not al.nudge(2, true, 1.0, t + 1000), "nor does a second, the same hour")
	check(not al.nudge(2, true, 1.0, t + 2000), "nor a third")
	check(heard.is_empty(), "so nothing was announced as a flip")
	check(moved.size() == 3, "but every push moved the mark, out loud")
	near(al.marks()[2], 0.75, 1e-5, "the mark is well past the threshold")
	check(al.days_toward()[2] == 1, "and yet it is still ONE day of evidence")
	check((al._store.body_bits() >> 2) & 1 == 0, "line 2 has not turned")
	al.unbind()


func _test_three_days_turn_the_line() -> void:
	print("\n[ three days of the same pressure ]")
	var al: Alchemy = _rig(3)
	var heard: Array = []
	al.line_flipped.connect(func(f: Dictionary) -> void: heard.append(f))
	var t: int = 100 * DAY
	check(not al.nudge(4, true, 1.0, t), "day one leans")
	check(al.days_toward()[4] == 1, "one day banked")
	check(not al.nudge(4, true, 1.0, t + DAY), "day two leans harder")
	check(al.days_toward()[4] == 2, "two days banked")
	near(al.marks()[4], 0.5, 1e-5, "and the mark is still under the threshold")
	check(al.nudge(4, true, 1.0, t + 2 * DAY), "day three turns the line")
	check(heard.size() == 1, "exactly one flip was announced")
	check(heard.size() == 1 and int(heard[0]["line"]) == 4, "and it named line 4")
	check(heard.size() == 1 and bool(heard[0]["to_yang"]), "turning it to yang")
	check((al._store.body_bits() >> 4) & 1 == 1, "the body carries it")
	check(int(al._store.last_flip["line"]) == 4, "and the flip record says so too")
	near(al.marks()[4], 0.0, 1e-6, "the pressure that turned it is spent")
	check(al.days_toward()[4] == 0, "and the run of days went with it")
	al.unbind()


func _test_decay_forgets() -> void:
	print("\n[ evidence that stops being repeated stops counting ]")
	var al: Alchemy = _rig(3)
	var t: int = 200 * DAY
	al.nudge(1, false, 1.0, t)
	al.nudge(1, false, 1.0, t + 1000)
	al.nudge(1, false, 1.0, t + 2000)
	near(al.marks()[1], -0.75, 1e-5, "three yin pushes lean the mark to -0.75")
	check(absf(al.marks()[1]) >= al.mark_threshold, "which is over the threshold")
	al.tick(t + 5 * DAY)
	check(absf(al.marks()[1]) < al.mark_threshold,
		"five days later it has leaked back under (%.4f)" % al.marks()[1])
	check(al.marks()[1] < 0.0, "without ever changing sign")
	al.tick(t + 200 * DAY)
	near(al.marks()[1], 0.0, 1e-5, "and a long silence forgets it entirely")
	check(al.days_toward()[1] == 0, "a forgotten mark takes its days with it")
	al.unbind()


func _test_a_broken_run_starts_again() -> void:
	print("\n[ a day of yin is not half a day of yang ]")
	var al: Alchemy = _rig(3)
	var t: int = 300 * DAY
	al.nudge(0, true, 1.0, t)
	al.nudge(0, true, 1.0, t + DAY)
	check(al.days_toward()[0] == 2, "two days of yang banked")
	check(not al.nudge(0, false, 1.0, t + 2 * DAY), "then the evidence turns around")
	check(al.days_toward()[0] == 1, "and the run starts over at one day")
	near(al.marks()[0], 0.25, 1e-5, "the mark only walks back, it does not jump")
	check(not al.nudge(0, false, 1.0, t + 3 * DAY), "a second yin day")
	check(not al.nudge(0, false, 1.0, t + 4 * DAY), "a third, and the mark has only just crossed back")
	check(al.days_toward()[0] == 3, "three yin days banked all the same")
	check((al._store.body_bits() & 1) == 0, "and line 0 has not turned yin -- it already was")
	al.unbind()


func _test_flip_days_zero_is_the_old_body() -> void:
	print("\n[ flip_days 0 is the body that was always here ]")
	var al: Alchemy = _rig(0)
	check(al.flip_days == 0, "the dial is down")
	var heard: Array = []
	al.line_flipped.connect(func(f: Dictionary) -> void: heard.append(f))
	check(al.nudge(3, true, 1.0, 400 * DAY), "one push turns line 3 on the spot")
	check((al._store.body_bits() >> 3) & 1 == 1, "the body carries it immediately")
	check(heard.size() == 1, "and it was announced once")
	near(al.marks()[3], 0.0, 1e-6, "no mark was banked, because none was needed")
	check(al.days_toward()[3] == 0, "and no day was counted")
	check(al.nudge(3, false, 1.0, 400 * DAY + 1), "and it turns straight back")
	check((al._store.body_bits() >> 3) & 1 == 0, "with no hysteresis in the way")
	al.unbind()


func _test_state_exposes_the_pressure() -> void:
	print("\n[ the glass can read the lean before the turn ]")
	var al: Alchemy = _rig(3)
	var st: Dictionary = al.state()
	check(st.has("marks") and st.has("days_toward"), "state carries marks and days_toward")
	check((st["marks"] as Array).size() == 6, "six marks, one per line")
	check((st["days_toward"] as Array).size() == 6, "six day counts")
	check(int(st["flip_days"]) == 3, "and the gate it is being held against")
	al.nudge(5, true, 1.0, 500 * DAY)
	var st2: Dictionary = al.state()
	near(float((st2["marks"] as Array)[5]), 0.25, 1e-5, "a push shows up in state")
	check(int((st2["days_toward"] as Array)[5]) == 1, "with its one day")
	var copy: Array = st2["marks"] as Array
	copy[5] = 99.0
	near(al.marks()[5], 0.25, 1e-5, "and what state hands out is a copy, not the accumulator")
	al.unbind()


func _test_a_cast_spends_the_pressure() -> void:
	print("\n[ a cast lands whole and settles the argument ]")
	var al: Alchemy = _rig(3)
	var t: int = 600 * DAY
	al.nudge(1, true, 1.0, t)
	al.nudge(1, true, 1.0, t + DAY)
	near(al.marks()[1], 0.5, 1e-5, "line 1 is leaning yang")
	## The cast puts line 1 yang itself, so the pressure toward yang is spent.
	al.inject(0b000010, t + 2 * DAY, "tap")
	check(al._store.body_bits() == 0b000010, "the cast landed whole, as it always has")
	near(al.marks()[1], 0.0, 1e-6, "and the line it moved has no pressure left")
	check(al.days_toward()[1] == 0, "nor any days")
	## A line the cast agreed with banks a day of standing-still evidence.
	al.inject(0b000010, t + 3 * DAY, "tap")
	near(al.marks()[1], 0.25, 1e-5, "casting the same figure again banks evidence for keeping it")
	check(al.days_toward()[1] == 1, "one day of it")
	al.unbind()
