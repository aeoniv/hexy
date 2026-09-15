extends SceneTree

## THE FRONT GLASS, BOOTED FOR REAL.
##
## scenes/hexy.tscn is instanced into a live tree with no device, no model and
## no room -- the same boot test_glass_smoke.gd does -- and then poked the way a
## finger pokes it: a blip, the figure, the creature, a swipe off the composer.
## Nothing here calls a private helper the user could not reach: every act is
## the release a real touch would leave behind.
##
## WHAT THIS FILE IS REALLY ASKING is whether the front is ONE ROOM. There must
## be exactly one radar in the whole tree and it must be quiet; the creature
## must stand in that radar's own hub square; the bar must be one sentence
## short enough to read at a glance; and the dials must be a page that is built
## once, covers the composer while it stands, and goes away again.

const SCENE: String = "res://scenes/hexy.tscn"

## The bar's contract, in characters.
const SENTENCE_MAX: int = 48

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
	print("\n--- TEST FRONT SMOKE (one sentence, one room, one composer) ---")
	await _run()
	await _run_phase_spine()
	await _run_peer_bearing()
	await _run_room_survives_the_dashboard(Vector2i(1812, 2176), "fold inner")
	await _run_room_survives_the_dashboard(Vector2i(2176, 1812), "fold landscape")
	await _run_room_survives_the_dashboard(Vector2i(1080, 2408), "phone")
	print("--- front smoke: %d passed, %d failed ---" % [passes, failures])
	if failures == 0:
		print("--- ALL FRONT SMOKE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- FRONT SMOKE TESTS FAILED: ", failures, " ---\n")
		quit(1)


## N4 -- A BEARING OFF THE BUS REACHES THE ROOM.
##
## The eco-location add-on says where a peer is as a Sense on
## "/sense/peer_bearing" and NOTHING ELSE: no call into the glass, no shared
## object. So this asks the only question that matters -- publish one on the
## front's own bus and see whether the radar's bearing for that peer moved.
## A null bearing (the LAN case, where no fix exists anywhere on the wire)
## must ERASE the arrow rather than freeze it.
func _run_peer_bearing() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.size = Vector2i(1080, 2408)
	root.content_scale_size = Vector2i(1080, 2408)
	root.add_child(app)
	await process_frame
	await process_frame
	var front: Node = app.get("front")
	if front == null:
		check(false, "the app mounted a Front for the bearing section")
		app.queue_free()
		return
	var topic: RefCounted = front.topic()
	if topic == null:
		topic = HexyTopic.new()
		front.set_bus(topic, front.gauge())
	check(topic != null, "the front stands on a bus")

	var radar: Control = front.radar as Control
	check(radar != null and radar.has_method("set_peer_bearings"),
		"the radar takes peer bearings")
	if radar == null:
		app.queue_free()
		return
	radar.set_peer_proximity({"peerbear01": "room"})
	radar.set_peer_headings({"peerbear01": 0.0})

	# -- a real bearing arrives ---------------------------------------------
	var ok: bool = topic.publish(HexyTopic.TOPIC_SENSE, HexyMsg.sense(
		"pheromone", "peer_bearing", 0,
		{"who": "peerbear01", "bearing_rad": 1.25, "dist_m": 12.0,
			"band": "room", "t_ns": 0}, {"who": "peerbear01"}))
	check(ok, "a peer_bearing Sense is a valid Sense the bus accepts")
	front.beat()
	var bearings: Dictionary = radar.get("_bearings") as Dictionary
	check(bearings.has("peerbear01"),
		"a /sense/peer_bearing Sense reaches radar.set_peer_bearings")
	check(bearings.has("peerbear01") and absf(float(bearings["peerbear01"]) - 1.25) < 0.001,
		"and it is the bearing the add-on worked out")

	# -- a null bearing takes the arrow away --------------------------------
	topic.publish(HexyTopic.TOPIC_SENSE, HexyMsg.sense(
		"pheromone", "peer_bearing", 0,
		{"who": "peerbear01", "bearing_rad": null, "dist_m": null,
			"band": "far", "t_ns": 0}, {"who": "peerbear01"}))
	front.beat()
	bearings = radar.get("_bearings") as Dictionary
	check(not bearings.has("peerbear01"),
		"a null bearing leaves the peer on its ring with no arrow")

	app.queue_free()
	await process_frame

func _run() -> void:
	var packed: PackedScene = load(SCENE)
	check(packed != null, "scenes/hexy.tscn loads")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	check(app != null and app is HexyApp, "the root of the scene is a HexyApp")
	root.size = Vector2i(1080, 2408)
	root.content_scale_size = Vector2i(1080, 2408)
	root.add_child(app)
	await process_frame
	await process_frame

	var front: Node = app.get("front")
	check(front != null and front is Front, "the app mounted a Front")
	if front == null:
		return
	check(_count_glass(app) == 1, "the Front is the app's only glass child")

	# -- one room, and it is quiet ------------------------------------------
	var radars: Array = _find_radars(app)
	check(radars.size() == 1, "exactly one calcium radar stands in the tree (got %d)" % radars.size())
	var radar: Control = front.radar as Control
	check(radar != null and radars.has(radar), "and it is the front's own room")
	check(bool(radar.get("quiet")), "the room is in quiet mode")
	check(not bool(radar.get("show_wedges")), "no wedges on the front glass")
	check(not bool(radar.get("show_bars")), "no neuromodulator bars either")

	# -- the creature stands in the radar's hub -----------------------------
	check(app.creature.get_parent() == front.view,
		"the creature stands in the front's own stage viewport")
	check(front.view.get_node_or_null("WorldEnvironment") != null
			and front.view.get_node_or_null("DirectionalLight3D") != null,
		"the stage carries the owner's environment and key light")
	var field: Control = front.creature_field as Control
	var hub: Rect2 = radar.hub_rect()
	check(field.size.x > 8.0, "the creature has a square of its own to be tapped in")
	check(field.position.distance_to(hub.position) < 2.0
			and absf(field.size.x - hub.size.x) < 2.0,
		"and that square IS the radar's hub_rect")

	# -- the bar says one sentence ------------------------------------------
	front.beat()
	await process_frame
	var line: String = String(front.sentence_text())
	print("sentence: ", line)
	check(line.strip_edges() != "", "one beat put a sentence on the bar")
	check(line.length() <= SENTENCE_MAX, "and it is at most 48 characters (%d)" % line.length())
	check(String(front.sentence_label.text) == line, "the label carries what the front says it does")
	var glyph: String = String(front.glyph_label.text)
	print("figure: ", glyph)
	check(glyph.contains("#"), "the figure under the disc names its King Wen number")
	check(glyph.contains(KingWen.name(int(app.store.body_bits()))),
		"and it is the store's own body figure")

	# -- the beat placed this phone in its own day --------------------------
	var phase: float = float(app.wmn.own_phase())
	check(phase >= 0.0 and phase < 1.0, "the beat set the fabric's own phase (%.3f)" % phase)
	check(float(radar.own_phase()) >= 0.0, "and the radar knows where the day stands")
	check(int(radar.own_stage()) >= 0, "and which chapter this figure is in")

	## From here the front's own four-a-second beat would overwrite the fake
	## room below with the empty one the fabric really has.
	front._beat_timer.stop()

	# -- a peer in the room becomes a plot, and a plot answers a finger -----
	radar.set_peer_proximity({"peerfront01": "room"})
	radar.set_peer_headings({"peerfront01": 0.0})
	radar.refresh_blips()
	var plots: Dictionary = radar.peer_plots()
	check(plots.has("peerfront01"), "a peer row through the radar yields a plot")
	var spots: Dictionary = radar.blip_positions()
	check(spots.has("peerfront01"), "and the plot is drawn somewhere a finger can reach")
	var heard: Array = []
	front.peer_tapped.connect(func(who: String) -> void: heard.append(who))
	radar.gui_input.emit(_tap(spots["peerfront01"] as Vector2))
	check(heard.size() == 1 and String(heard[0]) == "peerfront01",
		"tapping the blip says who was touched")
	radar.gui_input.emit(_tap(radar.disc_center()))
	check(heard.size() == 1, "and empty disc says nobody")

	# -- the figure asks for its reading ------------------------------------
	var readings: Array = []
	front.reading_tapped.connect(func(bits: int) -> void: readings.append(bits))
	front.glyph_band.gui_input.emit(_tap(Vector2(20.0, 20.0)))
	check(readings.size() == 1, "a tap on the figure asks for the reading")
	check(readings.size() == 1 and int(readings[0]) == (int(app.store.body_bits()) & 63),
		"and it asks about the figure that is standing")

	# -- a swipe up off the composer asks for the dashboard -----------------
	var dash: Array = []
	front.dashboard_requested.connect(func() -> void: dash.append(1))
	front.composer.gui_input.emit(_press(Vector2(200.0, 120.0)))
	front.composer.gui_input.emit(_tap(Vector2(200.0, 110.0)))
	check(dash.is_empty(), "a short drag off the composer is not a swipe")
	front.composer.gui_input.emit(_press(Vector2(200.0, 120.0)))
	front.composer.gui_input.emit(_tap(Vector2(200.0, 10.0)))
	check(dash.size() == 1, "a drag of more than eighty pixels up asks for the dashboard")
	await process_frame
	check(front.dashboard_open(), "and the front actually opened it")
	check(front.close_dashboard(), "and it can be closed again")
	check(not front.dashboard_open(), "leaving nothing standing for the rest of this smoke test")

	# -- the composer still takes a question --------------------------------
	check(not front.composer_send("   "), "the composer refuses an empty question")
	app.store.set_answer("")
	check(front.composer_send("what is this moment"), "and takes a real one")
	check(front.bubble_visible(), "the bubble stands while the answer is coming")
	var waited: float = 0.0
	while String(app.store.answer) == "" and waited < 2.0:
		await create_timer(0.05).timeout
		waited += 0.05
	check(String(app.store.answer) != "", "an answer landed in the store within 2 s")
	await process_frame
	check(front.bubble_text().strip_edges() != "", "and the bubble is carrying it")
	front.bubble.close()

	# -- the dials are a page, built once -----------------------------------
	check(front.dials_page() == null, "no dials page is built until a finger asks")
	front.creature_field.gui_input.emit(_tap(Vector2(4.0, 4.0)))
	await process_frame
	var page: Node = front.dials_page()
	check(page != null, "a tap on the creature opens the dials")
	check(page is Hud3, "and the dials page is the third glass itself")
	check(front.dials_open(), "the page is standing")
	check(not front.composer.visible, "the composer is out of the way while it stands")
	front.open_dials()
	await process_frame
	check(front.dials_page() == page, "asking twice opens the page that is already there")
	check(_count_children_of_type(front, "Hud3") == 1, "and never builds a second one")

	# -- and it goes away again ---------------------------------------------
	check(front.close_dials(), "the page closes")
	check(not front.dials_open(), "and it is gone")
	check(front.composer.visible, "the composer comes back")
	front.open_dials()
	await process_frame
	check(front.dials_open(), "the page can be opened again")
	check(front.back_requested(), "Android's back button closes the page")
	check(not front.dials_open(), "and the page is gone with it")
	check(not front.back_requested(), "a back request on the front itself does nothing")

	# -- THE PAGE CLOSING ITSELF PUTS THE FRONT BACK (device bug 1) ----------
	## On the phone: tap the creature, then the page's own back bar -- and the
	## front came back BLACK and answered nothing for a minute. The page takes
	## its own CanvasLayer down BEFORE it emits `closed`, so a front that asked
	## the layer whether a page was standing decided there was none, returned
	## early, and never showed its room, its composer or its creature again.
	front.open_dials()
	await process_frame
	var page2: Node = front.dials_page()
	check(front.dials_open(), "the page is standing again")
	check(app.creature.get_parent() == page2.view,
		"and the creature has moved into the page's own stage")
	## The page's OWN way out -- exactly what the back bar on the device does.
	page2.close()
	await process_frame
	await process_frame
	check(not front.dials_open(), "the page closing itself is a close the front heard")
	check(front.layer.visible, "the front's own room is drawn again")
	check(not page2.layer.visible, "and the page's layer is down")
	check(front.composer.visible, "the composer is back")
	check(is_equal_approx(front.root.modulate.a, 1.0) and front.root.visible,
		"the front's own glass is not left faded out or hidden")
	check(app.creature.get_parent() == front.view,
		"the creature was handed back to the front's stage")
	check(front.radar.get_parent() == front.room_band,
		"and the one radar is back in the front's own room band")
	check(_find_radars(app).size() == 1, "with still exactly one radar in the tree")
	check(not _blocks_the_front(page2),
		"nothing the page owns is left over the front eating fingers")
	## AND A FINGER REACHES THE FRONT AGAIN: the same tap that opened the page
	## the first time opens it once more, which it cannot do if the front is
	## hidden or something is standing in front of it.
	front.creature_field.gui_input.emit(_tap(Vector2(4.0, 4.0)))
	await process_frame
	check(front.dials_open(), "a tap on the creature reaches the front and opens the page")
	check(front.dials_page() == page2, "and it is still the one page, never a second")
	check(front.back_requested(), "back shuts it")
	await process_frame
	check(front.layer.visible and front.composer.visible, "and the front is whole again")

	# -- ANDROID BACK UNWINDS ONE PAGE AT A TIME (device bug 2) --------------
	## On the phone, back on the reading sheet QUIT THE APP: the engine's own
	## `quit_on_go_back` fired before this handler ever ran. It is off now, and
	## back is one act: shut the top page and stay; leave only from the front.
	check(not ProjectSettings.get_setting("application/config/quit_on_go_back", true),
		"the engine no longer quits out from under a page")
	front._open_reading_sheet(int(app.store.body_bits()) & 63)
	await process_frame
	check(front.reading_sheet_open(), "the reading sheet is standing")
	check(front.back_requested(), "back closes the reading sheet")
	check(not front.reading_sheet_open(), "and it is gone")
	check(front.composer.visible, "with the front whole underneath it")
	front._open_peer_sheet("peerfront01")
	await process_frame
	check(front.peer_sheet_open(), "a peer sheet stands")
	check(front.back_requested(), "back closes the peer sheet too")
	check(not front.peer_sheet_open(), "and it is gone")
	front.open_dashboard()
	await process_frame
	check(front.dashboard_open(), "the dashboard stands")
	check(front.back_requested(), "back closes the dashboard")
	check(not front.dashboard_open(), "and it is gone")
	## THE DASHBOARD GOES FIRST when it is stacked over the dials, and only
	## then the page: back unwinds the nearest thing, never two at once.
	front.open_dials()
	await process_frame
	front.open_dashboard()
	await process_frame
	check(front.dashboard_open() and front.dials_open(), "both are standing")
	check(front.back_requested(), "one back press is consumed")
	check(not front.dashboard_open(), "the dashboard went first")
	check(front.dials_open(), "and the page underneath is still there")
	check(front.back_requested(), "a second back press takes the page")
	check(not front.dials_open(), "and now nothing is standing")
	check(not front.back_requested(),
		"back on the front itself closes nothing -- that is the press that leaves the app")

	# -- A SLOW DRAG OPENS THE DASHBOARD (device note) -----------------------
	## `adb shell input swipe` makes a linear 300 ms drag with no fling, and it
	## did not register: the `ask` field covers nearly the whole band and STOPs
	## input, so the press never reached the composer's own panel at all.
	check(front.swipe_threshold() <= Front.SWIPE_PX,
		"the swipe is distance only, and never more than eighty pixels")
	check(front.swipe_threshold() > 0.0, "and it is a real distance")
	dash.clear()
	front.ask_field.gui_input.emit(_press(Vector2(40.0, 40.0)))
	front.ask_field.gui_input.emit(_tap(Vector2(40.0, 30.0)))
	check(dash.is_empty(), "a tap in the ask field is not a swipe -- it still takes focus")
	front.ask_field.gui_input.emit(_press(Vector2(40.0, 40.0)))
	front.ask_field.gui_input.emit(_tap(Vector2(40.0, 40.0 - front.swipe_threshold() - 1.0)))
	check(dash.size() == 1, "a slow drag up the ask field asks for the dashboard")
	await process_frame
	check(front.dashboard_open(), "and the panel opened")
	front.close_dashboard()
	dash.clear()
	front.btn_send.gui_input.emit(_press(Vector2(10.0, 40.0)))
	front.btn_send.gui_input.emit(_tap(Vector2(10.0, 40.0 - front.swipe_threshold() - 1.0)))
	check(dash.size() == 1, "and a drag off the send button asks for it as well")
	await process_frame
	front.close_dashboard()
	await process_frame

	# -- AND A TAP IS NEVER A SWIPE (device retest, W11) ---------------------
	## On the phone a plain tap on `ask` opened the dashboard instead of taking
	## the caret. Two reasons, both fixed here: a release that arrived with NO
	## remembered press subtracted from INF and handed back INF of travel, and
	## a finger that meant to stand still still jitters a few pixels.
	front.close_dashboard()
	await process_frame
	dash.clear()
	front.ask_field.release_focus()
	front.ask_field.gui_input.emit(_press(Vector2(40.0, 40.0)))
	front.ask_field.gui_input.emit(_tap(Vector2(40.0, 40.0)))
	check(dash.is_empty(), "a press and a release in the same spot is a tap, not a swipe")
	check(not front.dashboard_open(), "and the dashboard stayed shut")
	check(front.ask_field.has_focus(), "the tap put the caret in the ask field")

	dash.clear()
	front.ask_field.release_focus()
	front.ask_field.gui_input.emit(_press(Vector2(40.0, 40.0)))
	front.ask_field.gui_input.emit(_tap(Vector2(43.0, 35.0)))
	check(dash.is_empty(), "five pixels of finger jitter is still a tap")
	check(not front.dashboard_open(), "and still opens nothing")
	check(front.ask_field.has_focus(), "and still takes the caret")

	## A RELEASE WITH NO PRESS BEHIND IT SAYS NOTHING AT ALL.
	dash.clear()
	front.ask_field.gui_input.emit(_tap(Vector2(40.0, 10.0)))
	check(dash.is_empty(), "a release nobody pressed for is not a swipe of infinite travel")

	## AND A SWIPE IS UP, NOT ACROSS: the same distance dragged sideways is a
	## scroll along the band and must not open the gear.
	dash.clear()
	var reach: float = front.swipe_threshold() + 1.0
	front.ask_field.gui_input.emit(_press(Vector2(400.0, 40.0)))
	front.ask_field.gui_input.emit(_tap(Vector2(400.0 - reach * 2.0, 40.0 - reach)))
	check(dash.is_empty(), "a mostly-sideways drag is not the swipe that opens the gear")
	check(not front.dashboard_open(), "and nothing opened")
	dash.clear()
	front.ask_field.gui_input.emit(_press(Vector2(400.0, 40.0)))
	front.ask_field.gui_input.emit(_tap(Vector2(390.0, 40.0 - reach)))
	check(dash.size() == 1, "a mostly-upward drag still is")
	await process_frame
	front.close_dashboard()
	await process_frame

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


## W11 -- THE ROOM SURVIVES THE DASHBOARD (device bug, pass 3).
##
## On the Fold, panel 6 BORROWS the front's radar into a row -- and a row is a
## Container, so it writes anchors 0 and a 210 x 210 rect straight onto the
## node. The room band lays nobody out, so the disc came home the size of a
## dashboard tile while `radar_radius` went back to the band's own 771: the
## "split" front in the pass-3 screenshots, a disc drawn far outside its own
## rect with the creature mirrored across the glass. Nothing could be tapped,
## because `gui_input` only fires INSIDE a Control's rect -- so this test does
## not emit `gui_input` by hand the way the smoke test above does. It pushes
## real events at real screen points, which is the only way the hit-test is
## actually under test.
func _run_room_survives_the_dashboard(size_px: Vector2i, tag: String) -> void:
	print("-- room survives the dashboard: %s %s" % [tag, str(size_px)])
	var app: Node = load(SCENE).instantiate()
	root.size = size_px
	root.content_scale_size = size_px
	root.add_child(app)
	await process_frame
	await process_frame
	var front: Node = app.get("front")
	if front == null:
		check(false, "[%s] the app mounted a Front" % tag)
		return
	front._beat_timer.stop()
	var radar: Control = front.radar as Control

	## The room before anybody borrows it, so the two halves can be compared.
	check(_room_is_whole(front), "[%s] the radar fills the room band to start with" % tag)
	check(await _blip_opens_the_peer_sheet(front, "peerlayout1"),
		"[%s] a real tap on a blip opens the peer sheet" % tag)
	check(await _creature_opens_the_dials(front),
		"[%s] a real tap on the creature opens the dials" % tag)

	## THE ROUND TRIP. Open the dashboard (which takes the radar away), close
	## it (which hands it back), and ask the same two fingers again.
	front.open_dashboard()
	for _i in 8:
		await process_frame
	check(radar.get_parent() != front.room_band, "[%s] the dashboard borrowed the radar" % tag)
	front.close_dashboard()
	for _i in 8:
		await process_frame
	check(radar.get_parent() == front.room_band, "[%s] and handed it back" % tag)
	check(_room_is_whole(front),
		"[%s] the radar fills the band again (%s in a %s band)"
			% [tag, str(radar.size), str(front.room_band.size)])
	check(absf(radar.disc_center().x - front.room_band.size.x * 0.5) < 2.0,
		"[%s] the disc stands in the middle of the band, not off its own edge" % tag)
	check(front.creature_field.get_global_rect().has_point(
			radar.get_global_transform() * radar.disc_center()),
		"[%s] and the creature square still surrounds the disc centre" % tag)
	check(await _blip_opens_the_peer_sheet(front, "peerlayout2"),
		"[%s] a tap on a blip STILL opens the peer sheet after a dashboard visit" % tag)
	check(await _creature_opens_the_dials(front),
		"[%s] and a tap on the creature STILL opens the dials" % tag)

	## AND THE ROOM REPAIRS A RECT A BORROWER LEFT BENT. Whether the row's
	## Container zeroes the anchors is up to the engine's own layout pass and
	## the frame it lands on -- the room must not depend on it. This is that
	## exact state, written on by hand: anchors pinned top-left and a 210 px
	## tile of a rect, the shape the pass-3 screenshots came home in.
	radar.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	radar.position = Vector2.ZERO
	radar.size = Vector2(210.0, 210.0)
	front.reclaim_radar()
	for _i in 4:
		await process_frame
	check(_room_is_whole(front),
		"[%s] a rect left bent by a borrower is made whole again (%s in a %s band)"
			% [tag, str(radar.size), str(front.room_band.size)])
	check(await _blip_opens_the_peer_sheet(front, "peerlayout3"),
		"[%s] and a blip is tappable again" % tag)
	check(await _creature_opens_the_dials(front),
		"[%s] and so is the creature" % tag)

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


## The radar's rect IS the band's: the one thing the borrow used to break.
func _room_is_whole(front: Node) -> bool:
	var radar: Control = front.radar as Control
	return radar.position.is_equal_approx(Vector2.ZERO) 		and radar.size.is_equal_approx(front.room_band.size)


## A peer put in the room, then poked at the screen point its blip is drawn
## at -- radar-local through the radar's own global transform, which is what a
## finger does and what a hand-emitted `gui_input` never tests.
func _blip_opens_the_peer_sheet(front: Node, who: String) -> bool:
	var radar: Control = front.radar as Control
	front.close_peer_sheet()
	radar.set_peer_proximity({who: "room"})
	radar.set_peer_headings({who: 0.0})
	radar.refresh_blips()
	var spots: Dictionary = radar.blip_positions()
	if not spots.has(who):
		return false
	await _poke(radar.get_global_transform() * (spots[who] as Vector2))
	var ok: bool = bool(front.peer_sheet_open())
	front.close_peer_sheet()
	await process_frame
	return ok


## The creature, poked at the middle of the square it is drawn in.
func _creature_opens_the_dials(front: Node) -> bool:
	front.close_dials()
	await process_frame
	var r: Rect2 = front.creature_field.get_global_rect()
	await _poke(r.position + r.size * 0.5)
	var ok: bool = bool(front.dials_open())
	front.close_dials()
	await process_frame
	return ok


## A PRESS AND A RELEASE THROUGH THE VIEWPORT, at a point on the glass. This
## goes through the real hit-test, so a Control drawing outside its own rect
## is never hit -- exactly like the phone.
func _poke(at: Vector2) -> void:
	root.push_input(_press(at))
	root.push_input(_tap(at))
	await process_frame
	await process_frame


## Whether any Control the page owns is still sitting over the front with a
## filter that would swallow a finger. A hidden page that still eats input is
## the other half of the black-screen bug, and it is not visible in a
## screenshot: only this says so.
func _blocks_the_front(page: Node) -> bool:
	if page == null:
		return false
	for c in _all_controls(page):
		if c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
	return false


func _all_controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control:
		out.append(n as Control)
	for c in n.get_children():
		out.append_array(_all_controls(c))
	return out

# -- the poking ---------------------------------------------------------------

## One tap: the release a finger leaves behind.
static func _tap(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	return ev


## The other half of a drag: where the finger went down.
static func _press(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
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


## How many glass surfaces the app itself mounted: a Front or a Hud3 directly
## under the app, and no other.
func _count_glass(app: Node) -> int:
	var n: int = 0
	for kid in app.get_children():
		if kid is Front or kid is Hud3:
			n += 1
	return n


func _count_children_of_type(parent: Node, type_name: String) -> int:
	var n: int = 0
	for kid in parent.get_children():
		if kid.get_class() == type_name or (type_name == "Hud3" and kid is Hud3):
			n += 1
	return n


## W8e -- THE PHASE SPINE IS LIVE, AND IT IS THE GAUGE'S.
##
## The spine used to be a clock the front kept for itself and a stage rule in
## a const block. Both live in one file now -- user://gauge.json, through
## HexyGauge -- and the front only READS it. This is the file that notices if
## any of that goes inert again: the estimate must really run, the gauge must
## be the app's one gauge, the sentence must get a real phase_name off it, and
## the chapter must be read from the whole walk rather than one step.
func _run_phase_spine() -> void:
	print("\n[ the phase spine ]")
	var packed: PackedScene = load(SCENE)
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var front: Node = app.get_node_or_null("Hud")
	check(front != null, "the front is under the app")
	if front == null:
		app.queue_free()
		return
	var store: HexyStore = app.get("store") as HexyStore

	# -- 1. the estimate actually runs, and is exposed ------------------------
	front.beat()
	check(front.has_method("phase_estimate"), "the front exposes phase_estimate()")
	var est: Dictionary = front.phase_estimate() as Dictionary
	for key in ["offset_h", "confidence", "internal_hour", "phase_name", "phase"]:
		check(est.has(key), "phase_estimate names %s" % key)
	check(est.has("wake_h"), "and carries the estimate's own wake hour, so estimate() was really run")
	var ph: String = String(est.get("phase_name", ""))
	check(["night", "dawn", "morning", "midday", "afternoon", "dusk", "evening"].has(ph),
		"the internal hour names one of the seven bands (got '%s')" % ph)

	# -- 2. the clock is the app's ONE gauge, and the front only reads it -----
	var gauge: Variant = app.get("gauge")
	check(gauge != null, "the app built one gauge")
	check(front.gauge() == gauge, "and the front was handed that same one")
	check(front.topic() == app.get("topic"), "and the app's one topic with it")
	## A PURE READ. The front may not move the gauge's own two numbers; only
	## the bus (through fit) and the user (through correct) may.
	var before_offset: float = float(gauge.get_field("clock_offset_h", 0.0))
	var before_conf: float = float(gauge.get_field("confidence", 0.0))
	for _i in 8:
		front.beat()
	check(is_equal_approx(float(gauge.get_field("clock_offset_h", 0.0)), before_offset),
		"eight beats of the front never move the gauge's clock offset")
	check(is_equal_approx(float(gauge.get_field("confidence", 0.0)), before_conf),
		"nor its confidence -- the glass only looks")
	check(is_equal_approx(float(front.phase_estimate().get("offset_h", -99.0)),
		float(gauge.get_field("clock_offset_h", 0.0))),
		"and the offset the front reports IS the gauge's own")

	# -- 4. the sentence says a real day word --------------------------------
	var day: Dictionary = front._day_dict() as Dictionary
	check(day.has("phase_name"), "the day dict the sentence is handed names a phase")
	check(String(day["phase_name"]) != "", "and it is not empty")
	var line: String = String(front.sentence_text())
	check(line.length() <= SENTENCE_MAX, "the bar still fits in %d (%d)" % [SENTENCE_MAX, line.length()])
	check(line == line.to_lower(), "and is still lowercase")

	# -- 7. N3: the stage ARRIVES on /body; the front works nothing out -------
	## The front used to read the store's walk through the gauge and call the
	## chapter itself. It does not any more: whatever the organism publishes
	## as Body.stage is what the room shows, and the only thing this file can
	## do to move it is publish one.
	check(not front.has_method("_stage_of"),
		"the front no longer has a stage rule of its own")
	var topic: HexyTopic = app.get("topic") as HexyTopic
	check(topic != null, "the app has the one topic")
	store.set_body({"bits": 0b000111, "moving": 0})
	store.set_body({"bits": 0b001111, "moving": 0})
	store.set_body({"bits": 0b000111, "moving": 0})
	check(store.body_path().size() >= 3, "three steps of walk are remembered")
	front.beat()
	check(String(front.current_chapter().get("stage_word", "x")) == "",
		"a walk alone moves no stage: the organism has not said one")

	## A Body with a first-person stage on it, straight down the bus.
	var reward: Dictionary = HexyMsg.body(Clock.now_ns(), 0b000111,
		[0.5, 0.5, 0.5, 0.5, 0.5, 0.6], 0.0, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		0.5, "Day", "reward")
	check(String(reward.get("stage", "")) == "reward", "a Body can carry a stage")
	topic.publish(HexyTopic.TOPIC_BODY, reward)
	front.beat()
	var chapter: Dictionary = front.current_chapter() as Dictionary
	check(String(chapter.get("stage_word", "")) == "reward",
		"the front shows the organism's own word (got '%s')" % String(chapter.get("stage_word", "")))
	check(String(chapter.get("stage_name", "")) == "Reward",
		"which the gauge's own stage table spells out for the room")
	check(String(chapter.get("gloss", "")) != "", "with the gauge's gloss under it")
	check(String(chapter.get("title", "")).begins_with("Reward"),
		"and the chapter title the sheets are handed says so too")

	## And back to "" when the organism says so.
	var ordinary: Dictionary = HexyMsg.body(Clock.now_ns(), 0b000111,
		[0.5, 0.5, 0.5, 0.5, 0.5, 0.1], 0.0, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		0.5, "Day", "")
	topic.publish(HexyTopic.TOPIC_BODY, ordinary)
	front.beat()
	check(String(front.current_chapter().get("stage_word", "x")) == "",
		"and it returns to the ordinary world when the organism does")

	app.queue_free()
	await process_frame
