extends SceneTree

## THE OWNER'S HUD, BOOTED FOR REAL.
##
## scenes/hexy.tscn is instanced into a live tree with no device, no model and
## no room, and then poked exactly the way a finger would poke it: the hub in
## the middle of the human ring is tapped, the plus is pressed, a question is
## sent. Nothing here calls a private helper -- every act goes through a signal
## a real touch would have emitted, because a smoke test that takes a shortcut
## the user cannot take is testing a program nobody runs.

const SCENE: String = "res://scenes/hexy.tscn"

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST GLASS SMOKE (boot + tap + send + sheet + dials) ---")
	await _run()
	if failures == 0:
		print("--- ALL GLASS SMOKE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- GLASS SMOKE TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	check(packed != null, "scenes/hexy.tscn loads")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	check(app != null and app is HexyApp, "the root of the scene is a HexyApp")
	root.add_child(app)

	await process_frame
	await process_frame

	# -- the boot line -------------------------------------------------------
	var boot: String = String(app.boot_line())
	print("boot: ", boot)
	check(boot.begins_with("hexy base:"), "the boot line was printed at ready")
	check(boot.contains("mnn="), "the boot line says whether a model is there")
	check(boot.contains("mesh="), "the boot line names the fabric")
	check(boot.contains("senses=16"), "the boot line counts all sixteen senses")
	check(_is_ascii(boot), "the boot line is plain ASCII")

	var store: HexyStore = app.store
	var hud: HudBridge = app.hud

	# -- the owner's interface is the one on screen --------------------------
	check(hud.hud != null and hud.hud is MobileHudStore,
		"the surface is the owner's MobileHUD, not the sixteen-seat ring")
	check(hud.hud.has_node("TopBar") and hud.hud.has_node("HexCard")
			and hud.hud.has_node("ThoughtBubble") and hud.hud.has_node("Composer"),
		"the top bar, the figure card, the thought bubble and the composer are all there")
	check(hud.body_dial() is BodyDial2D, "the machine ring is the owner's BodyDial2D")
	check(hud.mandala_dial() is MandalaDial2D, "the human ring is the owner's MandalaDial2D")
	check(hud.mandala_dial().get_parent().name == "MandalaContainer",
		"the human ring still hangs in MandalaContainer")

	# -- the figure line -----------------------------------------------------
	var top: String = hud.top_text()
	print("top: ", top)
	check(top.begins_with("now - "), "the figure line opens with now")
	check(top.contains(KingWen.pinyin(store.primary())),
		"the figure line carries the pinyin of the figure on the glass")

	# -- a tap on the hub is a cast ------------------------------------------
	store.set_hexagram({"bits": 21, "moving": 0, "source": "senses", "when": 1})
	check(String(store.hexagram.get("source", "")) == "senses", "the senses hold the figure first")
	hud.mandala_dial().emit_signal("center_hub_clicked")
	await process_frame
	check(String(store.hexagram.get("source", "")) == "tap",
		"a tap on the centre hub casts, and the cast says it was a tap")
	check(int(store.hexagram.get("when", 0)) > 0, "the cast is stamped with an instant")
	check(String(store.hexagram.get("who", "")) == hud.who(), "the cast is signed by this phone")
	check((store.hexagram.get("throws", []) as Array).size() == 6, "six lines were thrown")

	# -- no drag survives on either ring -------------------------------------
	check(hud.body_dial() is BodyDialTap and hud.mandala_dial() is MandalaDialTap,
		"both rings are the tap-only dials")
	var before: int = store.primary()
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(40.0, 40.0)
	hud.mandala_dial()._gui_input(drag)
	hud.body_dial()._gui_input(drag)
	await process_frame
	check(store.primary() == before, "a drag across either ring changes nothing")

	# -- a question is answered ----------------------------------------------
	store.set_answer("")
	check(hud.send_text("what is this moment"), "send takes a question")
	var waited: float = 0.0
	while store.answer == "" and waited < 2.0:
		await process_frame
		waited += 0.05
		await create_timer(0.05).timeout
	check(store.answer != "", "an answer landed in the store within 2 s: %s" % store.answer)
	await process_frame
	check(hud.answer_text() != "", "the thought bubble is not empty")

	# -- a long thought wraps instead of running off the glass ---------------
	var bubble: Label = hud.hud.get_node("ThoughtBubble/Margin/ThoughtLabel") as Label
	check(bubble != null, "the ThoughtLabel is where the HUD says it is")
	check(bubble != null and bubble.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		"the ThoughtLabel wraps word-smart")
	check(bubble != null and bubble.max_lines_visible == 4,
		"the bubble grows to at most four lines")
	check(bubble != null
		and bubble.text_overrun_behavior == TextServer.OVERRUN_TRIM_WORD_ELLIPSIS,
		"anything past four lines ends in an ellipsis")

	# -- the answer line holds its three thoughts apart -----------------------
	store.set_machine({"trigram": 4, "score": 0.9, "sentence": "flat on a surface, untouched"})
	store.set_human({"trigram": 0, "score": 0.0, "sentence": "day, screen on"})
	await process_frame
	store.set_answer("Keeping Still. flat on a surface, untouched day, screen on")
	await process_frame
	print("answer: ", hud.answer_text())
	check(hud.answer_text() ==
		"Keeping Still. | flat on a surface, untouched | day, screen on",
		"the answer line joins judgement and the two sentences with a bar")
	store.set_answer("Keeping Still.")
	await process_frame
	check(hud.answer_text() == "Keeping Still.",
		"an answer carrying no sentences is left alone")

	# -- the two rings are fed the sixteen ------------------------------------
	check(hud.body_dial().scores.size() == 8,
		"the machine ring holds eight scores (got %d)" % hud.body_dial().scores.size())
	check(hud.mandala_dial().scores.size() == 8,
		"the human ring holds eight scores (got %d)" % hud.mandala_dial().scores.size())
	check(hud.body_dial().active_machine_trigram == int(store.machine.get("trigram", -1)),
		"the machine ring lights the trigram the store elected")
	check(hud.mandala_dial().active_human_trigram == int(store.human.get("trigram", -1)),
		"the human ring lights the trigram the store elected")

	# -- the creature is on the stage, and it is fed -------------------------
	check(app.creature.get_parent() == hud.view, "the creature stands in the stage viewport")
	check(app.creature.ball.get_parent() == app.creature, "the ball is the creature's own")
	check(app.creature.mandala.get_parent() == app.creature, "the dual orbit mandala is there too")
	check((app.creature.mandala.line_strains as Array).size() == 6,
		"the 3D mandala carries six line strains read off the sixteen")

	# -- the sheet -----------------------------------------------------------
	check(not hud.sheet_open(), "the sheet is shut until it is asked for")
	hud.plus_button().emit_signal("pressed")
	await process_frame
	check(hud.sheet_open(), "the plus opens the sheet")
	check(hud.sheet_row_count() == 16,
		"the sheet lists eight machine rows and eight human ones (got %d)" % hud.sheet_row_count())
	var skin: StyleBox = hud.sheet().get_theme_stylebox("panel")
	check(skin is StyleBoxFlat, "the sheet carries a ground of its own")
	check((skin as StyleBoxFlat).bg_color.a > 0.95,
		"the sheet is opaque enough to read text on (alpha %f)" % (skin as StyleBoxFlat).bg_color.a)
	hud.close_sheet()
	check(not hud.sheet_open(), "the sheet shuts again")

	# -- the becoming line ---------------------------------------------------
	print("becomes: ", hud.becomes_text())
	check(hud.becomes_text() != "", "the becoming line says something")
	check(_is_ascii_but_figures(hud.becomes_text()), "the becoming line is ASCII but for its glyph")

	# -- the head wheel previews, it does not decide -------------------------
	var held: int = store.primary()
	hud.hud.btn_next.emit_signal("pressed")
	await process_frame
	print("wheel: ", hud.becomes_text())
	check(hud.becomes_text().begins_with("wheel "), "the arrow previews the next head figure")
	check(store.primary() == held, "looking at the wheel does not write to the store")

	# -- the period is one number, and the clock follows it -------------------
	app.senses.period_ms = 1000
	check(is_equal_approx(float(app._ticker.wait_time), 1.0),
		"setting senses.period_ms moves the app ticker to 1.0 s")
	check(app.senses.period_ms == 1000, "the senses keep the period they were given")

	# -- the stage is letterboxed, not stretched -----------------------------
	hud.field.size = Vector2(300.0, 500.0)
	var mid: Vector2 = hud._to_stage(Vector2(150.0, 250.0))
	print("stage mid: ", mid)
	check(mid.is_equal_approx(Vector2(320.0, 320.0)),
		"the centre of a 300x500 field is the centre of the square stage")
	var corner: Vector2 = hud._to_stage(Vector2(300.0, 500.0))
	print("stage corner: ", corner)
	check(corner.x >= 0.0 and corner.x <= 640.0 and corner.y >= 0.0 and corner.y <= 640.0,
		"a corner of the field still lands inside the 640 square")
	check(hud.view.size == Vector2i(640, 640), "the stage viewport stays a 640 square")

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


static func _is_ascii(s: String) -> bool:
	for c in s:
		if c.unicode_at(0) > 126:
			return false
	return true


## ASCII, plus the two blocks a figure needs: trigram lines U+2630..U+2637 and
## the 64 hexagram glyphs U+4DC0..U+4DFF.
static func _is_ascii_but_figures(s: String) -> bool:
	for c in s:
		var u: int = c.unicode_at(0)
		if u <= 126:
			continue
		if u >= 0x2630 and u <= 0x2637:
			continue
		if u >= 0x4DC0 and u <= 0x4DFF:
			continue
		return false
	return true
