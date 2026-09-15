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
	print("--- front smoke: %d passed, %d failed ---" % [passes, failures])
	if failures == 0:
		print("--- ALL FRONT SMOKE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- FRONT SMOKE TESTS FAILED: ", failures, " ---\n")
		quit(1)


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

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


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

	# -- 7. the journey reads the whole path ---------------------------------
	check(store.has_method("body_path"), "the store remembers where the body has been")
	## Walk the body somewhere, somewhere else, then back to the first: only a
	## path-aware rule can call that THE ROAD BACK, and stage_of never could.
	store.set_body({"bits": 0b000111, "moving": 0})
	store.set_body({"bits": 0b001111, "moving": 0})
	store.set_body({"bits": 0b000111, "moving": 0})
	check(store.body_path().size() >= 3, "three steps of walk are remembered")
	front.beat()
	var walked: Array[int] = store.body_path()
	check(int(gauge.stage_of(walked, 0)) == front._stage,
		"the front's stage is the GAUGE's reading of the whole path")
	## Stage 8 is "The Road Back" in the gauge's own stage table: only a
	## path-aware rule can name it, and a single-step rule never could.
	check(front._stage == 8,
		"and returning to old ground fires The Road Back (got %d)" % front._stage)
	check(String(gauge.stage_name(front._stage)) == "The Road Back",
		"which the gauge's own stage table spells out")
	var chapter: Dictionary = front.current_chapter() as Dictionary
	check(String(chapter.get("stage_name", "")) == "The Road Back",
		"and the chapter the sheets are handed says so too")
	check(String(chapter.get("gloss", "")) != "", "with the gauge's gloss under it")

	app.queue_free()
	await process_frame
