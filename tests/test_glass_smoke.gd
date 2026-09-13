extends SceneTree

## THE THIRD GLASS, BOOTED FOR REAL.
##
## scenes/hexy.tscn is instanced into a live tree with no device, no model and
## no room, and then poked exactly the way a finger would poke it: a tick on
## the head ring, a station on the earth ring, a hub, a question in the
## composer. Nothing here calls a private helper -- every act goes through the
## signal or the input a real touch would have raised, because a smoke test
## that takes a shortcut the user cannot take is testing a program nobody runs.
##
## AND IT IS MEASURED TWICE. The five bands are checked at 1080x2408 and again
## at 1812x2176, because "nothing overlaps" is a claim about a layout, not
## about a screenshot, and a layout that is only true at one size is not a
## layout.

const SCENE: String = "res://scenes/hexy.tscn"

## The two phones this surface has to be right on: a tall slab and a fold.
const SIZES: Array[Vector2i] = [Vector2i(1080, 2408), Vector2i(1812, 2176)]

## Still air: a phone lying on a desk, saying the same thing every tick.
const STILL: Dictionary = {
	"gravity": Vector3(0.0, -9.8, 0.0),
	"accel": Vector3(0.0, -9.8, 0.0),
	"local_hour": 12.0,
	"battery_pct": 55.0,
	"screen_on": true,
}

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST GLASS SMOKE (boot + three dials + bubble + composer) ---")
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
	var hud: Hud3 = app.hud

	# -- the status strip ----------------------------------------------------
	await process_frame
	var strip: String = hud.status_text()
	print("status: ", strip)
	check(hud.status_strip() != null, "the status strip is a panel of its own")
	var summary: String = hud.status_summary()
	print("summary: ", summary)
	check(strip.strip_edges() != "", "the status strip says something")
	check(strip.contains("\n"), "the status strip holds its figures over its news")
	check(strip.contains("HEAD") and strip.contains("BODY"),
		"the figures hold the top line whatever else is happening")
	check(summary.contains("FPS"), "the strip's state carries the frame rate")
	check(_is_ascii_but_marks(summary),
		"the strip's own summary is ASCII but for the owner's marks")
	check(summary.contains("HEAD") and summary.contains("BODY"),
		"the summary names both figures")
	check(summary.contains(KingWen.zh(int(store.head_bits()))),
		"and carries the owner's own character for the HEAD figure")
	check(summary.contains(Hud3.MOON) and summary.contains(Hud3.SUN),
		"and marks them with the owner's moon and sun")

	# -- the bubble is a reply, not a greeting -------------------------------
	check(not hud.bubble_visible(), "nothing is speaking at boot, so no bubble stands")

	# -- three dials, and they keep out of each other's way -------------------
	check(hud.head_dial() is MandalaDial2D, "the head ring is the owner's MandalaDial2D")
	check(hud.head_dial() is MandalaDialTap, "and the drag has been taken out of it")
	check(hud.body_dial() is BodyDial2D, "the body ring is the owner's BodyDial2D")
	check(hud.body_dial() is BodyDialTap, "and the drag has been taken out of it too")
	check(hud.earth_dial() is EarthDial2D, "the earth ring is the new EarthDial2D")

	for px in SIZES:
		await _use(px)
		var h: Rect2 = hud.head_rect()
		var b: Rect2 = hud.body_rect()
		var e: Rect2 = hud.earth_rect()
		print("at %dx%d: head %s body %s earth %s" % [px.x, px.y, h, b, e])
		check(h.size.x > 8.0 and b.size.x > 8.0 and e.size.x > 8.0,
			"at %dx%d all three dials have a band" % [px.x, px.y])
		check(not h.intersects(b), "at %dx%d head and body do not overlap" % [px.x, px.y])
		check(not b.intersects(e), "at %dx%d body and earth do not overlap" % [px.x, px.y])
		check(not h.intersects(e), "at %dx%d head and earth do not overlap" % [px.x, px.y])
		check(h.end.y <= b.position.y and b.end.y <= e.position.y,
			"at %dx%d the bands are in order down the glass" % [px.x, px.y])

	await _use(SIZES[0])

	# -- a tick on the head ring walks the HEAD ------------------------------
	check(store.has_method("set_head"), "the store keeps a HEAD of its own")
	var dial: MandalaDialTap = hud.head_dial() as MandalaDialTap
	var from_slot: int = dial.head_slot()
	var want_slot: int = (from_slot + 17) % 64
	var ang: float = dial.dial_angle + float(want_slot) * (TAU / 64.0)
	var reach: float = dial.dial_radius * 0.95
	dial._gui_input(_tap(dial.dial_center + Vector2(cos(ang), sin(ang)) * reach))
	await process_frame
	var want_bits: int = int(HuohoutuData.get_head_hex(want_slot).get("bits", -1))
	print("head walked %d -> %d (bits %d)" % [from_slot, want_slot, want_bits])
	check(dial.head_slot() == want_slot, "the ring walked to the tick that was touched")
	check(store.has_method("head_bits") and int(store.head_bits()) == want_bits,
		"a tap on the head ring wrote that figure into store.head")

	# -- the earth ring casts the HEAD ---------------------------------------
	var before_head: int = int(store.head_bits()) if store.has_method("head_bits") else -1
	var earth: EarthDial2D = hud.earth_dial() as EarthDial2D
	var cast_at: Vector2 = earth.station_position(0)
	check(earth.station_label(0).contains("CAST HEAD"), "station 0 is the owner's CAST HEAD")
	var turned: bool = false
	for attempt in range(6):
		earth._gui_input(_tap(cast_at))
		await process_frame
		if store.has_method("head_bits") and int(store.head_bits()) != before_head:
			turned = true
			break
	check(turned, "the CAST HEAD station throws six coins and the HEAD changes")

	# -- stillness walks the BODY one line at a time -------------------------
	check(app.alchemy != null, "the app built an Alchemy and bound it")
	if app.alchemy != null:
		app.senses.period_ms = 100
		app.senses.reset()
		var t0: int = 5_000_000
		app.senses.tick(t0, STILL)
		app.alchemy.tick(t0)
		await process_frame
		var body0: int = _body_bits(store)
		var now: int = t0
		while now < t0 + 2600:
			now += 200
			app.senses.tick(now, STILL)
			app.alchemy.tick(now)
		await process_frame
		var body1: int = _body_bits(store)
		var turned_lines: int = _ones(body0 ^ body1)
		print("body %d -> %d over 2.6 s of stillness (%d lines)" % [body0, body1, turned_lines])
		check(turned_lines == 1,
			"2.5 s of stillness turns exactly one line of the BODY (turned %d)" % turned_lines)

	# -- the bubble appears on a hub tap, and goes away by itself -------------
	hud.bubble.fade_ms = 150
	hud.bubble.close()
	earth._gui_input(_tap(earth.dial_center))
	await process_frame
	print("bubble: ", hud.bubble_text())
	check(hud.bubble_visible(), "a tap on the earth hub pops the bubble")
	check(hud.bubble_text().strip_edges() != "", "and the bubble is carrying words")
	check(GlassBubble.FADE_MS == 6000, "a bubble stands six seconds unless a test says otherwise")
	await create_timer(0.4).timeout
	await process_frame
	check(not hud.bubble_visible(), "the bubble fades on its own")

	# -- a sense speaks next to the dot that was touched ----------------------
	hud.bubble.fade_ms = GlassBubble.FADE_MS
	var dot: Vector2 = dial.trigram_position(int(store.human.get("trigram", 0)))
	dial._gui_input(_tap(dot))
	await process_frame
	check(hud.bubble_visible(), "a tap on a human dot pops the bubble")
	print("dot says: ", hud.bubble_text())
	check(hud.bubble_text().strip_edges() != "", "and that human sense has a sentence")
	hud.bubble.close()

	# -- a question is answered ----------------------------------------------
	store.set_answer("")
	check(hud.composer_send("what is this moment"), "the composer takes a question")
	check(not hud.composer_send("   "), "and refuses an empty one")
	var waited: float = 0.0
	while store.answer == "" and waited < 2.0:
		await create_timer(0.05).timeout
		waited += 0.05
	check(store.answer != "", "an answer landed in the store within 2 s: %s" % store.answer)
	await process_frame
	check(hud.bubble_text().strip_edges() != "", "and the bubble is carrying it")

	# -- the creature stands inside the body ring -----------------------------
	check(app.creature.get_parent() == hud.view, "the creature stands in the stage viewport")
	check(hud.view.get_node_or_null("WorldEnvironment") != null,
		"the stage carries the owner's environment")
	check(hud.view.get_node_or_null("DirectionalLight3D") != null
			and hud.view.get_node_or_null("DirectionalLight3D2") != null,
		"the stage carries the owner's two lights")
	check(hud.creature_field.get_global_rect().size.x > 8.0,
		"the creature has a square of its own to be tapped in")

	app.wmn.stop()
	root.remove_child(app)
	app.queue_free()
	await process_frame


# -- the poking ---------------------------------------------------------------

## One tap: the release a finger leaves behind, which is the only event any
## dial on this surface listens for.
static func _tap(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = at
	return ev


## Put the glass on a phone of this size and let the layout settle.
func _use(px: Vector2i) -> void:
	root.size = px
	root.content_scale_size = px
	await process_frame
	await process_frame


static func _body_bits(store: HexyStore) -> int:
	if store.has_method("body_bits"):
		return int(store.body_bits()) & 63
	return int(store.primary()) & 63


static func _ones(n: int) -> int:
	var c: int = 0
	for i in range(6):
		if ((n >> i) & 1) == 1:
			c += 1
	return c


## ASCII, plus the marks the owner puts on his own figures: the moon and the
## sun, and the Chinese character HuohoutuData spells each figure with.
static func _is_ascii_but_marks(s: String) -> bool:
	for c in s:
		var u: int = c.unicode_at(0)
		if u <= 126:
			continue
		if u >= 0x4E00 and u <= 0x9FFF:
			continue
		if (Hud3.MOON + Hud3.SUN).contains(c):
			continue
		return false
	return true


static func _is_ascii(s: String) -> bool:
	for c in s:
		if c.unicode_at(0) > 126:
			return false
	return true
