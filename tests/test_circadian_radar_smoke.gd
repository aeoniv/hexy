extends MainLoop

const FlyCircadianClockScript := preload("res://scripts/brain/fly_circadian_clock.gd")
const FlyCalciumRadar2DScript := preload("res://scripts/brain/fly_calcium_radar_2d.gd")
const FlyCentralComplexScript := preload("res://scripts/brain/fly_central_complex.gd")
const CharacterScript := preload("res://scripts/brain/character.gd")
const GeoScript := preload("res://scripts/core/geo.gd")
const Hud3Script := preload("res://scripts/glass/hud3.gd")
const WmnScript := preload("res://scripts/core/wmn/wmn.gd")

var passes := 0
var failures := 0


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func _process(_delta: float) -> bool:
	print("HEXY_TEST: Running Circadian Clock & Calcium Radar Smoke Tests...")
	_test_circadian_clock()
	_test_calcium_radar_component()
	_test_room_inside_the_ring()
	_test_north_up()
	_test_log_rings()
	_test_trust_band()
	_test_tap_and_guide()
	_test_caption()
	_test_glass_wiring()
	_test_phase_and_mentor()
	
	print("\n=== CIRCADIAN & RADAR RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Circadian & Radar Verified)")
	return true


func _test_circadian_clock() -> void:
	print("\n• Testing FlyCircadianClock (s-LNv & l-LNv Pacemakers + PDF)...")
	var clock: RefCounted = FlyCircadianClockScript.new()
	
	# Test 1: Dawn Morning Peak (~07:00 AM)
	clock.update(7.0)
	var dawn_mods: Dictionary = clock.get_circadian_modifiers()
	check(dawn_mods["morning_drive"] > 0.85, "Morning drive surges at dawn (got %.3f > 0.85)" % dawn_mods["morning_drive"])
	check(dawn_mods["pdf_level"] > 0.65, "PDF neuropeptide peaks at dawn (got %.3f > 0.65)" % dawn_mods["pdf_level"])
	check(dawn_mods["da_boost"] > 0.20, "Dopamine motor vigor is boosted at dawn")
	check(dawn_mods["phase_name"].contains("Morning"), "Phase name identifies Morning Dawn")
	
	# Test 2: Night Torpor (~02:00 AM)
	clock.update(2.0)
	var night_mods: Dictionary = clock.get_circadian_modifiers()
	check(night_mods["pdf_level"] < 0.15, "PDF drops to trough during night torpor (got %.3f < 0.15)" % night_mods["pdf_level"])
	check(night_mods["dfb_permissiveness"] > 0.85, "dFB sleep permissiveness unlocks at night (got %.3f > 0.85)" % night_mods["dfb_permissiveness"])
	check(night_mods["phase_name"].contains("Night"), "Phase name identifies Night Torpor")
	
	# Test 3: Evening Twilight (~18:30 PM)
	clock.update(18.5)
	var eve_mods: Dictionary = clock.get_circadian_modifiers()
	check(eve_mods["evening_drive"] > 0.85, "Evening drive peaks at dusk (got %.3f > 0.85)" % eve_mods["evening_drive"])
	check(eve_mods["phase_name"].contains("Evening"), "Phase name identifies Evening Twilight")


func _test_calcium_radar_component() -> void:
	print("\n• Testing FlyCalciumRadar2D Visual Component Lifecycle...")
	var radar: Control = FlyCalciumRadar2DScript.new()
	var cx: RefCounted = FlyCentralComplexScript.new()
	var ch: RefCounted = CharacterScript.new()
	
	radar.central_complex = cx
	radar.character = ch
	radar.size = Vector2(240, 280)
	
	check(radar.TRIGRAM_NAMES.size() == 8, "Calcium radar has 8 Bagua trigrams")
	check(radar.NEURO_NAMES.size() == 6, "Calcium radar has 6 neuromodulator meters")
	check(radar.custom_minimum_size.x >= 220, "Custom minimum size is >= 220 px")
	
	radar.free()


## THE ROOM INSIDE THE RING: the peer dial and the calcium dial are one Control.
func _test_room_inside_the_ring() -> void:
	print("
• Testing the peer field inside the calcium ring...")
	var radar: Control = FlyCalciumRadar2DScript.new()
	radar.radar_radius = 100.0
	radar.ring_thickness = 20.0
	check(radar.peer_plots().is_empty(), "no peers, no blips")
	check(radar.field_radius() < radar.radar_radius - radar.ring_thickness * 0.5, "the field stays inside the wedge track")

	radar.set_peer_headings({"a": 1.0, "b": 2.0})
	var plots: Dictionary = radar.peer_plots()
	check(plots.size() == 2, "one blip per peer that pulsed")
	check(String(plots["a"]["cls"]) == "room", "a peer with no proximity parks on the room ring")
	check(is_equal_approx(float(plots["a"]["angle"]), 1.0), "without a bearing the blip sits at the peer's own fly heading")
	check(not bool(plots["a"]["bearing"]), "and says so: no bearing claimed")

	radar.set_peer_proximity({"a": "touch", "b": "far", "c": "room"})
	plots = radar.peer_plots()
	check(plots.size() == 3, "a peer known only by proximity is still plotted")
	check(float(plots["a"]["frac"]) < float(plots["c"]["frac"]) and float(plots["c"]["frac"]) < float(plots["b"]["frac"]),
		"touch < room < far in radius")
	check(float(plots["b"]["frac"]) < 1.0, "the far ring is still inside the field")

	radar.note_proximity("a", "nonsense")
	check(String(radar.peer_plots()["a"]["cls"]) == "room", "an unknown class falls to the default ring")

	radar.set_peer_bearings({"a": 3.0})
	plots = radar.peer_plots()
	check(is_equal_approx(float(plots["a"]["angle"]), 3.0), "a real bearing wins over the fly heading")
	check(bool(plots["a"]["bearing"]), "and the blip grows a nose")
	check(is_equal_approx(float(plots["b"]["angle"]), 2.0), "a peer without a bearing keeps its heading")

	radar.drop_peer("a")
	check(not radar.peer_plots().has("a"), "a dropped peer leaves every map")
	check(radar.peer_plots().size() == 2, "and the others stay")

	# It draws without a tree blowing up.
	radar.size = Vector2(240, 280)
	radar.free()
	check(true, "the merged radar frees cleanly")


## A live compass, and one fresh fed radar to hang it on.
func _radar(w: float = 240.0) -> Control:
	var r: Control = FlyCalciumRadar2DScript.new()
	r.radar_radius = 100.0
	r.ring_thickness = 20.0
	r.size = Vector2(w, 300.0)
	return r


func _live(deg: float, acc: int = GeoScript.ACC_HIGH) -> Dictionary:
	return {"heading_rad": deg_to_rad(deg), "accuracy": acc, "pose": GeoScript.POSE_UPRIGHT,
		"live": true, "seen": true, "true_north": false, "declination": 0.0}


## NORTH-UP: THE PEERS MOVE AND YOU DO NOT. When the compass is live the whole
## field turns so that screen-up is the way the phone faces. When it is not, or
## when it may not be believed, the dial is the allocentric disc it always was.
func _test_north_up() -> void:
	print("\n- north-up: the whole peer field turns, and nothing of yours does")
	var r: Control = _radar()
	r.set_peer_headings({"a": 0.0, "b": PI * 0.5})
	check(not r.north_up(), "cold, the dial is allocentric")
	check(is_zero_approx(r.frame_offset()), "so nothing is subtracted from anybody")
	var plots: Dictionary = r.peer_plots()
	check(is_equal_approx(float(plots["a"]["screen"]), float(plots["a"]["angle"])),
		"and a blip's screen angle is its own angle")

	# Facing north. A peer at allocentric 0 -- due north of us -- must land at
	# screen-up, which in draw coordinates is three quarters of a turn.
	r.set_compass(_live(0.0))
	check(r.north_up(), "a live, trusted compass turns the picture")
	plots = r.peer_plots()
	check(is_equal_approx(float(plots["a"]["screen"]), TAU * 0.75),
		"the peer you are facing sits at the top of the disc")
	check(is_equal_approx(float(plots["a"]["angle"]), 0.0),
		"while their allocentric angle is untouched -- it is a fact about them")

	# Turn a quarter turn to the right. The peer swings a quarter turn the other
	# way, which is the only motion on this screen.
	r.set_compass({"heading_rad": PI * 0.5})
	plots = r.peer_plots()
	check(is_equal_approx(float(plots["b"]["screen"]), TAU * 0.75),
		"turn 90 degrees and the peer that is now ahead of you comes to the top")
	check(is_equal_approx(float(plots["a"]["screen"]), PI),
		"and the one that was ahead swings to the left")

	# AND THE ROTATION IS CONDITIONAL. A compass the field magnitude disowned
	# stops the picture rather than turning it confidently.
	r.set_compass({"accuracy": GeoScript.ACC_LOW})
	check(not r.north_up(), "at LOW accuracy nothing rotates")
	check(r.compass_unreliable(), "and the dial knows to say why")
	plots = r.peer_plots()
	check(is_equal_approx(float(plots["a"]["screen"]), 0.0), "the peers are back in the allocentric frame")
	r.set_compass({"accuracy": GeoScript.ACC_UNRELIABLE})
	check(not r.north_up(), "and at UNRELIABLE too")
	r.set_compass({"accuracy": GeoScript.ACC_HIGH, "live": false})
	check(not r.north_up(), "a compass that has gone quiet does not turn anything either")
	r.free()


## THE LOG RINGS EXIST ONLY WHERE THERE ARE METRES.
func _test_log_rings() -> void:
	print("\n- 10 m / 100 m / 1 km, and only when somebody measured metres")
	var r: Control = _radar()
	r.set_peer_headings({"a": 0.0, "b": 0.0})
	r.set_peer_proximity({"a": "touch", "b": "far"})
	check(not r.has_metres(), "no metres, no metric scale")
	var plots: Dictionary = r.peer_plots()
	check(not bool(plots["a"]["log"]), "a peer with no distance keeps the proximity ring")
	check(is_equal_approx(float(plots["a"]["frac"]), r.ring_frac("touch")), "at the touch radius")
	check(float(plots["a"]["dist_m"]) < 0.0, "and claims no metres")

	r.set_peer_distances_m({"a": 10.0, "b": 1000.0})
	check(r.has_metres(), "metres put the log rings on the glass")
	plots = r.peer_plots()
	check(bool(plots["a"]["log"]) and bool(plots["b"]["log"]), "both peers move onto them")
	check(is_equal_approx(float(plots["a"]["frac"]), FlyCalciumRadar2DScript.log_frac(10.0)),
		"10 m sits on the first ring")
	check(is_equal_approx(float(plots["b"]["frac"]), 1.0), "and 1 km on the rim")
	check(float(plots["a"]["frac"]) < float(plots["b"]["frac"]), "near is inside far")
	# Three decades, evenly spaced: that is what RING_DECADES buys.
	var hub: float = FlyCalciumRadar2DScript.HUB_FRAC
	check(is_equal_approx(FlyCalciumRadar2DScript.log_frac(1.0), hub), "1 m sits on the hub")
	check(is_equal_approx(FlyCalciumRadar2DScript.log_frac(0.2), hub), "and so does anything nearer")
	check(is_equal_approx(FlyCalciumRadar2DScript.log_frac(40000.0), 1.0),
		"a peer 40 km away is drawn on the rim, not off the screen")
	check(int(FlyCalciumRadar2DScript.RING_DECADES) == 3, "three decades")
	check(FlyCalciumRadar2DScript.RING_M.size() == 3 and FlyCalciumRadar2DScript.RING_LABELS.size() == 3,
		"three rings, three labels")
	# A distance nobody really measured is not a distance.
	r.set_peer_distances_m({"a": 0.0, "b": 50.0})
	check(not r.peer_plots()["a"]["log"], "a zero distance is an unfilled field, not a measurement")
	r.free()


## THE TRUST BAND RIDES THE PEER'S OWN RING, AND NOTHING STARTS AT THE CENTRE.
func _test_trust_band() -> void:
	print("\n- how much to believe a bearing, along that peer's own ring")
	var r: Control = _radar()
	r.set_peer_headings({"a": 1.0, "b": 2.0})
	var plots: Dictionary = r.peer_plots()
	check(is_equal_approx(float(plots["a"]["spread"]), GeoScript.SPREAD_MAX_DEG),
		"a blip placed by its own fly heading claims no direction at all")
	check(bool(plots["a"]["ring"]), "so it is drawn as a full ring: somewhere around you")

	r.set_peer_bearings({"a": 1.0})
	plots = r.peer_plots()
	check(is_equal_approx(float(plots["a"]["spread"]), GeoScript.SPREAD_MIN_DEG),
		"a real bearing with no stated spread gets the minimum ink")
	check(not bool(plots["a"]["ring"]), "and is an arc, not a ring")
	check(bool(plots["b"]["ring"]), "the peer without one is still a ring")

	r.set_peer_spreads_deg({"a": 31.0})
	check(is_equal_approx(float(r.peer_plots()["a"]["spread"]), 31.0), "a handed-in spread wins")
	r.set_peer_spreads_deg({"a": 500.0})
	check(is_equal_approx(float(r.peer_plots()["a"]["spread"]), GeoScript.SPREAD_MAX_DEG),
		"and an impossible one is clamped rather than believed")
	check(bool(r.peer_plots()["a"]["ring"]), "past SPREAD_RING_DEG there is no direction left to draw")
	r.free()


## ONE GESTURE IN, THE SAME GESTURE OUT.
func _test_tap_and_guide() -> void:
	print("\n- tap a blip to be guided to them, tap again to let them go")
	var r: Control = _radar()
	r.set_peer_headings({"a": 0.0, "b": PI})
	r.refresh_blips()
	var at: Dictionary = r.blip_positions()
	check(at.size() == 2, "both blips have a place on the glass")
	check(r.blip_at(r.disc_center()) == "", "the empty middle is not anybody")
	check(r.blip_at(at["a"]) == "a", "the point a blip was drawn at hits that blip")
	check(r.guide_id == "", "nothing is being guided to yet")
	check(r.tap(at["b"]) == "b", "a tap on a blip picks them")
	check(r.guide_id == "b", "and that is who the arrow is for")
	check(r.tap(at["a"]) == "", "a second tap cancels, whatever was under the finger")
	check(r.guide_id == "", "one gesture in, the same gesture out")
	check(r.tap(r.disc_center()) == "", "a tap on empty disc guides nobody")

	# The guidance words. They need a compass to turn against.
	r.set_peer_bearings({"a": 0.0, "b": PI})
	r.set_compass(_live(0.0))
	r.refresh_blips()
	r.tap(r.blip_positions()["a"])
	check(r.guide_id == "a", "picked the peer due north")
	check(r.guide_line() == "straight ahead", "and we are already facing them")
	check(FlyCalciumRadar2DScript.ON_TARGET_DEG > 0.0, "there is a window for 'already facing them'")
	r.set_compass({"heading_rad": deg_to_rad(90.0)})
	check(r.guide_line().begins_with("turn left"), "turn ninety degrees and it says to turn back")
	r.set_compass({"heading_rad": deg_to_rad(270.0)})
	check(r.guide_line().begins_with("turn right"), "and from the other side, the other way")
	r.set_compass({"accuracy": GeoScript.ACC_UNRELIABLE})
	check(r.guide_line() == FlyCalciumRadar2DScript.UNRELIABLE_HINT,
		"a compass nothing stands behind gets the hint, not a confident turn")
	r.set_compass({"accuracy": GeoScript.ACC_HIGH, "live": false})
	check(r.guide_line() == "", "and no compass at all says nothing rather than guessing")

	# A peer who walks out takes their guidance with them.
	r.set_compass(_live(0.0))
	r.drop_peer("a")
	check(r.guide_id == "", "the peer being guided to walked out, so the arrow goes with them")
	r.free()


## THE ONE LINE OF PROSE, AND IT SAYS ONLY WHAT DOES NOT MOVE.
func _test_caption() -> void:
	print("\n- the north caption")
	var r: Control = _radar()
	check(r.north_caption() == "no compass", "no sensor has ever spoken: say so plainly")
	r.set_compass(_live(0.0))
	check(r.north_caption().begins_with("magnetic north"),
		"a live compass with nobody to compute a declination is MAGNETIC north")
	check(r.north_caption().contains(GeoScript.POSE_UPRIGHT), "and the pose rides quietly at the end")
	# THE CAPTION MUST NOT MOVE WHEN YOU TURN. That is the whole reason it exists
	# as a function a test can read.
	var said: String = r.north_caption()
	r.set_compass({"heading_rad": deg_to_rad(137.0)})
	check(r.north_caption() == said, "byte-identical at every heading -- nothing of YOURS is on this dial")
	r.set_compass({"true_north": true, "declination": 4.2})
	check(r.north_caption().begins_with("true north"), "a declination makes it TRUE north")
	check(r.north_caption().contains("4.2"), "and the caption names the number it folded in")
	r.set_compass({"accuracy": GeoScript.ACC_LOW})
	check(r.north_caption() == FlyCalciumRadar2DScript.UNRELIABLE_HINT,
		"an uncalibrated compass is told what to do about it")
	check(FlyCalciumRadar2DScript.UNRELIABLE_HINT.contains("figure-8"),
		"which is the gesture the platform's own prompt asks for")
	r.set_compass({"accuracy": GeoScript.ACC_HIGH, "live": false, "seen": true})
	check(r.north_caption().begins_with("compass quiet"),
		"a compass that stopped: the peers show the last heading, and it says so")
	r.free()


## THE GLASS SIDE OF THE SEAM, checked without a viewport: the surface exists,
## the app can hand the compass over, and a peer the fabric drops leaves the
## dial.
func _test_glass_wiring() -> void:
	print("\n- the wiring the app relies on")
	var hud: Object = Hud3Script.new()
	check(hud != null, "the glass parses")
	check(hud.has_method("set_heading"), "the glass takes a compass from the app")
	check(hud.has_method("_on_peer_gone"), "and forwards the fabric's goodbye to the dial")
	check(hud.has_method("_on_radar_input"), "a tap on the disc has somewhere to land")
	hud.free()
	var wmn: Object = WmnScript.new()
	check(wmn.has_signal("peer_gone"), "which is a signal the fabric really emits")
	wmn.free()
	# And the behaviour behind it, which is the part that matters.
	var r: Control = _radar()
	r.set_peer_headings({"a": 0.0, "b": 1.0})
	r.set_peer_proximity({"a": "touch"})
	r.set_peer_distances_m({"a": 12.0})
	r.set_peer_spreads_deg({"a": 20.0})
	r.refresh_blips()
	r.tap(r.blip_positions()["a"])
	check(r.guide_id == "a", "guiding to a peer")
	r.drop_peer("a")
	var plots: Dictionary = r.peer_plots()
	check(not plots.has("a"), "a peer that goes silent leaves the dial")
	check(plots.has("b"), "and takes nobody else with them")
	check(not r.blip_positions().has("a"), "including their hit-test seat")
	check(r.guide_id == "", "and their guidance")
	r.free()

## SAME DAY, ONE CHAPTER AHEAD. The two facts a peer now carries beside its
## heading, and the two flags a glass draws off them. Read through peer_plots,
## never off pixels.
func _test_phase_and_mentor() -> void:
	print("
- who is awake with you, and who is one chapter ahead")
	var r: Control = _radar()
	r.set_peer_headings({"a": 0.0, "b": 1.0, "c": 2.0})
	var plots: Dictionary = r.peer_plots()
	check(float(plots["a"]["phase"]) == -1.0, "a peer who never said has no phase")
	check(int(plots["a"]["stage"]) == -1, "nor a stage")
	check(not bool(plots["a"]["in_phase"]), "and is nobody's company")
	check(not bool(plots["a"]["mentor"]), "nor anybody's mentor")

	# Their side known, ours not: still nothing is claimed.
	r.set_peer_phase({"a": 0.50, "b": 0.65, "c": 0.99})
	r.set_peer_stage({"a": 2, "b": 3, "c": 5})
	plots = r.peer_plots()
	check(is_equal_approx(float(plots["a"]["phase"]), 0.50), "the phase rides on the row")
	check(int(plots["b"]["stage"]) == 3, "and the stage beside it")
	check(not bool(plots["a"]["in_phase"]) and not bool(plots["b"]["mentor"]),
		"a body that has not placed itself recognises nobody")

	# Now we stand somewhere.
	r.set_own_phase(0.52, 2)
	check(is_equal_approx(r.own_phase(), 0.52) and r.own_stage() == 2, "and now it has")
	plots = r.peer_plots()
	check(bool(plots["a"]["in_phase"]), "0.50 against 0.52 is the same two hours of the day")
	check(not bool(plots["b"]["in_phase"]), "0.65 is a long way off it")
	check(bool(plots["b"]["mentor"]), "stage 3 against our 2 is one chapter ahead")
	check(not bool(plots["a"]["mentor"]), "the same chapter is a companion, not a mentor")
	check(not bool(plots["c"]["mentor"]), "three chapters ahead is a stranger again")

	# THE DAY IS A CIRCLE. Just before midnight and just after it are neighbours.
	r.set_own_phase(0.02, 2)
	plots = r.peer_plots()
	check(bool(plots["c"]["in_phase"]), "0.99 and 0.02 are three hundredths apart, not ninety-seven")
	check(is_equal_approx(FlyCalciumRadar2DScript.phase_gap(0.99, 0.02), 0.03),
		"and phase_gap says so in one number")
	check(is_equal_approx(FlyCalciumRadar2DScript.phase_gap(0.0, 0.5), 0.5),
		"half a day is the furthest two bodies can be")
	check(FlyCalciumRadar2DScript.IN_PHASE_FRAC < 0.125,
		"the window is under three hours of the day")

	# A peer known ONLY by a phase is still a person on the dial.
	var r2: Control = _radar()
	r2.set_peer_phase({"z": 0.10})
	check(r2.peer_plots().has("z"), "a peer who only ever said what time it is still gets a blip")
	r2.free()

	# Rubbish in, nothing out.
	r.set_peer_phase({"a": 1.7, "b": 0.2})
	r.set_peer_stage({"a": -1, "b": 4})
	plots = r.peer_plots()
	check(float(plots["a"]["phase"]) == -1.0, "a phase outside the day is a wrong field, not a time")
	check(int(plots["a"]["stage"]) == -1, "and a negative stage is the wire's word for unknown")
	check(is_equal_approx(float(plots["b"]["phase"]), 0.2), "the good row beside it is untouched")
	r.set_own_phase(-1.0, -1)
	check(not bool(r.peer_plots()["b"]["in_phase"]), "forgetting where you stand un-flags everybody")

	# And they leave with the peer.
	r.set_own_phase(0.2, 3)
	check(bool(r.peer_plots()["b"]["in_phase"]), "b is company again")
	r.drop_peer("b")
	check(not r.peer_plots().has("b"), "a dropped peer leaves the phase map")
	r.set_peer_phase({"b": 0.2})
	check(r.peer_plots().has("b"), "and can walk back in")
	r.free()

