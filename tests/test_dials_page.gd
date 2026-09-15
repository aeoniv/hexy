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

	var cx: Object = hud.central_complex()
	check(cx != null, "the store's character carries a FlyCentralComplex")
	check(cx != null and "target_heading" in cx,
		"and the goal heading on it is spelled target_heading")
	check(cx != null and is_equal_approx(float(cx.get("target_heading")), got),
		"the drag set the fan-shaped body's own goal heading")

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
