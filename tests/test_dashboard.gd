extends SceneTree

## THE GEAR OPENS THE INSTRUMENT PANEL.
##
## scenes/hexy.tscn is booted for real and the configure button's own handler
## is called -- the same path a finger takes -- and then every claim the
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
	await _run()
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

	var hud: Node = app.get_node_or_null("Hud")
	check(hud != null, "the glass is under the app")
	if hud == null:
		return
	var store: HexyStore = app.store

	var dash: HexyDashboard = hud.dashboard
	check(dash != null, "the glass built a dashboard at bind()")
	if dash == null:
		return
	check(not dash.is_open(), "and it is hidden at boot")
	check(not dash.visible, "the overlay takes no pixel until it is asked for")

	# -- the gear ------------------------------------------------------------
	hud._on_configure_pressed()
	await process_frame
	check(dash.is_open() and dash.visible, "the configure button opens it")

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
	hud._on_configure_pressed()
	await process_frame
	check(dash.is_open(), "the gear toggles it back open")
	hud._on_configure_pressed()
	await process_frame
	check(not dash.is_open(), "and the gear shuts it again")
