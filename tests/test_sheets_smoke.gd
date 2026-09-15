extends SceneTree

## TWO THIN SHEETS, POKED THE WAY A FINGER POKES THEM.
##
## The peer sheet and the reading sheet each take one dictionary (or two) and
## draw what they were handed -- nothing more. This file checks the drawing
## is honest (the fields that should appear do, the ones that need a flag
## don't show up without it) and that the front wires a tap on a blip or the
## figure to exactly one page, closable one way or another, with the composer
## out of the way while it stands.

const SCENE: String = "res://scenes/hexy.tscn"

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
	print("\n--- TEST SHEETS SMOKE (peer sheet, reading sheet, front wiring) ---")
	await _run_peer_sheet_unit()
	await _run_reading_sheet_unit()
	await _run_front_wiring()
	await _run_on_a_fold()
	print("--- sheets smoke: %d passed, %d failed ---" % [passes, failures])
	if failures == 0:
		print("--- ALL SHEETS SMOKE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- SHEETS SMOKE TESTS FAILED: ", failures, " ---\n")
		quit(1)


# -- the peer sheet, on its own ------------------------------------------------

func _run_peer_sheet_unit() -> void:
	var sheet := PeerSheet.new()
	root.add_child(sheet)
	await process_frame

	var row: Dictionary = {
		"who": "peerabc12",
		"bits": 5,
		"moving": 0,
		"body": 5,
		"last_seen_ms": Time.get_ticks_msec(),
		"rssi": -1,
		"band": "room",
		"cls": "room",
		"heading_rad": 0.0,
		"phase": 0.3,
		"stage": 4,
	}
	sheet.show_peer(row, {})
	check(sheet.visible, "show_peer makes the sheet visible")
	check(sheet._name_label.text.begins_with("hexy-"), "the peer's short name is shown")
	check(sheet._band_label.text.contains("room"), "the band is shown")
	check(sheet._cls_label.text.contains("room"), "the proximity class is shown")
	check(sheet._trigram_label.text != "" and sheet._trigram_label.text != "?",
		"the heading trigram glyph is shown when a heading exists")
	check(not sheet._phase_label.text.contains("in phase"),
		"in_phase words are absent when the plot says nothing about it")
	check(not sheet._stage_label.text.contains("chapter ahead"),
		"mentor words are absent when the plot says nothing about it")

	sheet.show_peer(row, {"in_phase": true, "mentor": true})
	check(sheet._phase_label.text.contains("in phase with you"),
		"in_phase words appear when the plot flags it")
	check(sheet._stage_label.text.contains("one chapter ahead"),
		"mentor words appear when the plot flags it")

	var no_heading: Dictionary = row.duplicate()
	no_heading.erase("heading_rad")
	no_heading["heading_rad"] = null
	sheet.show_peer(no_heading, {})
	check(sheet._trigram_label.text == "?", "no heading draws no trigram glyph")

	# -- last seen, three cases --------------------------------------------------
	# A fixed "now" -- passed straight to the door `_last_seen_text` opens for a
	# test -- so the fake "when they were last seen" timestamp never has to race
	# the real clock.
	var now_ms: int = 1_000_000
	check(PeerSheet._last_seen_text(now_ms, now_ms).contains("just now"),
		"a peer seen this instant reads 'just now'")
	check(PeerSheet._last_seen_text(now_ms - 30000, now_ms).contains("30 s ago"),
		"a peer seen 30 s ago reads '30 s ago'")
	check(PeerSheet._last_seen_text(now_ms - 125000, now_ms).contains("2 min ago"),
		"a peer seen over two minutes ago reads '2 min ago'")

	# -- the trigram glyph toggles guidance --------------------------------------
	var requested: Array = []
	var cleared: Array = []
	sheet.guide_requested.connect(func(who: String) -> void: requested.append(who))
	sheet.guide_cleared.connect(func() -> void: cleared.append(1))
	var trigram_button: Control = sheet.get_node("Panel/Margin/Col/TrigramTap")
	trigram_button.gui_input.emit(_tap(Vector2(24.0, 24.0)))
	check(requested.size() == 1 and String(requested[0]) == "peerabc12",
		"tapping the trigram glyph asks for guidance to this peer")
	trigram_button.gui_input.emit(_tap(Vector2(24.0, 24.0)))
	check(cleared.size() == 1, "tapping it again cancels guidance")

	# -- THE WAYS OUT (device bug 5) ---------------------------------------------
	## On the phone this sheet had NO working dismiss: swipe-down and tap-outside
	## both left it standing, and while it stood it ate the front's swipe-up. The
	## panel covers the top of the glass and STOPs input of its own, so the swipe
	## never reached the sheet at all -- and there was no tap-outside to fall
	## back on. Three ways out now, and each of them is checked.
	var closed: Array = []
	sheet.closed.connect(func() -> void: closed.append(1))
	var panel: Control = sheet.panel

	## 1. A SHORT DRAG ON THE PANEL IS NOT A WAY OUT: the panel is what a person
	## is reading and a nudge on it must not throw it away.
	panel.gui_input.emit(_press(Vector2(200.0, 100.0)))
	panel.gui_input.emit(_tap(Vector2(200.0, 90.0)))
	check(closed.is_empty(), "a short drag on the panel is not a way out")
	panel.gui_input.emit(_tap(Vector2(200.0, 90.0)))
	check(closed.is_empty(), "and a plain tap on the panel is not one either")

	## 2. SWIPE DOWN, STARTED ON THE PANEL -- which is where a finger that means
	## to throw a sheet away actually starts.
	panel.gui_input.emit(_press(Vector2(200.0, 100.0)))
	panel.gui_input.emit(_tap(Vector2(200.0, 220.0)))
	check(closed.size() == 1, "a swipe down off the panel closes the sheet")

	## 3. SWIPE DOWN ON THE GROUND, the way it always worked.
	closed.clear()
	sheet.gui_input.emit(_press(Vector2(200.0, 100.0)))
	sheet.gui_input.emit(_tap(Vector2(200.0, 220.0)))
	check(closed.size() == 1, "a swipe down on the ground closes it too")

	## 4. A TAP ON THE GROUND BESIDE THE PANEL dismisses, which is the gesture
	## every sheet on every phone answers and this one did not.
	closed.clear()
	sheet.gui_input.emit(_press(Vector2(200.0, 900.0)))
	sheet.gui_input.emit(_tap(Vector2(200.0, 900.0)))
	check(closed.size() == 1, "a tap outside the panel dismisses the sheet")

	root.remove_child(sheet)
	sheet.queue_free()


# -- the reading sheet, on its own ---------------------------------------------

func _run_reading_sheet_unit() -> void:
	for bits in [0, 63, 21]:
		var sheet := ReadingSheet.new()
		root.add_child(sheet)
		await process_frame
		var chapter: Dictionary = Journey.chapter(bits & 63, Journey.Stage.ORDINARY)
		sheet.show_reading(bits, chapter)
		check(sheet.visible, "show_reading(%d) makes the sheet visible" % bits)
		check(sheet._glyph_label.text == KingWen.glyph(bits & 63),
			"bits %d: the large glyph matches KingWen" % bits)
		check(sheet._title_label.text.contains("#%d" % KingWen.number(bits & 63))
				and sheet._title_label.text.contains(KingWen.name(bits & 63)),
			"bits %d: the title carries the King Wen number and name" % bits)
		check(sheet._lines_box.get_child_count() == 6,
			"bits %d: six bars are drawn" % bits)
		check(sheet._chapter_label.text == String(chapter.get("title", "")),
			"bits %d: the chapter title is shown" % bits)
		root.remove_child(sheet)
		sheet.queue_free()

	# an empty chapter dictionary falls back to ORDINARY rather than a blank line
	var sheet2 := ReadingSheet.new()
	root.add_child(sheet2)
	await process_frame
	sheet2.show_reading(0, {})
	check(sheet2._chapter_label.text.contains("Ordinary World"),
		"an unwalked chapter reads Ordinary World rather than nothing")
	root.remove_child(sheet2)
	sheet2.queue_free()


# -- the front wires a tap to exactly one page ---------------------------------

func _run_front_wiring() -> void:
	var packed: PackedScene = load(SCENE)
	check(packed != null, "scenes/hexy.tscn loads")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	root.size = Vector2i(1080, 2408)
	root.content_scale_size = Vector2i(1080, 2408)
	root.add_child(app)
	await process_frame
	await process_frame

	var front: Node = app.get("front")
	check(front != null and front is Front, "the app mounted a Front")
	if front == null:
		return
	front.beat()
	await process_frame
	front._beat_timer.stop()

	# -- a peer sheet opens on a tapped blip -------------------------------------
	front.radar.set_peer_proximity({"peersheet01": "room"})
	front.radar.set_peer_headings({"peersheet01": 1.0})
	front.radar.refresh_blips()
	var spots: Dictionary = front.radar.blip_positions()
	check(spots.has("peersheet01"), "a fake peer is plotted on the radar")
	front.radar.gui_input.emit(_tap(spots["peersheet01"] as Vector2))
	await process_frame
	check(front.peer_sheet_open(), "tapping the blip opens the peer sheet")
	check(not front.composer.visible, "the composer is hidden while the peer sheet stands")
	check(not front.reading_sheet_open(), "and the reading sheet is not also open")

	front.radar.gui_input.emit(_tap(spots["peersheet01"] as Vector2))
	await process_frame
	check(front.peer_sheet_open(), "tapping again keeps one sheet open, not a second")

	## THE SHEET'S OWN DISMISS REACHES THE FRONT (device bug 5). A tap on the
	## ground says `closed`, the front hears it, and the front comes back whole.
	front.peer_sheet.gui_input.emit(_press(Vector2(200.0, 900.0)))
	front.peer_sheet.gui_input.emit(_tap(Vector2(200.0, 900.0)))
	await process_frame
	check(not front.peer_sheet_open(), "a tap outside the panel closes the sheet on the front")
	check(front.composer.visible, "and the composer comes back with it")
	## AND A CLOSED SHEET IS NOT A WALL. It is a full-rect STOP: while it is
	## down it must not be in the tree's way, or the front's own swipe-up off
	## the composer -- which is what the device could not do -- lands on it.
	check(not front.peer_sheet.is_visible_in_tree(),
		"a closed peer sheet is not in the tree's way at all")
	var dash: Array = []
	front.dashboard_requested.connect(func() -> void: dash.append(1))
	front.composer.gui_input.emit(_press(Vector2(200.0, 120.0)))
	front.composer.gui_input.emit(_tap(Vector2(200.0, 120.0 - front.swipe_threshold() - 1.0)))
	check(dash.size() == 1, "and the front's swipe-up is heard again once it is gone")
	front.close_dashboard()
	await process_frame

	front.radar.gui_input.emit(_tap(spots["peersheet01"] as Vector2))
	await process_frame
	check(front.peer_sheet_open(), "the sheet opens once more")
	check(front.back_requested(), "and Android's back button closes it")
	check(not front.peer_sheet_open(), "and it is gone")
	check(front.composer.visible, "the composer comes back")

	# -- THE GUIDE ARROW REACHES THE RADAR (device bug 6) ------------------------
	## On the phone, tapping the guide glyph drew no rim arrow. The wiring is
	## checked end to end here: the sheet's tap, the front's handler, the
	## radar's own `guide_id`, and the arrow's two preconditions -- the peer
	## must be PLOTTED and must not be sitting on the ring, because a ring has
	## no direction in it and the radar will not invent one.
	front.radar.set_peer_proximity({"peersheet01": "room"})
	front.radar.set_peer_headings({"peersheet01": 1.0})
	## A BEARING, NOT A FLY HEADING. `set_peer_headings` says which way the peer
	## is FACING, which says nothing about which way they are FROM here: the
	## radar gives such a peer the widest spread there is and calls the plot a
	## ring, and a ring has no direction to point at. Only `set_peer_bearings`
	## makes a plot the rim arrow can be drawn from.
	front.radar.set_peer_bearings({"peersheet01": 1.0})
	front.radar.refresh_blips()
	front.radar.guide_id = ""
	front.radar.gui_input.emit(_tap(spots["peersheet01"] as Vector2))
	await process_frame
	check(front.peer_sheet_open(), "the peer sheet is standing for the guide tap")
	var tap_target: Control = front.peer_sheet.get_node("Panel/Margin/Col/TrigramTap")
	tap_target.gui_input.emit(_tap(Vector2(24.0, 24.0)))
	await process_frame
	check(String(front.radar.guide_id) == "peersheet01",
		"tapping the guide glyph puts that peer in the radar's guide_id")
	var plots: Dictionary = front.radar.peer_plots()
	check(plots.has("peersheet01"), "and the radar has a plot for them to point at")
	check(not bool((plots["peersheet01"] as Dictionary).get("ring", true)),
		"the plot carries a real bearing, so the rim arrow has a direction to draw")
	## AND THE OTHER WAY ROUND, which is the state a real phone is in: with only
	## a fly heading to go on the plot is a ring and the radar draws no arrow --
	## honestly, because it does not know which way to point.
	front.radar.set_peer_bearings({})
	front.radar.refresh_blips()
	check(bool((front.radar.peer_plots()["peersheet01"] as Dictionary).get("ring", false)),
		"with no bearing the same peer is a ring, and a ring gets no arrow")
	front.radar.set_peer_bearings({"peersheet01": 1.0})
	front.radar.refresh_blips()
	tap_target.gui_input.emit(_tap(Vector2(24.0, 24.0)))
	await process_frame
	check(String(front.radar.guide_id) == "", "tapping it again lets the peer go")
	check(front.close_peer_sheet(), "the sheet closes")
	check(not front.peer_sheet_open(), "and it is gone")
	check(front.composer.visible, "the composer comes back")

	# -- a reading sheet opens on the figure --------------------------------------
	front.glyph_band.gui_input.emit(_tap(Vector2(20.0, 20.0)))
	await process_frame
	check(front.reading_sheet_open(), "tapping the figure opens the reading sheet")
	check(not front.composer.visible, "the composer is hidden while the reading sheet stands")
	check(not front.peer_sheet_open(), "and the peer sheet is not also open")

	front.glyph_band.gui_input.emit(_tap(Vector2(20.0, 20.0)))
	await process_frame
	check(front.reading_sheet_open(), "tapping the figure again does not add a second page")
	check(_count_children_of_type(front, "ReadingSheet") == 1, "and never builds a second one")

	check(front.back_requested(), "Android's back button closes the reading sheet")
	check(not front.reading_sheet_open(), "and it is gone")
	check(front.composer.visible, "the composer comes back")
	check(not front.back_requested(), "a second back request on the front itself does nothing")

	# -- opening the dials closes a standing sheet, and the reverse -------------
	front.radar.gui_input.emit(_tap(spots["peersheet01"] as Vector2))
	await process_frame
	check(front.peer_sheet_open(), "the peer sheet opens once more")
	front.open_dials()
	await process_frame
	check(front.dials_open(), "opening the dials opens the dials")
	check(not front.peer_sheet_open(), "and closes the peer sheet standing in the way")
	front.close_dials()

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


# -- the poking -----------------------------------------------------------------

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


func _count_children_of_type(parent: Node, type_name: String) -> int:
	var n: int = 0
	for kid in parent.get_children():
		if type_name == "ReadingSheet" and kid is ReadingSheet:
			n += 1
		elif type_name == "PeerSheet" and kid is PeerSheet:
			n += 1
		n += _count_children_of_type(kid, type_name)
	return n
# -- the two sheets on a Galaxy Z Fold4, poked through the viewport -----------

## W11 -- A FINGER, NOT A SIGNAL.
##
## Every check above reaches into `control.gui_input.emit(...)`, which skips
## hit-testing entirely -- and hit-testing is precisely what was broken on the
## device. Here the whole app is stood up inside a SubViewport the size of the
## fold's inner screen (1812 x 2176) and the events are pushed at GLOBAL
## coordinates, so the engine decides for itself which Control is under the
## finger. That is the only way this file could ever have caught either of
## these: both sheets measured 0 x 0 under their CanvasLayer, so the reading
## sheet drew a small panel in the top-left corner of a very tall screen (it
## looked like the tap had done nothing at all) and the peer sheet's ground
## had no area for a tap-outside to land on.
var _sub: SubViewport = null


func _run_on_a_fold() -> void:
	print("-- both sheets on an 1812x2176 glass, hit-tested --")
	_sub = SubViewport.new()
	_sub.size = Vector2i(1812, 2176)
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.handle_input_locally = true
	root.add_child(_sub)
	var app: Node = (load(SCENE) as PackedScene).instantiate()
	_sub.add_child(app)
	for i in 8:
		await process_frame
	var front: Node = app.get_node_or_null("Hud")
	check(front != null, "a front stands in the fold-sized viewport")
	if front == null:
		return
	var glass := Vector2(1812.0, 2176.0)
	check(front.root.size.is_equal_approx(glass),
		"and it has the whole glass (got %s)" % front.root.size)

	# -- the reading sheet, opened by a finger on the figure -----------------
	await _finger(_mid(front.glyph_band))
	check(front.reading_sheet_open(), "a real tap on the hexagram bar opens the reading sheet")
	if front.reading_sheet_open():
		var r: Rect2 = front.reading_sheet.get_global_rect()
		check(r.size.is_equal_approx(glass),
			"and the sheet is the whole glass, not a panel in the corner (got %s)" % r.size)
		check(front.reading_sheet.panel.get_global_rect().size.x > glass.x * 0.5,
			"its panel spans the width a person can read")
		check(front.glyph_label.text != "", "the hexagram bar still names a figure")
		check(front.close_reading_sheet(), "the sheet closes")
		await process_frame
		## AND A SECOND TAP OPENS IT AGAIN, which is what "it only cycles the
		## hexagram" would look like if it did not.
		await _finger(_mid(front.glyph_band))
		check(front.reading_sheet_open(), "and tapping the bar a second time opens it again")
		front.close_reading_sheet()
		await process_frame

	# -- the peer sheet, dismissed by a finger on the ground -----------------
	front._open_peer_sheet("foldpeer01")
	for i in 4:
		await process_frame
	check(front.peer_sheet_open(), "a peer sheet stands")
	var sheet: Control = front.peer_sheet
	check(sheet.get_global_rect().size.is_equal_approx(glass),
		"and it owns the whole glass, so there is a catcher behind the panel (got %s)"
		% sheet.get_global_rect().size)
	check(sheet.mouse_filter == Control.MOUSE_FILTER_STOP, "and that catcher STOPs a finger")
	var panel_rect: Rect2 = sheet.panel.get_global_rect()
	var ground_pt := Vector2(glass.x * 0.5, panel_rect.end.y + (glass.y - panel_rect.end.y) * 0.5)
	check(not panel_rect.has_point(ground_pt), "there is ground below the panel to tap")
	await _finger(ground_pt)
	check(not front.peer_sheet_open(),
		"and a tap on the ground beside the panel dismisses the sheet")
	check(front.composer.visible, "the composer comes back with it")

	## A TAP ON THE PANEL ITSELF IS NOT A DISMISSAL.
	front._open_peer_sheet("foldpeer01")
	for i in 4:
		await process_frame
	await _finger(front.peer_sheet.panel.get_global_rect().position + Vector2(400.0, 8.0))
	check(front.peer_sheet_open(), "a tap ON the panel leaves the sheet standing")
	front.close_peer_sheet()
	await process_frame

	app.wmn.stop()
	_sub.remove_child(app)
	app.queue_free()
	root.remove_child(_sub)
	_sub.queue_free()
	_sub = null
	await process_frame


static func _mid(c: Control) -> Vector2:
	var r: Rect2 = c.get_global_rect()
	return r.position + r.size * 0.5


## One finger down and up in the same place, pushed at the viewport so the
## engine does its own hit-testing.
func _finger(at: Vector2) -> void:
	_sub.push_input(_at(at, true))
	await process_frame
	_sub.push_input(_at(at, false))
	await process_frame
	await process_frame


static func _at(at: Vector2, down: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	return ev

