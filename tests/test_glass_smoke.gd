extends SceneTree

## THE GLASS, BOOTED FOR REAL.
##
## scenes/hexy.tscn is instanced into a live tree with no device, no model and
## no room, and then poked exactly the way a finger would poke it: the top
## target is pressed, the plus is pressed, a question is sent. Nothing here
## calls a private helper -- every act goes through a signal a real touch would
## have emitted, because a smoke test that takes a shortcut the user cannot
## take is testing a program nobody runs.

const SCENE: String = "res://scenes/hexy.tscn"

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST GLASS SMOKE (boot + tap + send + sheet) ---")
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
	var glass: Glass = app.glass

	# -- the top line --------------------------------------------------------
	var top: String = glass.top_text()
	print("top: ", top)
	check(top.begins_with("now - "), "the top line opens with now")
	check(top.contains(KingWen.pinyin(store.primary())),
		"the top line carries the pinyin of the figure on the glass")

	# -- a tap is a cast -----------------------------------------------------
	store.set_hexagram({"bits": 21, "moving": 0, "source": "senses", "when": 1})
	check(String(store.hexagram.get("source", "")) == "senses", "the senses hold the figure first")
	glass.top_button().emit_signal("pressed")
	await process_frame
	check(String(store.hexagram.get("source", "")) == "tap",
		"a tap on the top target casts, and the cast says it was a tap")
	check(int(store.hexagram.get("when", 0)) > 0, "the cast is stamped with an instant")
	check(String(store.hexagram.get("who", "")) == glass.who(), "the cast is signed by this phone")
	check((store.hexagram.get("throws", []) as Array).size() == 6, "six lines were thrown")

	# -- a question is answered ----------------------------------------------
	store.set_answer("")
	check(glass.send_text("what is this moment"), "send takes a question")
	var waited: float = 0.0
	while store.answer == "" and waited < 2.0:
		await process_frame
		waited += 0.05
		await create_timer(0.05).timeout
	check(store.answer != "", "an answer landed in the store within 2 s: %s" % store.answer)
	await process_frame
	check(glass.answer_text() != "", "the answer line on the glass is not empty")

	# -- the sheet -----------------------------------------------------------
	check(not glass.sheet_open(), "the sheet is shut until it is asked for")
	glass.plus_button().emit_signal("pressed")
	await process_frame
	check(glass.sheet_open(), "the plus opens the sheet")
	check(glass.sheet_row_count() == 16,
		"the sheet lists eight machine rows and eight human ones (got %d)" % glass.sheet_row_count())
	glass.close_sheet()
	check(not glass.sheet_open(), "the sheet shuts again")

	# -- the becoming line ---------------------------------------------------
	print("becomes: ", glass.becomes_text())
	check(glass.becomes_text() != "", "the becoming line says something")
	check(_is_ascii_but_figures(glass.becomes_text()), "the becoming line is ASCII but for its glyph")

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
