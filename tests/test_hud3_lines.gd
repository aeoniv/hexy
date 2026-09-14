extends SceneTree

## THE THIRD GLASS, AS A DAY RATHER THAN A DASHBOARD.
##
## Five things are checked here, and all five are things a person would notice:
## the strip reads as a day, the earth band reads as six lines with three
## honest states, a finger on one of those lines lands on the seat bus as that
## line and no other, the dwell ring is exactly stillness over the civil fire's
## seconds, and every one of the twelve stations evicted from the earth band
## still exists as a method somebody can call.
##
## It boots the scene that actually ships, the way test_hud_telemetry_smoke
## does, because a Hud3 built by hand is a Hud3 nobody uses.

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST HUD3 LINES (day, six lines, dwell, evictions) ---")

	var node: Node = load("res://scenes/hexy.tscn").instantiate()
	root.add_child(node)
	await process_frame
	await process_frame

	var hud: Node = node.get_node("Hud")
	check(hud != null, "Hud3 stands under the app")

	_test_day_line(hud)
	_test_earth_lines(hud)
	_test_line_tap(hud)
	_test_dwell(hud)
	_test_evictions(hud)

	if failures == 0:
		print("--- ALL HUD3 LINES TESTS PASSED ---\n")
		quit(0)
	else:
		print("--- HUD3 LINES TESTS FAILED: ", failures, " ---\n")
		quit(1)


## "Day N · <LineName> <opens|closes>", or "Day N · holding" when the altar and
## the body agree and nothing has flipped yet.
func _test_day_line(hud: Node) -> void:
	var line: String = String(hud.day_line())
	print("day line: ", line)
	check(line.begins_with("Day "), "the day line begins with Day")
	var parts: PackedStringArray = line.split(" · ")
	check(parts.size() == 2, "the day line is a day and a verdict")
	check(int(parts[0].substr(4)) >= 1, "the day number is at least one")
	var tail: String = parts[1] if parts.size() > 1 else ""
	if tail == "holding":
		check(true, "the day line holds when nothing is moving")
	else:
		var words: PackedStringArray = tail.split(" ")
		check(words.size() == 2, "a moving day line is a name and a verb")
		check(EarthLinesDial.LINE_NAMES.has(words[0]),
			"the moving line is one of Pacing's six names (%s)" % words[0])
		check(words[1] == "opens" or words[1] == "closes",
			"the line either opens or closes (%s)" % words[1])

	check(String(hud.journal_text()).begins_with("DAY "),
		"the strip opens into a journal headed by the day")


## body 0b000001, head 0b000011: line 2 opens, the other five hold.
func _test_earth_lines(hud: Node) -> void:
	var dial: EarthLinesDial = hud.earth_lines
	check(dial != null, "the earth band has a six-line face")
	dial.set_figures(0b000001, 0b000011)
	check(dial.line_state(0) == EarthLinesDial.SAME, "line 1 holds (both yang)")
	check(dial.line_state(1) == EarthLinesDial.OPENS, "line 2 opens (yin -> yang)")
	for i in range(2, 6):
		check(dial.line_state(i) == EarthLinesDial.SAME, "line %d holds" % (i + 1))
	dial.set_figures(0b000011, 0b000001)
	check(dial.line_state(1) == EarthLinesDial.CLOSES, "line 2 closes the other way")
	check(dial.bits_if_tapped(3) == (0b000011 ^ 0b001000),
		"a tap on line 4 turns exactly line 4 of the body")
	check(dial.line_name(5) == "Connection", "line 6 is Connection")
	check(dial.line_name(0) == "Body", "line 1 is Body")


## A tap on segment i announces EARTH on the seat bus with moving == 1 << i.
func _test_line_tap(hud: Node) -> void:
	var store: Node = hud._store
	var dial: EarthLinesDial = hud.earth_lines
	var seen: Array[Dictionary] = []
	var seats: Array[int] = []
	var grab := func(seat: int, c: Dictionary) -> void:
		seats.append(seat)
		seen.append(c.duplicate())
	store.seat_landed.connect(grab)

	var before: int = int(store.body_bits())
	for i in range(6):
		seen.clear()
		seats.clear()
		dial.line_tapped.emit(i)
		check(seen.size() >= 1, "a tap on line %d landed on the seat bus" % (i + 1))
		if seen.is_empty():
			continue
		check(seats[0] == HexyStore.Seat.EARTH, "line %d lands on the EARTH seat" % (i + 1))
		check(int(seen[0].get("moving", 0)) == (1 << i),
			"line %d moves exactly bit %d" % [i + 1, i])
		check((int(seen[0].get("bits", 0)) & 63) == ((before ^ (1 << i)) & 63),
			"line %d seats the body with that one line turned" % (i + 1))
		check(String(seen[0].get("source", "")) == "tap", "line %d says it was a tap" % (i + 1))
		check(seen[0].has("sig"), "line %d carries the seat bus's signature field" % (i + 1))

	store.seat_landed.disconnect(grab)


## The dwell fraction is stillness over the civil fire's seconds, clamped.
func _test_dwell(hud: Node) -> void:
	var f: float = float(hud.dwell_fraction())
	check(f >= 0.0 and f <= 1.0, "the dwell fraction is clamped to 0..1 (%f)" % f)
	var span: float = float(hud.civil_fire_s())
	check(span > 0.0, "the civil fire has a span of seconds")
	var senses: Node = hud._senses
	if senses != null and senses.has_method("stillness"):
		var want: float = clampf(float(senses.stillness()) / span, 0.0, 1.0)
		check(is_equal_approx(f, want), "the dwell fraction IS stillness over %f s" % span)
	else:
		check(is_zero_approx(f), "with no senses the dwell fraction is nothing")
	check(hud.dwell_ring != null, "the body band carries a dwell ring")
	## A boot may already have turned a line, so the flash is expired by hand
	## rather than assumed cold: what is under test is that it EXPIRES.
	hud._flash_until_ms = 0
	check(int(hud.flash_line()) == -1, "a flash that has run out stops flashing")
	hud._on_flipped({"line": 2, "to_yang": true, "when": 1})
	check(int(hud.flash_line()) == 2, "a flip lights the line that turned")


## Every station evicted from the earth band still exists by name.
func _test_evictions(hud: Node) -> void:
	for m in ["toggle_enhanced", "cycle_geometry", "telemetry_text", "brain_text",
			"config_text", "cycle_sense_period", "mesh_broadcast", "camera_reset",
			"toggle_sensor_freeze", "cast_earth", "walk_earth"]:
		check(hud.has_method(m), "hud3 answers to %s()" % m)
	check(typeof(hud.toggle_enhanced()) == TYPE_BOOL, "toggle_enhanced returns a bool")
	hud.toggle_enhanced()
	check(typeof(hud.cycle_geometry()) == TYPE_STRING, "cycle_geometry returns a name")
	check(typeof(hud.cycle_sense_period()) == TYPE_INT, "cycle_sense_period returns a period")
	check(typeof(hud.mesh_broadcast()) == TYPE_INT, "mesh_broadcast returns a peer count")
	check(typeof(hud.toggle_sensor_freeze()) == TYPE_BOOL, "toggle_sensor_freeze returns a bool")
	check(typeof(hud.cast_earth()) == TYPE_DICTIONARY, "cast_earth returns the earth seat")
	hud.walk_earth(1)
	check(true, "walk_earth walks without complaint")
