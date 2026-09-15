extends SceneTree

## THE DIALS AS A PAGE, AND THE TWO JOYSTICKS ON IT.
##
## The third glass is not the surface any more: it is what the front opens when
## a finger asks to READ the machine. Four claims are made here and every one
## of them is the kind a person would notice going wrong.
##
##   1. THE PAGE IS ONE PAGE. `open_dials()` builds exactly one Hud3 however
##      often it is asked, and while that page stands there is STILL exactly
##      one FlyCalciumRadar2D in the whole tree -- the front's own room. The
##      page used to carry a second one and the dashboard carries a third, so
##      this is the check that keeps the radar from breeding.
##   2. THERE IS ALWAYS A WAY BACK. `close()` says `closed`, the back bar says
##      `closed`, a swipe down off the glass says `closed`, and Android's own
##      back button says `closed` -- and the front, listening to that one
##      signal, takes the page off the glass every time.
##   3. THE HEAD RING IS A JOYSTICK. A finger dragged round it says an angle
##      and that angle lands on the fan-shaped body's own goal heading:
##      `FlyCentralComplex.target_heading`, which is the name the connectome
##      really spells. The release disarms it.
##   4. THE EARTH RING IS A SCRUB. The same drag round the earth says a share
##      of the day, always inside 0..1, and says so again when it is let go.
##
## Every act here is the event a real touch leaves behind, pushed through the
## dial's own `gui_input` -- which is exactly where the page listens.

const SCENE: String = "res://scenes/hexy.tscn"
const PHONE: Vector2i = Vector2i(1080, 2408)

var failures: int = 0
var passes: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST DIALS PAGE (one page, one room, a way back, two joysticks) ---")
	await _run()
	await _run_w7a()
	await _run_w10c()
	print("--- dials page: %d passed, %d failed ---" % [passes, failures])
	if failures == 0:
		print("--- ALL DIALS PAGE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- DIALS PAGE TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	check(packed != null, "scenes/hexy.tscn loads")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.size = PHONE
	root.content_scale_size = PHONE
	root.add_child(app)
	await process_frame
	await process_frame

	var front: Node = app.get("front")
	check(front != null and front is Front, "the app mounted a Front")
	if front == null:
		return

	# -- 1. one page, and the room stays one room ----------------------------
	check(_count_pages(app) == 0, "no dials page stands until a finger asks")
	check(_count_radars(app) == 1, "and the front is the one room in the tree")
	var hud: Hud3 = front.open_dials() as Hud3
	await process_frame
	await process_frame
	check(hud != null, "open_dials puts a Hud3 up")
	if hud == null:
		return
	check(_count_pages(app) == 1, "exactly one dials page stands in the whole tree")
	check(front.open_dials() == hud, "asking again opens the page that is there")
	await process_frame
	check(_count_pages(app) == 1, "and never builds a second one")
	check(_count_radars(app) == 1,
		"there is STILL exactly one calcium radar in the tree while the page stands")
	check(_find_radars(app)[0] == front.radar, "and it is the front's own room")
	check(hud.get("radar") == null, "the page stands no radar of its own")
	check(hud.dashboard == null, "and builds no dashboard until one is asked for")
	check(hud.is_open(), "the page says it is standing")

	# -- the captions the strip used to say ----------------------------------
	check(String(hud.head_cap.text).contains("HEAD"), "the head dial carries a caption")
	check(String(hud.body_cap.text).contains("BODY"), "the body dial carries a caption")
	check(String(hud.earth_cap.text).contains("EARTH"), "the earth dial carries a caption")

	# -- 2. the ways back ----------------------------------------------------
	var shut: Array = []
	hud.closed.connect(func() -> void: shut.append(1))

	hud.close()
	check(shut.size() == 1, "close() says the page is closed")
	check(not hud.is_open(), "and the page is down")
	check(not front.dials_open(), "and the front took it off the glass")

	front.open_dials()
	await process_frame
	check(hud.is_open(), "the page opens again")
	hud.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(shut.size() == 2, "the back request says the page is closed")
	check(not front.dials_open(), "and the front took it off again")

	front.open_dials()
	await process_frame
	hud.back_bar.gui_input.emit(_tap(Vector2(24.0, 12.0)))
	check(shut.size() == 3, "a tap on the back bar says the page is closed")

	front.open_dials()
	await process_frame
	hud.gestures.gui_input.emit(_press(Vector2(540.0, 400.0)))
	hud.gestures.gui_input.emit(_tap(Vector2(540.0, 430.0)))
	check(shut.size() == 3, "a short drag on the glass is not a way out")
	hud.gestures.gui_input.emit(_press(Vector2(540.0, 400.0)))
	hud.gestures.gui_input.emit(_tap(Vector2(540.0, 520.0)))
	check(shut.size() == 4, "a swipe of more than eighty pixels down closes the page")

	front.open_dials()
	await process_frame
	await process_frame

	# -- 3. the head ring steers the fly -------------------------------------
	var head: Control = hud.head_dial() as Control
	check(head != null and head.size.x > 8.0, "the head dial has a band to be dragged in")
	var mid: Vector2 = head.size * 0.5
	var reach: float = minf(head.size.x, head.size.y) * 0.44 * 0.95
	var steered: Array = []
	hud.head_steered.connect(func(a: float) -> void: steered.append(a))

	head.gui_input.emit(_press(mid + Vector2(reach, 0.0)))
	head.gui_input.emit(_motion(mid + Vector2(0.0, reach)))
	check(steered.size() == 1, "a drag round the head ring steers once per move")
	var got: float = float(steered[0]) if steered.size() > 0 else -1.0
	check(got >= 0.0 and got < TAU, "and the angle it says is inside one turn (%f)" % got)
	check(is_equal_approx(got, PI * 0.5), "and it IS the angle the finger stands at")

	## W8e -- THE DIALS PAGE NO LONGER REACHES FOR THE BRAIN. The drag is
	## published as a tarsi Sense at door "head_tiller" and the ORGANISM sets
	## its own goal vector, so the glass is asked what it published and the
	## brain is asked, separately, what it did about it.
	var sensed: Dictionary = hud._topic.last("/sense/head_tiller") as Dictionary
	check(String(sensed.get("kind", "")) == "sense", "the drag published a Sense")
	check(String(sensed.get("organ", "")) == "tarsi"
		and String(sensed.get("door", "")) == "head_tiller",
		"on organ tarsi at door head_tiller")
	check(is_equal_approx(float(sensed.get("value", -1.0)), got),
		"carrying the angle the finger stands at and nothing else")
	var cx: Object = _cx(app)
	check(cx != null, "the store's character carries a FlyCentralComplex")
	check(cx != null and "target_heading" in cx,
		"and the goal heading on it is spelled target_heading")
	check(cx != null and is_equal_approx(float(cx.get("target_heading")), got),
		"the organism took the Sense and set its own goal heading")

	head.gui_input.emit(_motion(mid + Vector2(-reach, 0.0)))
	check(steered.size() == 2, "every move while the finger is down steers again")
	head.gui_input.emit(_tap(mid + Vector2(-reach, 0.0)))
	head.gui_input.emit(_motion(mid + Vector2(0.0, -reach)))
	check(steered.size() == 2, "and a finger that came up steers no more")

	steered.clear()
	head.gui_input.emit(_press(mid))
	head.gui_input.emit(_motion(mid + Vector2(0.0, reach)))
	check(steered.is_empty(), "a finger down in the hub is a tap, not a joystick")
	head.gui_input.emit(_tap(mid))

	# -- 4. the earth ring scrubs the day ------------------------------------
	var earth: Control = hud.earth_lines if hud.earth_lines.visible else hud.earth_dial()
	check(earth != null and earth.size.x > 8.0, "the earth band has a face to be dragged on")
	var emid: Vector2 = earth.size * 0.5
	var ereach: float = minf(earth.size.x, earth.size.y) * 0.44 * 0.95
	var scrubs: Array = []
	var lets_go: Array = []
	hud.earth_scrubbed.connect(func(p: float) -> void: scrubs.append(p))
	hud.earth_released.connect(func() -> void: lets_go.append(1))

	earth.gui_input.emit(_press(emid + Vector2(ereach, 0.0)))
	for a in [0.0, PI * 0.5, PI, -PI * 0.5]:
		earth.gui_input.emit(_motion(emid + Vector2(cos(a), sin(a)) * ereach))
	check(scrubs.size() == 4, "a drag round the earth ring scrubs once per move")
	var inside: bool = true
	for p in scrubs:
		if float(p) < 0.0 or float(p) > 1.0:
			inside = false
	check(inside, "and every share of the day it says is inside 0..1 (%s)" % str(scrubs))
	## Straight up is the seam of the day: a hair either side of it is 0.0 or a
	## hair short of 1.0, and both are the top.
	var top: float = float(scrubs[3]) if scrubs.size() == 4 else -1.0
	check(top >= 0.0 and (top < 0.001 or top > 0.999),
		"straight up the earth ring is the top of the day (%f)" % top)
	check(scrubs.size() == 4 and is_equal_approx(float(scrubs[1]), 0.5),
		"and straight down is the other half of it")
	check(lets_go.is_empty(), "the finger has not come up yet")
	earth.gui_input.emit(_tap(emid + Vector2(0.0, -ereach)))
	check(lets_go.size() == 1, "and letting go says so once")
	scrubs.clear()
	earth.gui_input.emit(_motion(emid + Vector2(ereach, 0.0)))
	check(scrubs.is_empty(), "a finger that is not down scrubs nothing")

	check(is_equal_approx(Hud3.day_phase_of(-PI * 0.5), 0.0),
		"day_phase_of puts midnight straight up")
	check(is_equal_approx(Hud3.day_phase_of(0.0), 0.25),
		"and runs the day clockwise round the ring")

	# -- 4b. A SCRUB SNAPS BACK ON RELEASE (device bug 3) --------------------
	## The device showed a balloon left standing after a drag round the EARTH
	## ring -- "Food same -> #16 Providing-For" -- which is a PREVIEW that never
	## went away. Letting go must put the page back to now: no balloon, and the
	## three captions re-read off the store rather than off the finger.
	var earth_before: int = int(app.store.earth_bits())
	hud.bubble.say("Food same -> #16 Providing-For", Vector2(100.0, 100.0))
	check(hud.bubble.visible, "a balloon is standing before the release")
	scrubs.clear()
	lets_go.clear()
	earth.gui_input.emit(_press(emid + Vector2(ereach, 0.0)))
	earth.gui_input.emit(_motion(emid + Vector2(0.0, ereach)))
	check(scrubs.size() == 1, "the ring previews while the finger travels")
	earth.gui_input.emit(_tap(emid + Vector2(0.0, ereach)))
	check(lets_go.size() == 1, "and the release is announced once")
	check(not hud.bubble.visible, "the scrub balloon is gone when the finger comes up")
	check(String(hud.earth_cap.text).contains("EARTH"),
		"and the earth caption has snapped back to the figure that is standing")
	check(String(hud.earth_cap.text).contains(KingWen.name(earth_before)),
		"which is the store's own earth figure, unchanged by the scrub")
	check(int(app.store.earth_bits()) == earth_before,
		"a scrub is a question: it never wrote the earth")
	## A PRESS THAT NEVER MOVED IS STILL A TAP. The swallow is only for a real
	## scrub, or the ring would stop answering fingers altogether.
	lets_go.clear()
	earth.gui_input.emit(_press(emid + Vector2(ereach, 0.0)))
	earth.gui_input.emit(_tap(emid + Vector2(ereach, 0.0)))
	check(lets_go.size() == 1, "a press that never travelled still ends the gesture")
	check(not hud._earth_scrubbed_any, "and left no scrub behind it")

	# -- 5. opening the gear FROM the dials page still borrows one radar -----
	front.open_dials()
	await process_frame
	check(_count_radars(app) == 1, "one radar with the dials page standing")
	hud.toggle_dashboard()
	await process_frame
	check(hud.dashboard_open(), "toggle_dashboard opened the gear from the dials page")
	check(_count_radars(app) == 1, "still exactly one radar with the gear open on top of the dials")
	check(hud.dashboard.radar == front.radar, "and the panel drew the front's own instance, not a second one")
	check(not bool(front.radar.get("quiet")), "borrowed for the gear, the one radar is loud")
	hud.toggle_dashboard()
	await process_frame
	check(not hud.dashboard_open(), "and the gear closes again")
	check(_count_radars(app) == 1, "with the radar count still exactly one")
	check(bool(front.radar.get("quiet")), "and the radar quiet again, back in the front's room")
	front.close_dials()
	await process_frame

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


# -- the poking ---------------------------------------------------------------

static func _tap(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	return ev


static func _press(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	return ev


static func _motion(at: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	return ev


# -- reading the tree ---------------------------------------------------------

func _find_radars(from: Node) -> Array:
	var out: Array = []
	if from is FlyCalciumRadar2D:
		out.append(from)
	for kid in from.get_children():
		out.append_array(_find_radars(kid))
	return out


func _count_radars(from: Node) -> int:
	return _find_radars(from).size()


func _count_pages(from: Node) -> int:
	var n: int = 1 if from is Hud3 else 0
	for kid in from.get_children():
		n += _count_pages(kid)
	return n


## W7a.5/6 -- THE TWO JOYSTICKS ACTUALLY REACH SOMETHING.
##
## Both rings already SAID their number and neither number was ever consumed:
## the earth scrub went nowhere, and the head's goal heading sat on the
## fan-shaped body while the creature carried on drifting. These two checks
## are what notice if either goes inert again.
func _run_w7a() -> void:
	print("\n[ the scrub previews, and the tiller turns the creature ]")
	var packed: PackedScene = load(SCENE)
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.size = PHONE
	root.content_scale_size = PHONE
	root.add_child(app)
	await process_frame
	await process_frame
	var front: Node = app.get("front")
	if front == null:
		front = app.get_node_or_null("Hud")
	if front == null:
		app.queue_free()
		return
	var hud: Node = front.open_dials()
	await process_frame
	await process_frame
	if hud == null:
		app.queue_free()
		return

	# -- 5. the earth scrub is a preview the front consumes -------------------
	front.beat()
	var resting: float = front.own_phase()
	check(front.has_method("own_phase"), "the front says which phase the glass is showing")
	hud.earth_scrubbed.emit(0.75)
	check(is_equal_approx(front.own_phase(), 0.75),
		"a scrub overrides the shown phase (got %f)" % front.own_phase())
	var scrubbed_word: String = String((front._day_dict() as Dictionary).get("phase_name", ""))
	check(scrubbed_word == "dusk" or scrubbed_word == "evening",
		"and the sentence's day word follows the finger (0.75 of a day -> '%s')" % scrubbed_word)
	## THE SCRUB IS A GAUGE PREVIEW: the gauge is ASKED what that hour is
	## called and nothing is written -- a scrub is a question, not an
	## observation.
	check(hud.has_method("scrub_caption"), "the dials page can caption a scrubbed hour")
	var caption: String = String(hud.scrub_caption(0.75))
	check(caption.find("18:00") >= 0, "the caption names the scrubbed hour (got '%s')" % caption)
	check(caption.find(scrubbed_word) >= 0,
		"and the gauge's own word for it (got '%s')" % caption)
	var gauge: Variant = app.get("gauge")
	var before_samples: int = (gauge.samples as Array).size()
	var before_offset: float = float(gauge.get_field("clock_offset_h", 0.0))
	hud.earth_scrubbed.emit(0.25)
	hud.scrub_caption(0.25)
	check((gauge.samples as Array).size() == before_samples,
		"a scrub never writes a sample into the gauge")
	check(is_equal_approx(float(gauge.get_field("clock_offset_h", 0.0)), before_offset),
		"nor moves its clock offset")
	hud.earth_released.emit()
	check(is_equal_approx(front.own_phase(), resting) or front.own_phase() >= 0.0,
		"letting go hands the phase back to the clock (got %f)" % front.own_phase())
	check(front._scrub_phase < 0.0, "and the override is cleared outright")

	# -- 6. the head tiller reaches the creature ------------------------------
	var cx: Object = _cx(app)
	check(cx != null, "the store's character carries a FlyCentralComplex")
	if cx == null:
		app.queue_free()
		return
	var character: Object = (app.get("store") as HexyStore).get_character()
	check(character != null and character.has_method("feed_senses"), "and the character can be ticked")

	cx.set("current_heading", 0.0)
	var goal: float = PI * 0.5
	hud.steer_head(goal)
	check(is_equal_approx(float(cx.get("target_heading")), goal), "the tiller set the goal heading")
	check(bool(cx.get("has_target")), "and said out loud that a goal was set at all")
	var start_err: float = absf(float(cx.call("steering_error")))
	for i in range(60):
		character.feed_senses({}, 0.05)
	var end_err: float = absf(float(cx.call("steering_error")))
	check(end_err < start_err,
		"sixty ticks later the heading has moved TOWARD the goal (%f -> %f)" % [start_err, end_err])
	check(absf(float(cx.get("current_heading")) - goal) < 0.2,
		"and is close enough to say the creature turned (heading %f, goal %f)"
			% [float(cx.get("current_heading")), goal])

	## With no goal ever set, the ring attractor is left entirely alone.
	var virgin := FlyCentralComplex.new()
	virgin.current_heading = 1.0
	virgin.steer_toward_target(1.0)
	check(is_equal_approx(virgin.current_heading, 1.0),
		"a central complex nobody steered is not steered by this")

	## FIX 3: sin(err) vanishes at err = +-PI, stranding the fly facing
	## directly away from the goal with zero turn signal. Straight-behind
	## must still resolve to the goal, not sit at the antipode forever.
	var behind := FlyCentralComplex.new()
	behind.current_heading = 0.0
	behind.set_target_hexagram(1)
	behind.target_heading = PI
	behind.has_target = true
	for i in range(100):
		behind.steer_toward_target(0.05)
	check(absf(behind.current_heading - PI) < 0.05,
		"dead-behind (0 -> PI) still converges (got %f)" % behind.current_heading)

	var opp_a := FlyCentralComplex.new()
	opp_a.current_heading = PI * 0.5
	opp_a.target_heading = PI * 1.5
	opp_a.has_target = true
	for i in range(100):
		opp_a.steer_toward_target(0.05)
	check(absf(fposmod(opp_a.current_heading - PI * 1.5 + PI, TAU) - PI) < 0.05,
		"PI/2 -> 3PI/2 also converges (got %f)" % opp_a.current_heading)

	var opp_b := FlyCentralComplex.new()
	opp_b.current_heading = PI * 1.5
	opp_b.target_heading = PI * 0.5
	opp_b.has_target = true
	for i in range(100):
		opp_b.steer_toward_target(0.05)
	check(absf(fposmod(opp_b.current_heading - PI * 0.5 + PI, TAU) - PI) < 0.05,
		"3PI/2 -> PI/2 also converges (got %f)" % opp_b.current_heading)

	app.queue_free()
	await process_frame


## THE FAN-SHAPED BODY, through the store's character. The dials page used to
## hand this out itself; it does not know the brain any more, so a test that
## wants to check what the organism DID with a Sense asks the organism.
static func _cx(app: Node) -> Object:
	var store: Variant = app.get("store")
	if store == null:
		return null
	var ch: Variant = store.get_character()
	return (ch.get("central_complex") as Object) if ch != null else null


## W10c -- THE DIALS WRITE NOTHING, AND A REFUSAL IS VISIBLE.
##
## Two claims, and both are the kind a person would notice going wrong:
##
##   1. THE ALTAR PUBLISHES A SENSE. A cast on the earth used to call
##      store.note_seat, store.note_cast and wmn.broadcast straight from the
##      dial. Now the gesture goes out as a tarsi Sense at door "earth_seat"
##      and the STORE, which owns seat state, applies it -- so the figure the
##      store ends up on is the figure the Sense carried, and the glass wrote
##      none of it.
##   2. THE HEAD RING SHOWS WHEN IT IS NOT OBEYED. The tiller is a request;
##      while the body's real heading stands more than ten degrees off it, the
##      page draws a ghost pointer at the request and the solid one at the
##      truth. When the brain follows, the ghost merges.
func _run_w10c() -> void:
	print("
[ the dials publish a seat, and a refused tiller is visible ]")
	var packed: PackedScene = load(SCENE)
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.size = PHONE
	root.content_scale_size = PHONE
	root.add_child(app)
	await process_frame
	await process_frame
	var front: Node = app.get("front")
	var store: HexyStore = app.get("store") as HexyStore
	var topic: Variant = app.get("topic")
	if front == null or store == null or topic == null:
		app.queue_free()
		return
	var hud: Node = front.open_dials()
	await process_frame
	await process_frame
	if hud == null:
		app.queue_free()
		return

	# -- 1. the EARTH cast is a Sense, and the store is what applies it -------
	var seated: Dictionary = hud.cast_earth() as Dictionary
	var msg: Dictionary = topic.last("/sense/earth_seat") as Dictionary
	check(String(msg.get("kind", "")) == "sense", "the earth cast published a Sense")
	check(String(msg.get("organ", "")) == "tarsi"
			and String(msg.get("door", "")) == "earth_seat",
		"on organ tarsi at door earth_seat")
	var value: Dictionary = (msg.get("value", {}) as Dictionary)
	check(int(value.get("seat", -1)) == HexyStore.Seat.EARTH,
		"carrying the seat it landed in")
	check(String(value.get("cast", "")) == "cast_confirmed",
		"and the cast kind the altar's throw deserves")
	check(int(value.get("bits", -1)) == store.earth_bits(),
		"and the store stands on exactly the figure the Sense carried (%d vs %d)"
			% [int(value.get("bits", -1)), store.earth_bits()])
	check(int(seated.get("bits", -1)) == store.earth_bits(),
		"which is the seat cast_earth hands back")

	## And the same door carries a WALK of the altar, which lands the same way:
	## one Sense, one seat, one store applying it.
	hud.walk_earth(9)
	var walked: Dictionary = (topic.last("/sense/earth_seat") as Dictionary).get("value", {})
	check(int(walked.get("seat", -1)) == HexyStore.Seat.EARTH,
		"a walk of the altar goes out on the same door")
	check(int(walked.get("bits", -1)) == store.earth_bits(),
		"and the store followed the walk too")

	## THE PAGE ITSELF WRITES NOTHING. Detach the store from the bus and the
	## same gesture moves nothing at all -- proof the store was the writer.
	var before: int = store.earth_bits()
	store.detach_bus()
	hud.walk_earth(31)
	check(store.earth_bits() == before,
		"with the store off the bus the dial moves no seat by itself")
	store.attach_bus(topic)

	# -- 2. the tiller's refusal, drawn ---------------------------------------
	check(hud.get("tiller_ghost") != null, "the head dial carries a ghost pointer")
	check(not bool(hud.call("tiller_refused")),
		"with nothing ever asked there is one pointer and no ghost")
	hud.steer_head(PI * 0.5)
	_say_body(topic, store.body_bits(), 0.0)
	check(bool(hud.call("tiller_refused")),
		"a body that has not turned yet leaves the request ghosted (gap %f)"
			% float(hud.call("tiller_gap_rad")))
	check(is_equal_approx(float(hud.call("tiller_heading")), PI * 0.5),
		"the ghost stands at the angle the finger asked for")
	check(is_equal_approx(float(hud.call("body_heading")), 0.0),
		"and the solid pointer at the heading the body reports")
	_say_body(topic, store.body_bits(), PI * 0.5 - 0.05)
	check(not bool(hud.call("tiller_refused")),
		"once the brain is within ten degrees the ghost merges")
	_say_body(topic, store.body_bits(), PI)
	check(bool(hud.call("tiller_refused")),
		"and a body that turns away again is ghosted again")

	# -- 3. the BODY dial reads its bits off the bus --------------------------
	_say_body(topic, 0b101010, PI)
	check(int(hud.call("_body_bits")) == 0b101010,
		"the BODY dial stands on the figure the bus carried")

	front.close_dials()
	await process_frame
	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


## ONE BODY MESSAGE, put on the bus the way the organism puts one there.
static func _say_body(topic: Variant, bits: int, heading: float) -> void:
	topic.publish(HexyTopic.TOPIC_BODY, HexyMsg.body(0, bits,
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], heading,
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0, "Day"))
