extends SceneTree

## THE GEAR OPENS THE INSTRUMENT PANEL.
##
## scenes/hexy.tscn is booted for real, the dials page is opened off the front
## the way a finger opens it, `toggle_dashboard()` is called -- the same path a
## finger takes -- and then every claim the
## dashboard makes is checked against the objects it was bound to: seven panels
## on the column, every one of them painted at least once, sixty-four cells of
## sense data, the store's own three figures. And while it stands, the three
## dials underneath must still keep out of each other's way, because an overlay
## that moves the bands is not an overlay.

const SCENE: String = "res://scenes/hexy.tscn"
const SIZES: Array[Vector2i] = [Vector2i(1080, 2400), Vector2i(1812, 2176)]

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST DASHBOARD (the gear's instrument panel) ---")
	await _run_widget_panels()
	await _run()
	await _run_borrowed_radar()
	await _run_phase_panel()
	if failures == 0:
		print("--- ALL DASHBOARD TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- DASHBOARD TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	check(packed != null, "scenes/hexy.tscn loads")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var front: Node = app.get_node_or_null("Hud")
	check(front != null, "the front is under the app")
	if front == null:
		return
	var hud: Node = front.open_dials()
	await process_frame
	check(hud != null and hud is Hud3, "and the dials page opens behind it")
	if hud == null:
		return
	var store: HexyStore = app.store

	check(hud.dashboard == null, "the page builds no dashboard until one is asked for")
	var dash: HexyDashboard = hud.dashboard_page()
	check(dash != null, "and builds one the moment it is")
	if dash == null:
		return
	check(not dash.is_open(), "it is hidden when it is built")
	check(not dash.visible, "the overlay takes no pixel until it is asked for")

	# -- the gear ------------------------------------------------------------
	hud.toggle_dashboard()
	await process_frame
	check(dash.is_open() and dash.visible, "toggling opens it")

	# Let a few beats pass so every panel has painted from a real snapshot.
	for i in 12:
		await process_frame
	dash._refresh()
	await process_frame
	await process_frame

	# -- the seven panels ----------------------------------------------------
	for kind in HexyDashboard.PANELS:
		var panel: Control = dash.panel(kind)
		check(panel != null, "panel %s stands on the column" % kind)
		check(panel != null and panel.name == kind.capitalize() + "Panel",
			"panel %s is named for what it shows" % kind)
	check(dash.panel("identity") != null and dash.panel("identity").get_parent() == dash.column,
		"every panel is a child of the one scrolling column")

	var counts: Dictionary = dash.draw_counts()
	print("draws: ", counts)
	for kind in HexyDashboard.PANELS:
		check(int(counts.get(kind, 0)) > 0, "panel %s painted itself" % kind)

	# -- the data each panel reads -------------------------------------------
	var grid: Array = dash.sense_grid()
	check(grid.size() == 64, "the sense grid carries 8x8 cells (got %d)" % grid.size())
	var summed: float = 0.0
	for v in grid:
		summed += float(v)
	check(summed >= 0.0, "and every cell is a real number")

	var figs: Dictionary = dash.figures()
	check(figs.has("head") and figs.has("body") and figs.has("earth"),
		"the figures panel read all three figures")
	check(int((figs.get("head", {}) as Dictionary).get("bits", -1)) == (int(store.head_bits()) & 63),
		"the head figure is the store's own")
	check(int((figs.get("body", {}) as Dictionary).get("bits", -1)) == (int(store.body_bits()) & 63),
		"the body figure is the store's own")
	check(int((figs.get("earth", {}) as Dictionary).get("bits", -1)) == (int(store.earth_bits()) & 63),
		"the earth figure is the store's own")

	var snap: Dictionary = dash.snapshot()
	check((snap.get("device", {}) as Dictionary).has("row"), "the device panel named a profile row")
	check((snap.get("engine", {}) as Dictionary).has("backend"), "the engine panel named a backend")
	check((snap.get("fires", {}) as Dictionary).has("dwell_needed_s"),
		"the fires panel read the civil breath from alchemy")
	check((snap.get("mesh", {}) as Dictionary).has("fabric"), "the mesh panel named the fabric")

	# -- the PEERS door: one row answers who / where / which-way ------------
	check(dash._trigram_of(null) == "·", "no bio pulse draws no trigram, not a guessed one")
	var wedge0: String = dash._trigram_of(0.0)
	var wedge_pi: String = dash._trigram_of(PI)
	check(wedge0 != "" and wedge_pi != "" and wedge0 != wedge_pi,
		"a heading in radians resolves to a trigram glyph (%s at 0, %s at pi)"
			% [wedge0, wedge_pi])
	var fake_peers: Array = [{"who": "peerid1234abcd", "bits": 0, "moving": 0,
		"body": 0, "last_seen_ms": 0, "rssi": -1, "band": "here",
		"cls": "touch", "heading_rad": 1.57}]
	var fake_row: Dictionary = fake_peers[0]
	check(fake_row.has("cls") and fake_row.has("heading_rad"),
		"a peers() row carries cls and heading_rad for the door to draw")
	var eng: Dictionary = snap.get("engine", {}) as Dictionary
	for cast_key in ["q6_cast_version", "q6_prior_weight", "q6_prior_mismatches"]:
		check(eng.has(cast_key), "the figures panel reads %s from Mnn.info()" % cast_key)
	check(dash.radar != null, "the fly panel mounts a calcium radar of its own")
	check(dash.radar != null and bool(dash.radar.get("_fed")), "and the radar has been fed a state")
	check(HexyDashboard.build_id() != "", "the footer has a build id")

	# -- the dials underneath are untouched ----------------------------------
	for px in SIZES:
		root.size = px
		root.content_scale_size = px
		await process_frame
		await process_frame
		var h: Rect2 = hud.head_rect()
		var b: Rect2 = hud.body_rect()
		var e: Rect2 = hud.earth_rect()
		check(not h.intersects(b), "at %dx%d head and body still do not overlap" % [px.x, px.y])
		check(not b.intersects(e), "at %dx%d body and earth still do not overlap" % [px.x, px.y])
		check(not h.intersects(e), "at %dx%d head and earth still do not overlap" % [px.x, px.y])
		check(dash.is_open(), "at %dx%d the dashboard is still standing" % [px.x, px.y])

	# -- and the words are still there ---------------------------------------
	check(String(hud.config_text()).contains("HEXY CONFIG"), "config_text() is untouched")

	# -- closing -------------------------------------------------------------
	dash.close()
	await process_frame
	check(not dash.is_open() and not dash.visible, "close() shuts it")
	hud.toggle_dashboard()
	await process_frame
	check(dash.is_open(), "toggle_dashboard() puts it back")
	hud.toggle_dashboard()
	await process_frame
	check(not dash.is_open(), "and shuts it again")

	# -- the two new panels are on the live column too ------------------------
	check(dash.panel("tunables") != null and dash.panel("tunables").get_parent() == dash.column,
		"the tunables panel stands under the seven on the real glass")
	check(dash.panel("controls") != null and dash.panel("controls").get_parent() == dash.column,
		"the controls panel stands under it")
	check(dash.tunable_control("senses.period_ms") != null,
		"and the registry reached it through the app's own autoload")

	## PANEL 10 ON THE LIVE GLASS. The app builds a loader whether any add-on
	## is on disk or not, so the doors panel must stand either way -- with six
	## need rows and four circuit rows, and a dash wherever no door lands.
	check(dash.panel("doors") != null and dash.panel("doors").get_parent() == dash.column,
		"the doors panel stands under the two on the real glass")
	check(app.addons != null, "the app built an add-on loader")
	check(String(dash.doors_text()).split("
").size() == 10,
		"the doors panel reads six need lines and four circuits")

# -- W6: exactly one radar, front or dashboard, never both -------------------

## THE FRONT'S SWIPE, DRIVING A REAL DASHBOARD. `open_dashboard()` must borrow
## the one radar the front already stands rather than leaving the panel's own
## built one in the tree; closing it must put the front's radar back exactly
## where it was, quiet, with the creature still in the room's own hub.
func _run_borrowed_radar() -> void:
	print("-- the borrowed radar (W6) --")
	var packed: PackedScene = load(SCENE)
	var app: Node = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	var front: Node = app.get_node_or_null("Hud")
	check(front != null, "a front is under the app, for the borrow test")
	if front == null:
		return

	var room_band: Node = front.room_band
	var home_index: int = int(front.radar.get_index())
	check(_count_radars(app) == 1, "one radar stands before the gear is ever opened")
	check(bool(front.radar.get("quiet")), "and it is the front's own quiet room")

	var dash: HexyDashboard = front.open_dashboard() as HexyDashboard
	await process_frame
	check(dash != null, "opening the dashboard from the front returns it")
	if dash == null:
		return
	check(_count_radars(app) == 1, "still exactly one radar while the gear stands open")
	check(dash.radar == front.radar, "and panel 6-FLY is drawing the front's own instance")
	check(not bool(front.radar.get("quiet")), "borrowed, the one radar goes loud")
	check(dash.panel("fly").get_parent() != null, "the fly panel still stands on the column")

	check(front.close_dashboard(), "the gear closes")
	await process_frame
	check(_count_radars(app) == 1, "and there is still exactly one radar after it closes")
	check(bool(front.radar.get("quiet")), "returned, the radar is quiet again")
	check(front.radar.get_parent() == room_band, "and it is back under the front's room band")
	check(int(front.radar.get_index()) == home_index, "at the very seat it left")
	var hub: Rect2 = front.radar.hub_rect()
	var field: Rect2 = Rect2(front.creature_field.position, front.creature_field.size)
	check(field.position.distance_to(hub.position) < 2.0 and absf(field.size.x - hub.size.x) < 2.0,
		"and the creature is still standing in that radar's own hub")

	## OPENING AGAIN LENDS THE SAME INSTANCE, not a fresh build.
	var dash2: HexyDashboard = front.open_dashboard() as HexyDashboard
	await process_frame
	check(dash2 == dash, "asking again opens the dashboard already built")
	check(dash2.radar == front.radar, "and it borrows the one radar a second time")
	check(_count_radars(app) == 1, "with the count still exactly one")
	front.close_dashboard()
	await process_frame

	## A BARE DASHBOARD, NEVER LENT ANYTHING, STILL BUILDS ITS OWN.
	var solo := HexyDashboard.new()
	root.add_child(solo)
	await process_frame
	check(solo.radar != null, "a dashboard nobody lent a radar to still mounts one of its own")
	check(_count_radars(app) == 1, "the app's own room is unaffected by that standalone panel")
	solo.queue_free()
	await process_frame

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


func _count_radars(from: Node) -> int:
	var n: int = 1 if from is FlyCalciumRadar2D else 0
	for kid in from.get_children():
		n += _count_radars(kid)
	return n


# -- panels 8 and 9, on a bare dashboard -------------------------------------

## A GLASS THAT HAS EVERY CONTROL METHOD, and one that has none. The dashboard
## is not allowed to care which it was handed: with this one every button is
## live, with a plain Node every button is grey, and neither is a crash.
class StubHost extends Node:
	var calls: Array[String] = []
	var walked: int = 0

	func who() -> String:
		return "stub"

	func toggle_enhanced() -> bool:
		calls.append("toggle_enhanced")
		return true

	func cycle_geometry() -> String:
		calls.append("cycle_geometry")
		return "rhombic"

	func telemetry_text() -> String:
		calls.append("telemetry_text")
		return "TELEMETRY LINE"

	func brain_text() -> String:
		calls.append("brain_text")
		return "BRAIN LINE"

	func config_text() -> String:
		calls.append("config_text")
		return "HEXY CONFIG"

	func cycle_sense_period() -> int:
		calls.append("cycle_sense_period")
		return 3500

	func mesh_broadcast() -> int:
		calls.append("mesh_broadcast")
		return 3

	func camera_reset() -> void:
		calls.append("camera_reset")

	func toggle_sensor_freeze() -> bool:
		calls.append("toggle_sensor_freeze")
		return false

	func cast_earth() -> Dictionary:
		calls.append("cast_earth")
		return {"bits": 7}

	func walk_earth(delta: int) -> void:
		calls.append("walk_earth")
		walked += delta


## THE TWO NEW PANELS, ON A DASHBOARD THAT HAS NO SCENE UNDER IT.
##
## Panels one to seven need the whole app bound to them; eight and nine need
## nothing but the registry and a host, so they are checked here on a bare
## Control -- which is also the only way this file can go green while the glass
## itself is being rebuilt next door.
func _run_widget_panels() -> void:
	print("-- tunables & controls --")
	var cfg := HexyConfig.instance()
	cfg.autosave = false
	cfg.reset()

	var dash := HexyDashboard.new()
	root.add_child(dash)
	await process_frame

	check(dash.panel("tunables") != null, "the tunables panel stands on the column")
	check(dash.panel("controls") != null, "the controls panel stands on the column")
	check(String(HexyDashboard.TITLES["tunables"]).begins_with("8 ·"), "tunables is panel 8")
	check(String(HexyDashboard.TITLES["controls"]).begins_with("9 ·"), "controls is panel 9")
	check(dash.panel("doors") != null, "the doors panel stands on the column")
	check(String(HexyDashboard.TITLES["doors"]).begins_with("10 ·"), "doors is panel 10")
	check(String(dash.doors_text()).contains("body: —"),
		"and with no loader bound it draws a dash on every row")

	# -- a control for every key in the schema -------------------------------
	var missing: Array[String] = []
	for key in cfg.keys():
		if dash.tunable_control(key) == null:
			missing.append(key)
	check(missing.is_empty(), "every schema key has a control (missing %s)" % str(missing))
	check(dash.tunable_control("pacing.beta") is HSlider, "a float key is a slider")
	check(dash.tunable_control("pacing.journal_max") is HSlider, "an int key is a slider")
	check(dash.tunable_control("qwen.one_line_only") is CheckButton, "a bool key is a check button")
	check(dash.tunable_control("hud.earth_mode") is OptionButton, "an enum key is an option button")
	var slider: HSlider = dash.tunable_control("pacing.civil_fire_s") as HSlider
	var srow: Dictionary = cfg.row("pacing.civil_fire_s")
	check(is_equal_approx(slider.min_value, float(srow["min"])), "the slider carries the schema's floor")
	check(is_equal_approx(slider.max_value, float(srow["max"])), "the slider carries the schema's ceiling")
	check(is_equal_approx(slider.step, float(srow["step"])), "and the schema's step")

	# -- moving a control writes through set_value ---------------------------
	slider.value = 7.5
	await process_frame
	check(is_equal_approx(float(cfg.get_value("pacing.civil_fire_s")), 7.5),
		"moving the slider wrote the registry (got %s)" % str(cfg.get_value("pacing.civil_fire_s")))
	check(dash.tunable_text("pacing.civil_fire_s") == "7.500",
		"and the value label followed (got %s)" % dash.tunable_text("pacing.civil_fire_s"))

	var check_button: CheckButton = dash.tunable_control("qwen.one_line_only") as CheckButton
	check_button.button_pressed = false
	await process_frame
	check(not bool(cfg.get_value("qwen.one_line_only")), "the check button wrote the registry")

	var opt: OptionButton = dash.tunable_control("hud.earth_mode") as OptionButton
	opt.select(1)
	opt.item_selected.emit(1)
	await process_frame
	check(String(cfg.get_value("hud.earth_mode")) == "stations", "the option button wrote the registry")

	# -- an OUTSIDE write comes back without a loop --------------------------
	var before: int = cfg.revision()
	cfg.set_value("pacing.civil_fire_s", 1.5)
	await process_frame
	check(is_equal_approx(slider.value, 1.5), "an outside write moved the slider")
	check(dash.tunable_text("pacing.civil_fire_s") == "1.500", "and the label with it")
	check(cfg.revision() == before + 1,
		"and the panel did not write back (revision %d, not %d)" % [cfg.revision(), before + 1])

	cfg.set_value("qwen.one_line_only", true)
	cfg.set_value("hud.earth_mode", "lines")
	await process_frame
	check(check_button.button_pressed, "an outside write moved the check button")
	check(opt.get_item_text(opt.selected) == "lines", "an outside write moved the option button")

	# -- reset, and the clipboard bridge -------------------------------------
	cfg.set_value("pacing.beta", 9.0)
	dash._on_reset_key("pacing.beta")
	check(is_equal_approx(float(cfg.get_value("pacing.beta")), float(cfg.row("pacing.beta")["default"])),
		"the row's reset arrow puts the default back")
	cfg.set_value("pacing.anchor", 0.9)
	dash._on_reset_all()
	check(is_equal_approx(float(cfg.get_value("pacing.anchor")), 0.5), "RESET ALL empties the drawer")

	## The headless display server owns no clipboard, so the round trip is only
	## claimed where there is one to make it through. The document itself is
	## checked either way -- that is the half the web studio has to agree with.
	check(JSON.parse_string(cfg.to_json()) is Dictionary, "to_json() is a JSON object")
	dash._on_copy_json()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		var copied: String = DisplayServer.clipboard_get()
		check(copied == cfg.to_json(), "COPY JSON put exactly to_json() on the clipboard")
		cfg.set_value("pacing.beta", 11.0)
		check(dash._on_paste_json(), "PASTE JSON read the clipboard back")
		check(is_equal_approx(float(cfg.get_value("pacing.beta")), 2.5),
			"and the drawer went back to what was copied")
	else:
		print("SKIP: no clipboard on this display server")
		cfg.set_value("pacing.beta", 11.0)
		check(dash._config.from_json(cfg.to_json().replace("11.0", "2.5")),
			"from_json() takes the document COPY JSON would have carried")
		check(is_equal_approx(float(cfg.get_value("pacing.beta")), 2.5),
			"and the drawer moved to what that document said")

	# -- the controls panel, with no host ------------------------------------
	for row in HexyDashboard.CONTROL_ROWS:
		var id: String = HexyDashboard._control_id(row)
		var b: Button = dash.control_button(id)
		check(b != null, "the controls panel has a button for %s" % id)
		check(b != null and b.disabled, "%s is grey while no host holds the method" % id)
	check(dash._control_buttons.size() == 12, "there are twelve controls (got %d)" % dash._control_buttons.size())

	var bare := Node.new()
	root.add_child(bare)
	dash.set_host(bare)
	check(dash.control_button("camera_reset").disabled,
		"a host without the methods still greys every button")
	bare.queue_free()

	# -- and with a host that has all twelve ---------------------------------
	var host := StubHost.new()
	root.add_child(host)
	dash.set_host(host)
	for row in HexyDashboard.CONTROL_ROWS:
		var b: Button = dash.control_button(HexyDashboard._control_id(row))
		check(not b.disabled, "%s lights up once the host has it" % b.name)

	for row in HexyDashboard.CONTROL_ROWS:
		dash.control_button(HexyDashboard._control_id(row)).pressed.emit()
	check(host.calls.size() == 12, "pressing all twelve called the host twelve times (got %d)" % host.calls.size())
	check(host.calls.has("camera_reset") and host.calls.has("cast_earth"),
		"the void one and the dictionary one both went through")
	check(host.walked == 0, "prev and next walked the earth one step each way")

	dash.control_button("telemetry_text").pressed.emit()
	check(dash.control_text() == "TELEMETRY LINE", "a text control writes its answer into the readout")
	dash.control_button("brain_text").pressed.emit()
	check(dash.control_text() == "BRAIN LINE", "and the next one replaces it")
	dash.control_button("toggle_enhanced").pressed.emit()
	check(dash.control_text().contains("toggle_enhanced"), "a flag control names itself in the readout")

	cfg.reset()
	host.queue_free()
	dash.queue_free()
	await process_frame



## W7a.7 -- THE FOUR TIMESCALES STAND ON THE COLUMN.
func _run_phase_panel() -> void:
	print("\n[ panel 11: four timescales ]")
	var packed: PackedScene = load(SCENE)
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var front: Node = app.get_node_or_null("Hud")
	if front == null:
		app.queue_free()
		return
	var dash: Node = front.open_dashboard()
	await process_frame
	await process_frame
	check(dash != null, "the gear opens")
	if dash == null:
		app.queue_free()
		return

	check(dash.panel("phase") != null, "the phase panel stands on the column")
	check(dash.panel("phase") != null and dash.panel("phase").get_parent() == dash.column,
		"as a child of the one scrolling column")
	check(HexyDashboard.PHASE_ROWS.size() == 4, "and it has exactly four timescales")
	check(dash.has_method("set_phase_snapshot"), "data comes in through set_phase_snapshot")

	## The panel is glass and reaches for no brain: everything it shows arrives
	## in one flat dictionary, which is the only way a glass file may learn
	## what a calcium phase or a chapter is.
	dash.set_phase_snapshot({
		"seconds": "calcium 0.250  morning",
		"internal_hour": 8.5,
		"offset_h": 1.25,
		"confidence": 0.75,
		"marks": [0.0, 0.25, 0.5, 0.75, 1.0, -0.5],
		"days_toward": [0, 1, 2, 3, 0, 1],
		"chapter_title": "Trials · Difficulty",
		"stage_name": "Trials",
	})
	check(dash.phase_row_text("seconds").find("calcium") >= 0, "the seconds row shows the calcium phase")
	check(dash.phase_row_text("day").find("08:30") >= 0,
		"the day row shows the internal hour (got '%s')" % dash.phase_row_text("day"))
	check(dash.phase_row_text("day").find("+1.25") >= 0, "with the offset beside it")
	check(dash.phase_row_text("day").find("0.75") >= 0, "and the confidence")
	var weeks: String = dash.phase_row_text("weeks")
	check(weeks.length() >= 6, "the weeks row draws the six marks as six bars (got '%s')" % weeks)
	check(weeks.find("days 7") >= 0, "and counts the days toward a turn")
	check(dash.phase_row_text("life").find("Trials") >= 0, "the life row names the chapter and the stage")
	check(not dash.phase_snapshot().is_empty(), "the snapshot is readable back")

	## And the front really pushes one every beat while the panel is open.
	dash.set_phase_snapshot({"seconds": "wiped"})
	front.beat()
	check(dash.phase_row_text("seconds") != "wiped",
		"the front pushes a fresh snapshot on every beat the dashboard is open")
	check(not (dash.phase_snapshot().get("marks", null) == null),
		"and the snapshot it pushes carries the six marks")

	app.queue_free()
	await process_frame
