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

	# -- swipe down closes --------------------------------------------------------
	var closed: Array = []
	sheet.closed.connect(func() -> void: closed.append(1))
	sheet.gui_input.emit(_press(Vector2(200.0, 100.0)))
	sheet.gui_input.emit(_tap(Vector2(200.0, 90.0)))
	check(closed.is_empty(), "a short drag down is not a swipe")
	sheet.gui_input.emit(_press(Vector2(200.0, 100.0)))
	sheet.gui_input.emit(_tap(Vector2(200.0, 220.0)))
	check(closed.size() == 1, "a drag of more than eighty pixels down closes the sheet")

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
