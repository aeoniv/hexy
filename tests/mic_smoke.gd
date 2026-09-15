extends SceneTree

## THE MIC, WALKED END TO END WITH NO PHONE IN THE ROOM.
##
## Two halves. First the core node on its own: start, one partial, one result,
## stopped, in that order and once each. Then the whole glass, booted the way
## test_glass_smoke boots it, poked only where a finger can reach -- the MIC
## button -- and asked the one question that matters about a microphone:
## DID IT SEND ANYTHING BY ITSELF? It must not. The result lands in the
## composer line and waits there for a person to tap SEND.

const SCENE: String = "res://scenes/hexy.tscn"

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST MIC SMOKE (mock flow + button + no auto-send) ---")
	await _core()
	await _glass()
	if failures == 0:
		print("--- ALL MIC SMOKE TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- MIC SMOKE TESTS FAILED: ", failures, " ---\n")
		quit(1)


## Wait, frame by frame, until the thing is true or a second has gone. A mock
## that leans on a Timer answers on the tree's own beat, and a test that names
## a number of seconds instead of the thing it is waiting for is a flake.
func _until(pred: Callable, label: String) -> void:
	var spent: float = 0.0
	while spent < 1.0:
		if bool(pred.call()):
			return
		await process_frame
		spent += 0.016
	check(false, "timed out waiting: " + label)


# -- 1. the core node --------------------------------------------------------

var _heard: Array[String] = ([] as Array[String])


func _core() -> void:
	var mic := Mic.new()
	mic.name = "Mic"
	root.add_child(mic)

	check(mic.backend_name() == "mock", "with no IxMnn the mic is the mock")
	check(mic.available(), "and the mock still counts as available")
	check(not mic.listening(), "and it starts quiet")

	mic.partial.connect(func(t: String) -> void: _heard.append("partial:" + t))
	mic.result.connect(func(t: String) -> void: _heard.append("result:" + t))
	mic.state.connect(func(s: String) -> void: _heard.append("state:" + s))
	var levels: Array[float] = ([] as Array[float])
	mic.level.connect(func(r: float) -> void: levels.append(r))

	await process_frame
	await process_frame

	check(mic.start(), "a tap starts it")
	check(mic.listening(), "and then it is listening")
	check(not mic.start(), "a second start while listening is refused")

	await _until(func() -> bool: return not mic.listening(), "the mock to stop")

	check(not mic.listening(), "the mock stops itself")
	check(_heard.size() == 4, "four things were said, not more: %s" % [_heard])
	check(_heard[0] == "state:listening", "it said listening first")
	check(_heard[1] == "partial:" + Mic.MOCK_PARTIAL, "then one partial")
	check(_heard[2] == "result:" + Mic.MOCK_TEXT, "then one result")
	check(_heard[3] == "state:stopped", "then stopped")
	check(levels.size() >= 1, "and it reported a level while it was hearing")

	mic.queue_free()


# -- 2. the glass ------------------------------------------------------------

func _glass() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		check(false, "scenes/hexy.tscn loads")
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	## THE MIC IS THE FRONT'S NOW. The dials page gave up the composer in W4;
	## the field, the button and the meter all live on the front glass.
	var hud: Front = app.front
	check(app.mic != null, "the app builds a mic")
	if not hud.has_method("set_mic"):
		print("SKIP: this glass has no MIC button yet; the core half stands alone")
		app.queue_free()
		await process_frame
		return
	check(hud.mic_button() != null, "the composer has a MIC button")
	check(not hud.mic_button().disabled, "and the mock un-greys it")
	check(hud.mic_button().text == Front.MIC_IDLE, "which says MIC while it waits")

	var sent: Array[String] = ([] as Array[String])
	app.store.answer_changed.connect(func(a: String) -> void: sent.append(a))
	hud.ask_field.text = ""

	hud.mic_button().emit_signal("pressed")
	await process_frame
	check(hud.mic_listening(), "a tap on MIC starts listening")
	check(hud.mic_button().text == Front.MIC_LIVE, "and the button says LISTENING")
	check(hud.mic_meter.visible, "and the level shows")

	await _until(func() -> bool: return hud.ask_field.text != "", "a partial")
	check(hud.ask_field.text == Mic.MOCK_PARTIAL, "the partial streams into the composer")

	await _until(func() -> bool: return not hud.mic_listening(), "the mic to stop")
	await process_frame

	check(not hud.mic_listening(), "the glass hears the stop")
	check(hud.mic_button().text == Front.MIC_IDLE, "and the button says MIC again")
	check(not hud.mic_meter.visible, "and the level goes away")
	check(hud.ask_field.text == Mic.MOCK_TEXT, "the result replaces the partial")
	check(sent.is_empty(), "AND NOTHING WAS SENT: the person still taps SEND")

	check(hud.composer_send(hud.ask_field.text), "and when they do, it goes")

	app.queue_free()
	await process_frame
