extends SceneTree

## TEST CORE SENSES -- the sixteen, the two elections, and the tap that outranks
## them. Headless, no device, no plugin: every reading here is a Dictionary
## written by hand, which is the whole point of the telemetry contract.

const HexyStoreScript = preload("res://scripts/core/store.gd")
const SensesScript = preload("res://scripts/senses/senses.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	print("\n--- TEST CORE SENSES (16 senses + election) ---")

	_test_absent()
	_test_crafted()
	_test_negative_states()
	_test_election()
	_test_tap_blocks_figure()
	_test_lattice_spike()
	_test_tools()

	if failures == 0:
		print("--- ALL CORE SENSES TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CORE SENSES TESTS FAILED: ", failures, " ---\n")
		quit(1)


# -- helpers -----------------------------------------------------------------

static func is_ascii(s: String) -> bool:
	for i in range(s.length()):
		var c: int = s.unicode_at(i)
		if c < 32 or c > 126:
			return false
	return true


func new_senses() -> Senses:
	return SensesScript.new() as Senses


## Every sense, in one flat list, labelled for the report.
func each_sense(rig: Senses) -> Array:
	var out: Array = []
	for i in range(8):
		out.append(["machine %d %s" % [i, rig.machine[i].label()], rig.machine[i]])
	for i in range(8):
		out.append(["human %d %s" % [i, rig.human[i].label()], rig.human[i]])
	return out


# -- 1. nothing sensed -------------------------------------------------------

func _test_absent() -> void:
	var rig: Senses = new_senses()
	var empty: Dictionary = {}
	var bad: int = 0
	for row in each_sense(rig):
		var name: String = row[0]
		var s: Sense = row[1]
		s.tick(1000, empty)
		# A sense that can name what it lacks says so; one that cannot falls
		# back to "not sensed". Both are absence, neither is a zero reading.
		var want: String = Sense.NOT_SENSED
		if s.needs() != "":
			want = "needs %s" % s.needs()
		if s.present() or s.score() != 0.0 or s.sentence() != want:
			bad += 1
			print("  absent-mismatch: ", name, " present=", s.present(),
				" score=", s.score(), " sentence=", s.sentence())
	check(bad == 0, "all 16 senses with empty telemetry are not sensed, score 0")

	var named: int = 0
	for row in each_sense(rig):
		var s2: Sense = row[1]
		if s2.needs() != "" and s2.sentence() == ("needs %s" % s2.needs()):
			named += 1
	check(named >= 8, "senses that want a plugin say needs <x>, not not sensed")
	check(rig.sense(Sense.MACHINE, 2).sentence() == "needs android battery",
		"battery with no key says needs android battery")
	check(rig.sense(Sense.MACHINE, 3).sentence() == "needs ixvoice",
		"acoustic with no key says needs ixvoice")
	check(rig.sense(Sense.MACHINE, 0).sentence() == "needs ixloc",
		"sanctuary with no key says needs ixloc")
	check(rig.sense(Sense.HUMAN, 7).sentence() == "needs ixbody",
		"posture with no key says needs ixbody")

	var families_ok: bool = true
	for i in range(8):
		if rig.machine[i].family() != Sense.MACHINE or rig.machine[i].index() != i:
			families_ok = false
		if rig.human[i].family() != Sense.HUMAN or rig.human[i].index() != i:
			families_ok = false
		if rig.machine[i].trigram_name() != Sense.TRIGRAMS[i]:
			families_ok = false
		if rig.human[i].trigram_name() != Sense.TRIGRAMS[i]:
			families_ok = false
	check(families_ok, "families, indices 0..7 and trigram names line up")
	rig.free()


# -- 2. crafted telemetry ----------------------------------------------------

## Each entry: label, family, index, and the ticks to feed, oldest first.
func crafted() -> Array:
	return [
		["sanctuary", Sense.MACHINE, 0, [[0, {"location": {"lat": 51.5, "lon": -0.12, "acc": 8.0}}]]],
		["thermal", Sense.MACHINE, 1, [[0, {"charging": true, "battery_temp_c": 38.0}]]],
		["battery", Sense.MACHINE, 2, [[0, {"battery_pct": 10.0}]]],
		["acoustic", Sense.MACHINE, 3, [[0, {"mic_db": 70.0, "speech": false}]]],
		["desk_rest", Sense.MACHINE, 4, [[0, {"gravity": Vector3(0, 0, -9.8), "touch_rate": 0.0}]]],
		["light", Sense.MACHINE, 5, [[0, {"lux": 5000.0}]]],
		["geomagnetic", Sense.MACHINE, 6, [[0, {"magnet": Vector3(0, 50, 0)}]]],
		["circadian", Sense.MACHINE, 7, [[0, {"local_hour": 12.0, "offset_ms": 0.0}]]],
		["sleep", Sense.HUMAN, 0, [[0, {"local_hour": 2.0, "lux": 0.0,
			"accel": Vector3(0, -9.8, 0), "screen_on": false}]]],
		["locomotion", Sense.HUMAN, 1, [[0, {"steps_per_min": 110.0}]]],
		["hydration", Sense.HUMAN, 2, [[20000000, {"last_drink_ms": 8000000.0}]]],
		["grip", Sense.HUMAN, 3, [[0, {"accel": Vector3(0, -9.5, 3.58), "touch_rate": 1.0}]]],
		["deep_work", Sense.HUMAN, 4, [[0, {"gravity": Vector3(0, 0, 9.8), "screen_on": false}]]],
		["gaze", Sense.HUMAN, 5, [[0, {"face_on": true, "touch_rate": 2.0}]]],
		["breath", Sense.HUMAN, 6, [[0, {"accel": Vector3(0, 0, 9.92)}]]],
		["posture", Sense.HUMAN, 7, [[0, {"pose_upright": 1.0, "gravity": Vector3(0, -9.8, 0)}]]],
	]


func _test_crafted() -> void:
	var rig: Senses = new_senses()
	var weak: int = 0
	var unsaid: int = 0
	for row in crafted():
		var name: String = row[0]
		var s: Sense = rig.sense(int(row[1]), int(row[2]))
		for step in (row[3] as Array):
			s.tick(int((step as Array)[0]), (step as Array)[1] as Dictionary)
		if not s.present() or s.score() <= 0.6:
			weak += 1
			print("  weak: ", name, " present=", s.present(), " score=", s.score())
		var line: String = s.sentence()
		if line == Sense.NOT_SENSED or line.length() > 60 or not is_ascii(line):
			unsaid += 1
			print("  bad sentence: ", name, " len=", line.length(), " [", line, "]")
	check(weak == 0, "all 16 senses score above 0.6 on their own telemetry")
	check(unsaid == 0, "all 16 sentences are ASCII and 60 characters or fewer")

	# The windowed senses must rise, not merely clear the floor.
	var loco: Sense = rig.sense(Sense.HUMAN, 1)
	var floor_score: float = loco.score()
	loco.tick(600000, {"steps_per_min": 110.0})
	check(loco.score() > floor_score,
		"a held window lifts the reading above its first-tick floor")
	rig.free()


# -- 2b. a present sense that reads NO says NO ------------------------------

## THE DESK AT 13:07. Every reading below was taken from a Samsung A22 lying
## flat, face up, screen on, at one in the afternoon. The old sixteen answered
## it with "night, dark and still", "face down, screen off" and "held in a
## hand" -- three sentences about a phone that was none of those things.
func _test_negative_states() -> void:
	var rig: Senses = new_senses()
	var desk: Dictionary = {
		"local_hour": 13.116,
		"gravity": Vector3(0.05, 0.1, -9.79),
		"accel": Vector3(0.05, 0.1, -9.79),
		"screen_on": true,
		"touch_rate": 0.0,
	}

	var sleep: Sense = rig.sense(Sense.HUMAN, 0)
	sleep.tick(0, desk)
	check(sleep.present(), "sleep is present: the clock is there")
	check(sleep.score() == 0.0, "daytime with the screen on scores sleep 0")
	check(sleep.sentence() == "day, screen on",
		"sleep says day, screen on -- got: %s" % sleep.sentence())

	var deep: Sense = rig.sense(Sense.HUMAN, 4)
	deep.tick(0, desk)
	check(deep.score() == 0.0, "face up with the screen on scores deep work 0")
	check(deep.sentence() == "face up, screen on",
		"deep work says face up, screen on -- got: %s" % deep.sentence())

	var grip: Sense = rig.sense(Sense.HUMAN, 3)
	grip.tick(0, desk)
	check(grip.score() == 0.0, "a phone flat on a desk is not held")
	check(grip.sentence() == "not held, flat on a surface",
		"grip says not held -- got: %s" % grip.sentence())

	var desk_rest: Sense = rig.sense(Sense.MACHINE, 4)
	desk_rest.tick(0, desk)
	check(desk_rest.score() > 0.6, "the same phone IS flat on a surface")
	check(grip.score() == 0.0 or desk_rest.score() == 0.0,
		"grip and desk rest are never both true")

	# Night, screen off, still: the same sense says the opposite thing.
	var night: Dictionary = {
		"local_hour": 2.0, "screen_on": false, "accel": Vector3(0, -9.8, 0),
	}
	sleep.reset()
	sleep.tick(0, night)
	check(sleep.score() > 0.6 and sleep.sentence() == "night, dark and still",
		"night with the screen off still reads as sleep")

	# Turned over, screen off: deep work, with the corrected sign.
	var over: Dictionary = {"gravity": Vector3(0, 0, 9.79), "screen_on": false}
	deep.reset()
	deep.tick(0, over)
	check(deep.score() > 0.6 and deep.sentence() == "face down, screen off",
		"face down (gravity.z positive) with the screen off is deep work")

	# A hand: not flat, and jittering.
	var hand: Dictionary = {"accel": Vector3(0.2, -9.4, 3.6), "touch_rate": 1.0}
	grip.reset()
	grip.tick(0, hand)
	check(grip.score() > 0.6 and grip.sentence().begins_with("held in a hand"),
		"a tilted, touched phone is held -- got: %s" % grip.sentence())

	# Not flat, but no jitter and no finger: still not a hand.
	var shelf: Dictionary = {"accel": Vector3(0.0, -9.8, 0.0), "touch_rate": 0.0}
	grip.reset()
	grip.tick(0, shelf)
	grip.tick(4000, shelf)
	grip.tick(8000, shelf)
	check(grip.score() == 0.0, "upright and perfectly still is furniture, not a hand")

	rig.free()


# -- 3. the election ---------------------------------------------------------

## Low battery is the machine's loudest voice (2, Water); a face on the glass
## is the human's (5, Fire). (5 << 3) | 2 == 42.
static func election_telemetry() -> Dictionary:
	return {"battery_pct": 8.0, "face_on": true, "touch_rate": 2.0}


func _test_election() -> void:
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	var rig: Senses = new_senses()
	rig.bind(store)

	rig.tick(100000, election_telemetry())
	rig.tick(104000, election_telemetry())

	check(store.machine["trigram"] == 2, "machine elects 2 (Water, battery)")
	check(store.human["trigram"] == 5, "human elects 5 (Fire, gaze)")
	check(store.hexagram["bits"] == 42, "two elections make bits 42")
	check(String(store.hexagram["source"]) == "senses", "the figure's source is senses")
	check(store.machine["score"] > 0.6 and store.machine["sentence"] != "",
		"machine dict carries a score and a sentence")
	check(store.human["score"] > 0.6 and store.human["sentence"] != "",
		"human dict carries a score and a sentence")

	rig.free()
	store.free()


# -- 4. a tap holds the figure, not the lines --------------------------------

func _test_tap_blocks_figure() -> void:
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	var rig: Senses = new_senses()
	rig.bind(store)

	var now: int = 1000000
	store.set_hexagram({
		"bits": 63, "moving": 0, "throws": [], "when": now - 60000,
		"who": "me", "source": "tap", "sig": "",
	})
	rig.tick(now, election_telemetry())
	rig.tick(now + 4000, election_telemetry())

	check(store.hexagram["bits"] == 63, "a tap 1 minute old keeps its figure")
	check(String(store.hexagram["source"]) == "tap", "the tap keeps its source")
	check(store.machine["trigram"] == 2 and store.human["trigram"] == 5,
		"machine and human lines keep updating under a fresh tap")

	# Six minutes on, the tap has lapsed and the senses may speak again.
	store.set_hexagram({
		"bits": 63, "moving": 0, "throws": [], "when": now - 360000,
		"who": "me", "source": "tap", "sig": "",
	})
	rig.tick(now + 8000, election_telemetry())
	check(store.hexagram["bits"] == 42 and String(store.hexagram["source"]) == "senses",
		"a tap 6 minutes old no longer blocks the senses")

	rig.free()
	store.free()


# -- 5. one tick of anything is not a figure ---------------------------------

func _test_lattice_spike() -> void:
	var store: HexyStore = HexyStoreScript.new() as HexyStore
	var rig: Senses = new_senses()
	rig.bind(store)

	rig.tick(0, election_telemetry())
	rig.tick(4000, election_telemetry())
	check(store.hexagram["bits"] == 42, "the figure settles at 42")

	# One tick of blazing light and a walk. Neither may take the seat.
	var spike: Dictionary = {"lux": 20000.0, "steps_per_min": 140.0}
	rig.tick(8000, spike)
	check(store.hexagram["bits"] == 42, "a one-tick spike does not change the figure")
	check(store.machine["trigram"] == 2 and store.human["trigram"] == 5,
		"a one-tick spike does not change either trigram")

	# Held for a second tick, it is no longer a spike and the seat changes.
	rig.tick(12000, spike)
	check(store.machine["trigram"] == 5 and store.human["trigram"] == 1,
		"a challenger held for two ticks takes the seat")

	rig.free()
	store.free()


# -- 6. the plus sheet -------------------------------------------------------

func _test_tools() -> void:
	var rig: Senses = new_senses()
	var found: bool = false
	for tool in rig.tools():
		if String((tool as Dictionary).get("id", "")) == "water":
			found = true
			check(String((tool as Dictionary).get("label", "")) == "water",
				"the water tool is labelled water")
	check(found, "tools() contains the water tool")
	rig.free()
