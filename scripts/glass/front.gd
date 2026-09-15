class_name Front
extends Node

## THE FRONT GLASS: ONE SENTENCE, ONE ROOM, ONE VOICE.
##
## The third glass put five bands and three dials on the screen at once, which
## is the right surface for a person who wants to READ the machine and the
## wrong one for a person who is just carrying it. This is the surface for the
## carrying. Top to bottom there are three things and no more:
##
##   1. THE SENTENCE. One line, at most forty-eight characters, composed by
##      `scripts/core/sentence.gd` out of the body figure, the cast, the room,
##      the day, the standing marks and the chapter. It is the whole app said
##      once, and it is the only text on the glass that is always there.
##   2. THE ROOM. ONE FlyCalciumRadar2D in quiet mode -- no wedges, no
##      neuromodulator bars, just the disc, the needle, the north caption and
##      the blips -- filling the width, with the creature standing in the
##      radar's own `hub_rect()` and the hexagram under it. A person looking at
##      this band sees where they are, who else is here, and what figure they
##      are holding, in one glance and with no chrome.
##   3. THE COMPOSER. The mic and the field the third glass already had, moved
##      across unchanged, and the bubble is still the reply.
##
## THE PAGES ARE NOT HERE. Tapping the creature opens the dials (the third
## glass, instantiated once and parked over this one); tapping a blip, the
## hexagram, or swiping up says so with a SIGNAL and stops. Whoever mounts this
## front decides what a page is; the front only ever says what was touched.
##
## TAP ONLY, and one drag. No long press, no buttons but the composer's own.

## The one skin, borrowed from the bubble so there is only one of it.
const SKIN := preload("res://scripts/glass/bubble.gd")

## THE DIALS, PRELOADED AND NEVER BUILT UNTIL ASKED FOR. The third glass is a
## heavy surface -- three dials, a dashboard, a stage of its own -- and a front
## that built one at boot would pay for a page nobody opened.
const DIALS := preload("res://scripts/glass/hud3.gd")

## THE GEAR'S PANEL, PRELOADED THE SAME WAY: heavy, and never built until a
## swipe asks for it.
const DASHBOARD := preload("res://scripts/glass/dashboard.gd")

## How often the gauge's own estimate is actually read back, in milliseconds.
## The beat is four times a second and the estimate walks a week of samples;
## the number it produces moves in hours.
const GAUGE_READ_EVERY_MS: int = 60_000

## THE TWO THIN SHEETS, preloaded and never built until a finger asks for one
## -- the same bargain the dials strike above.
const PEER_SHEET := preload("res://scripts/glass/peer_sheet.gd")
const READING_SHEET := preload("res://scripts/glass/reading_sheet.gd")

## THE SENTENCE, LOADED RATHER THAN NAMED: it belongs to the core and the core
## may land after the glass does.
## When it is on disk the bar is its words; when it is not, the bar still says
## which figure is standing, because a glass with an empty top line is a glass
## that looks broken.
const SENTENCE_PATH: String = "res://scripts/core/sentence.gd"

## The ground the whole surface stands on, kept byte for byte from the third
## glass so the two pages do not flash different colours at each other.
const GROUND: Color = Color(0.0588235, 0.0823529, 0.12549, 1.0)

## The bands. The sentence and the composer are fixed; the room takes the rest.
const SENTENCE_H: float = 52.0
const GLYPH_H: float = 56.0
const COMPOSER_H: float = 72.0
const BAND_GAP: int = 14

## The longest a sentence may be. The composer owns the same number.
const SENTENCE_MAX: int = 48

## How much of the radar's hub square the solid fills, and the solid's own
## diameter in metres -- the creature's own scale, as the third glass has it.
const CREATURE_FILL: float = 0.9
const SOLID_DIAMETER: float = 0.88

## How far up the composer a finger has to travel before it is a swipe and not
## a tap, and how far down the back bar to close the dials again.
const SWIPE_PX: float = 80.0

## The beat, when nobody is calling `beat()` for us. Four times a second, which
## is the rate the third glass composed its strip at.
const BEAT_S: float = 0.25

## A day, in seconds, for counting how long a figure has stood still.
const DAY_S: int = 86400

## The mic's two words, kept the same as the third glass's.
const MIC_IDLE: String = "MIC"
const MIC_LIVE: String = "LISTENING"
const MIC_RMS_FULL: float = 10.0

## Somebody in the room was touched.
signal peer_tapped(who: String)
## The figure under the disc was touched: the whole reading is wanted.
signal reading_tapped(bits: int)
## A finger came up off the composer: the dashboard is wanted.
signal dashboard_requested()

var layer: CanvasLayer = null
var root: Control = null
var ground: ColorRect = null
var bands: VBoxContainer = null
var pad: MarginContainer = null

var sentence_panel: PanelContainer = null
var sentence_label: Label = null

## THE ROOM. One radar, quiet, and the square the creature stands in, which is
## the radar's own `hub_rect()` and not this file's arithmetic.
var room_band: Control = null
var radar: Control = null
var creature_field: Control = null

var glyph_band: PanelContainer = null
var glyph_label: Label = null

var stage: SubViewportContainer = null
var view: SubViewport = null

var composer: PanelContainer = null
var ask_field: LineEdit = null
var btn_mic: Button = null
var mic_meter: ProgressBar = null
var btn_send: Button = null

var bubble: GlassBubble = null

## THE DIALS PAGE, once it has been asked for, and the back bar this file puts
## over it when the page has no way of closing itself yet.
var dials: Node = null
var back_layer: CanvasLayer = null
var back_bar: PanelContainer = null

## THE GEAR'S PANEL. Built the first time a swipe asks for it, either by
## reusing the dials page's own copy (so opening the dashboard from the dials
## page and opening it from the composer land on the same instance) or, when
## the dials have never been opened, one the front owns outright. Either way
## it borrows THIS front's one radar rather than growing a second.
var dashboard: Node = null

## THE TWO SHEETS, each built the first time a finger asks for it, each above
## the room but under nothing else, and never both open at once -- opening one
## closes the other, the same rule that keeps the dials the only other page.
var peer_sheet: PeerSheet = null
var reading_sheet: ReadingSheet = null
var _peer_sheet_layer: CanvasLayer = null
var _reading_sheet_layer: CanvasLayer = null

var _store: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
var _qwen: Node = null
var _heading: Node = null
var _mic: Node = null
var _creature: Node = null
var _addons: Node = null

var _who: String = "hexy"
var _stream: String = ""
var _awaiting: bool = false
var _mic_listening: bool = false

## W8e -- THE BUS AND THE GAUGE. The front SUBSCRIBES and it READS: "/body"
## for the radar and the figure, "/phase" for the four timescales, and the
## gauge for every word, band, chapter and threshold it puts on the glass.
## Neither is ever written from this file.
var _topic: RefCounted = null
var _gauge: RefCounted = null
var _body_sub: int = -1
var _phase_sub: int = -1
## The last Body and the last Phase off the bus, retained here so a beat that
## arrives between two publishes still draws the live figure.
var _body: Dictionary = {}
var _phase_msg: Dictionary = {}

## Whether a question left the composer since the last beat.
var _spoke: bool = false
## The last light reading anybody handed in. -1 is "no light sensor here".
## PUBLISHED, NOT KEPT: see [method set_lux].
var _lux: float = -1.0

## The walk, tracked from the store's body changes: where the figure came
## from, and how many days it has been sitting where it is.
var _prev_body: int = -1
var _cur_body: int = -1
var _still_since_day: int = -1
var _stage: int = -1
var _phase: float = -1.0
## The last gauge estimate, read back at most once a minute -- it walks the
## whole ring buffer and a beat is four times a second, which would be a week
## of arithmetic for a number that moves in hours.
var _phase_est: Dictionary = {}
## Wall-clock ms the estimate was last taken, so the throttle needs no timer.
var _est_at_ms: int = 0
## A FINGER ON THE EARTH RING, as a share of the day, or -1 for no finger.
## A PREVIEW ONLY: it colours the sentence's day word and the radar's own
## phase while it is held and is forgotten on release. Nothing here ever
## reaches the gauge -- a scrub is a question, not an observation.
var _scrub_phase: float = -1.0

var _sentence_script: Script = null
var _beat_timer: Timer = null
var _last_sentence: String = ""


# -- building ----------------------------------------------------------------

func _ready() -> void:
	if ResourceLoader.exists(SENTENCE_PATH):
		_sentence_script = load(SENTENCE_PATH) as Script

	layer = CanvasLayer.new()
	layer.name = "FrontGlass"
	layer.layer = 1
	add_child(layer)

	root = Control.new()
	root.name = "Front"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	ground = ColorRect.new()
	ground.name = "Ground"
	ground.color = GROUND
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ground)

	_build_stage()

	pad = MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	root.add_child(pad)

	bands = VBoxContainer.new()
	bands.name = "Bands"
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override("separation", BAND_GAP)
	pad.add_child(bands)

	_build_sentence()
	_build_room()
	_build_glyph()
	_build_composer()

	bubble = GlassBubble.new()
	root.add_child(bubble)

	_beat_timer = Timer.new()
	_beat_timer.name = "Beat"
	_beat_timer.wait_time = BEAT_S
	_beat_timer.autostart = true
	_beat_timer.timeout.connect(beat)
	add_child(_beat_timer)

	root.resized.connect(_layout_room)
	_layout_room.call_deferred()
	set_process(true)

	## THE TWO SHEETS ANSWER THE FRONT'S OWN SIGNALS. A blip or the figure is
	## touched, the front says so, and the front is also the one thing in this
	## file that knows what a peer row and a chapter look like -- so it hears
	## its own word and opens the page.
	peer_tapped.connect(_open_peer_sheet)
	reading_tapped.connect(_open_reading_sheet)
	## A SWIPE UP OFF THE COMPOSER OPENS THE PANEL ITSELF. The front is the one
	## thing that knows both what a dashboard is and which radar there is only
	## one of, so it answers its own signal rather than leaving it for whoever
	## mounts the front to reinvent.
	dashboard_requested.connect(open_dashboard)


## 1. THE SENTENCE: one line, and the app has nothing else to say up here.
func _build_sentence() -> void:
	sentence_panel = PanelContainer.new()
	sentence_panel.name = "Sentence"
	sentence_panel.custom_minimum_size = Vector2(0.0, SENTENCE_H)
	sentence_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sentence_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sentence_panel.add_theme_stylebox_override("panel", SKIN.skin())
	bands.add_child(sentence_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	sentence_panel.add_child(margin)

	sentence_label = Label.new()
	sentence_label.name = "Line"
	sentence_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sentence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sentence_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	sentence_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sentence_label.add_theme_font_size_override("font_size", 17)
	sentence_label.add_theme_color_override("font_color", Color(0.82, 0.91, 1.0, 1.0))
	sentence_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sentence_label.text = "waking"
	margin.add_child(sentence_label)


## 2. THE ROOM: the radar, quiet, filling the width, with the creature parked
## in its hub. The band expands, the radar takes the whole band, and the square
## the creature is tapped in is moved to wherever `hub_rect()` says the hub is
## -- which is the radar's floor plan and never this file's guess.
func _build_room() -> void:
	room_band = Control.new()
	room_band.name = "RoomBand"
	room_band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_child(room_band)

	radar = FlyCalciumRadar2D.new()
	radar.name = "CalciumRadar"
	radar.set_anchors_preset(Control.PRESET_FULL_RECT)
	## A STOP FILTER, BECAUSE A BLIP IS A THING YOU TAP, and the same rule the
	## third glass has: a finger outside the disc falls straight through.
	radar.mouse_filter = Control.MOUSE_FILTER_STOP
	radar.show_neuromodulators = false
	if radar.has_method("set_quiet"):
		radar.set_quiet(true)
	radar.gui_input.connect(_on_radar_input)
	room_band.add_child(radar)

	creature_field = Control.new()
	creature_field.name = "CreatureField"
	creature_field.set_anchors_preset(Control.PRESET_TOP_LEFT)
	creature_field.mouse_filter = Control.MOUSE_FILTER_STOP
	creature_field.gui_input.connect(_on_creature_input)
	room_band.add_child(creature_field)
	room_band.resized.connect(_layout_room)


## 3. THE FIGURE, under the disc: the glyph, the King Wen number and the name,
## and a tap on it asks for the whole reading.
func _build_glyph() -> void:
	glyph_band = PanelContainer.new()
	glyph_band.name = "Glyph"
	glyph_band.custom_minimum_size = Vector2(0.0, GLYPH_H)
	glyph_band.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	glyph_band.mouse_filter = Control.MOUSE_FILTER_STOP
	glyph_band.add_theme_stylebox_override("panel", SKIN.skin())
	glyph_band.gui_input.connect(_on_glyph_input)
	bands.add_child(glyph_band)

	glyph_label = Label.new()
	glyph_label.name = "Figure"
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_label.add_theme_font_size_override("font_size", 20)
	glyph_label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.70, 1.0))
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_band.add_child(glyph_label)
	_refresh_glyph()


## 4. THE COMPOSER, moved across from the third glass with nothing changed: a
## field, a mic that is honest about being a stub, a meter and a send.
func _build_composer() -> void:
	composer = PanelContainer.new()
	composer.name = "Composer"
	composer.custom_minimum_size = Vector2(0.0, COMPOSER_H)
	composer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	composer.mouse_filter = Control.MOUSE_FILTER_STOP
	composer.add_theme_stylebox_override("panel", SKIN.skin())
	composer.gui_input.connect(_on_composer_input)
	bands.add_child(composer)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	composer.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "HBox"
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	ask_field = LineEdit.new()
	ask_field.name = "Ask"
	ask_field.placeholder_text = "ask"
	ask_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask_field.custom_minimum_size = Vector2(0.0, 46.0)
	ask_field.add_theme_font_size_override("font_size", 16)
	ask_field.text_submitted.connect(_on_submitted)
	row.add_child(ask_field)

	btn_mic = Button.new()
	btn_mic.name = "Mic"
	btn_mic.text = MIC_IDLE
	btn_mic.disabled = true
	btn_mic.custom_minimum_size = Vector2(64.0, 46.0)
	btn_mic.add_theme_font_size_override("font_size", 15)
	btn_mic.pressed.connect(_on_mic_pressed)
	row.add_child(btn_mic)

	mic_meter = ProgressBar.new()
	mic_meter.name = "MicLevel"
	mic_meter.custom_minimum_size = Vector2(8.0, 0.0)
	mic_meter.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	mic_meter.show_percentage = false
	mic_meter.min_value = 0.0
	mic_meter.max_value = MIC_RMS_FULL
	mic_meter.value = 0.0
	mic_meter.visible = false
	mic_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mic_meter)

	btn_send = Button.new()
	btn_send.name = "Send"
	btn_send.text = "SEND"
	btn_send.custom_minimum_size = Vector2(74.0, 46.0)
	btn_send.add_theme_font_size_override("font_size", 15)
	btn_send.pressed.connect(_on_send_pressed)
	row.add_child(btn_send)

	## THE WHOLE BAND HEARS THE SWIPE, not just the sliver of panel the field
	## and the buttons leave uncovered.
	_watch_swipe(ask_field)
	_watch_swipe(btn_mic)
	_watch_swipe(btn_send)


## THE STAGE, under every other pixel and the whole size of the glass, which is
## the third glass's own ruling: an opaque viewport the size of the screen has
## no edge to see, and the framing is arithmetic done in `_frame_creature`.
func _build_stage() -> void:
	stage = SubViewportContainer.new()
	stage.name = "Stage"
	stage.stretch = true
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stage)

	view = SubViewport.new()
	view.name = "Stagelet"
	view.size = Vector2i(720, 1280)
	view.transparent_bg = false
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(view)
	_light_the_stage()


## The same environment and the same two lights the third glass carries, so the
## creature is lit identically wherever it is standing.
func _light_the_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = GROUND
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.25
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	view.add_child(world)

	var key := DirectionalLight3D.new()
	key.name = "DirectionalLight3D"
	key.transform = Transform3D(
		Vector3(0.866025, -0.353553, 0.353553),
		Vector3(0.0, 0.707107, 0.707107),
		Vector3(-0.5, -0.612372, 0.612372),
		Vector3(2.0, 4.0, 3.0))
	key.light_color = Color(0.9, 0.95, 1.0, 1.0)
	key.light_energy = 1.2
	view.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "DirectionalLight3D2"
	fill.transform = Transform3D(
		Vector3(-0.707107, 0.0, -0.707107),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.707107, 0.0, -0.707107),
		Vector3(-2.0, -2.0, -2.0))
	fill.light_color = Color(0.2, 0.6, 1.0, 1.0)
	fill.light_energy = 0.6
	view.add_child(fill)


# -- wiring ------------------------------------------------------------------

## THE SAME SIX OBJECTS THE THIRD GLASS IS HANDED, in the order a front reads
## them: what is true, what thinks, who else is here, what is sensed, what is
## turning, and what answers.
## W8e -- `pressure` is the dead fifth slot (it used to be the core object
## that turned a line of the body when a person stood still; nothing on the
## glass may hold a writer of organism state any more), and `topic`/`gauge`
## are the two new ones. Both trail the old six so a caller that binds
## positionally, as the tests do, keeps working unchanged.
func bind(store: Node, mnn: Node, wmn: Node, senses: Node, pressure: Node = null,
		qwen: Node = null, topic: RefCounted = null, gauge: RefCounted = null) -> void:
	_store = store
	_mnn = mnn
	_wmn = wmn
	_senses = senses
	_qwen = qwen
	var _dead: Node = pressure
	if topic != null or gauge != null:
		set_bus(topic, gauge)
	if _store != null:
		_join(_store, "body_changed", _on_body_changed)
		if not _store.has_signal("body_changed"):
			_join(_store, "hexagram_changed", _on_body_changed)
		_join(_store, "answer_changed", _on_answer_changed)
		_cur_body = _body_bits()
		_prev_body = _cur_body
		_still_since_day = _today()
	_join(_mnn, "token", _on_token)
	## A PEER THAT STOPS SHOUTING LEAVES THE DISC. The fabric's own timeout is
	## the authority; the front only forwards the word.
	_join(_wmn, "peer_gone", _on_peer_gone)
	_refresh_glyph()
	beat()


## The compass node, handed in by the app, read once a beat in `_feed_radar`.
func set_heading(h: Node) -> void:
	_heading = h


func set_senses(senses: Node) -> void:
	_senses = senses


## The creature is re-parented into the front's own stage and parked in the
## radar's hub. Nothing of it is altered but where it is looked at from.
func set_creature(creature: Node) -> void:
	_creature = creature
	if creature == null:
		return
	if creature.get_parent() != null:
		creature.get_parent().remove_child(creature)
	view.add_child(creature)
	_layout_room()


## THE BUS, SUBSCRIBED, AND THE GAUGE, HELD. Two subscriptions and no
## publishes: "/body" is the figure and the room's own needle, "/phase" is
## the four timescales. Both are LATCHED by the bus, so a front attached
## after the organism has already spoken stands on what is live rather than
## on an empty room.
func set_bus(topic: RefCounted, gauge: RefCounted) -> void:
	_gauge = gauge
	if _topic != null:
		if _body_sub >= 0:
			_topic.unsubscribe(_body_sub)
		if _phase_sub >= 0:
			_topic.unsubscribe(_phase_sub)
	_body_sub = -1
	_phase_sub = -1
	_topic = topic
	if _topic == null:
		return
	_body_sub = int(_topic.subscribe(HexyTopic.TOPIC_BODY, Callable(self, "_on_body_msg")))
	_phase_sub = int(_topic.subscribe(HexyTopic.TOPIC_PHASE, Callable(self, "_on_phase_msg")))
	var b: Dictionary = _topic.last(HexyTopic.TOPIC_BODY)
	if not b.is_empty():
		_on_body_msg(b)
	var p: Dictionary = _topic.last(HexyTopic.TOPIC_PHASE)
	if not p.is_empty():
		_on_phase_msg(p)
	if dials != null and dials.has_method("set_bus"):
		dials.set_bus(_topic, _gauge)
	if dashboard != null and dashboard.has_method("set_bus"):
		dashboard.set_bus(_topic, _gauge)


func gauge() -> RefCounted:
	return _gauge


func topic() -> RefCounted:
	return _topic


## THE BODY, OFF THE BUS. Kept whole; the radar wants it as a radar state and
## the glyph band wants only its bits, and both are taken from this one copy.
func _on_body_msg(msg: Dictionary) -> void:
	_body = msg.duplicate()


func _on_phase_msg(msg: Dictionary) -> void:
	_phase_msg = msg.duplicate()


func set_addons(addons: Node) -> void:
	_addons = addons
	if dials != null and dials.has_method("set_addons"):
		dials.set_addons(addons)


## THE BROKER, PASSED STRAIGHT THROUGH. The front has no use for it: panel 10
## of the instrument panel does, and the dashboard is only ever reached from
## here or from the dials page, so this is where the handle has to be kept.
## Without it the doors panel could only ever read the add-on loader's static
## table and never the holder actually standing on a door.
var _broker: Node = null


func set_broker(b: Node) -> void:
	_broker = b
	if dials != null and dials.has_method("set_broker"):
		dials.set_broker(b)
	if dashboard != null and dashboard.has_method("set_broker"):
		dashboard.set_broker(b)


func set_who(who_name: String) -> void:
	_who = who_name


func who() -> String:
	return _who


## THE MIC, exactly as the third glass has it: grey until the core says there
## is a recogniser, and what comes back is left in the field for a person to
## send. Nothing here sends by itself.
func set_mic(mic: Node) -> void:
	_mic = mic
	if _mic == null:
		btn_mic.disabled = true
		return
	_join(_mic, "partial", _on_mic_partial)
	_join(_mic, "result", _on_mic_result)
	_join(_mic, "error", _on_mic_error)
	_join(_mic, "level", _on_mic_level)
	_join(_mic, "state", _on_mic_state)
	btn_mic.disabled = not bool(_mic.call("available"))


func mic_button() -> Button:
	return btn_mic


func mic_listening() -> bool:
	return _mic_listening


func radar_dial() -> Control:
	return radar


## The front has one placement and it has no opinion to express about screens.
func radar_layout() -> String:
	return "front"


# -- the beat ----------------------------------------------------------------

## ONE BEAT: the room is pushed into the radar, the day is pushed into the
## clock, and the sentence is composed. Called by the app's own tick and, when
## nobody is calling it, by this file's own timer four times a second. Calling
## it twice in a row costs one extra sample and changes nothing else.
func beat() -> void:
	_feed_radar()
	_feed_clock()
	_refresh_sentence()
	_refresh_glyph()
	_feed_dashboard()
	_spoke = false


## THE FOUR TIMESCALES, PUSHED. The dashboard is glass and may not preload a
## brain; the front already holds every one of these numbers, so it hands them
## over as one flat dictionary while the panel is standing open.
func _feed_dashboard() -> void:
	if dashboard == null or not dashboard.has_method("set_phase_snapshot"):
		return
	var ch: Dictionary = current_chapter()
	var est: Dictionary = phase_estimate()
	## THE SECONDS ROW IS THE PHASE MESSAGE'S OWN when the organism has
	## published one; the radar's calcium phase is the fallback for a front
	## with no bus attached.
	var seconds: float = float(_phase_msg.get("seconds", own_phase()))
	dashboard.set_phase_snapshot({
		"radar_phase": own_phase(),
		"seconds": "calcium %.3f  %s" % [seconds, String(est.get("phase_name", ""))],
		"internal_hour": float(est.get("internal_hour", 0.0)),
		"offset_h": float(est.get("offset_h", 0.0)),
		"confidence": float(est.get("confidence", 0.0)),
		## THE WEEKS ARE THE GAUGE'S SIX LEANS -- the reading layer's standing
		## thumb on each line, which is what "pressure" now means -- with the
		## organism's own weeks count beside them.
		"marks": _marks(),
		"days_toward": [int(float(_phase_msg.get("weeks", 0.0)) * 7.0)],
		"chapter_title": String(ch.get("title", "")),
		"stage_name": String(ch.get("stage_name", "")),
	})


## EVERYTHING THE ROOM KNOWS, PUSHED. The radar reaches for nothing: the fly
## state, the headings, the proximity classes, the bearings, the phases, the
## chapters and the compass all arrive here or not at all.
func _feed_radar() -> void:
	if radar == null:
		return
	## THE ROOM'S NEEDLE COMES OFF "/body". Two keys the Body does not carry
	## -- acetylcholine (LINE_FOCUS has no Body slot) and is_startled -- are a
	## DOCUMENTED GAP in HexyMsg.body_to_radar_state, so they are still polled
	## off get_fly_state() and merged over the top, and nothing else is.
	if not _body.is_empty():
		var state: Dictionary = HexyMsg.body_to_radar_state(_body)
		var gap: Dictionary = _fly_gap()
		for k in ["acetylcholine", "is_startled"]:
			if gap.has(k):
				state[k] = gap[k]
		radar.set_state(state)
	elif _store != null and _store.has_method("get_character"):
		var ch: Variant = _store.get_character()
		if ch != null and ch.has_method("get_fly_state"):
			radar.set_state(ch.get_fly_state() as Dictionary)
	if _wmn != null:
		if _wmn.has_method("peer_headings"):
			radar.set_peer_headings(_wmn.peer_headings() as Dictionary)
		if _wmn.has_method("peer_proximity"):
			radar.set_peer_proximity(_wmn.peer_proximity() as Dictionary)
		if _wmn.has_method("peer_phase") and radar.has_method("set_peer_phase"):
			radar.set_peer_phase(_wmn.peer_phase() as Dictionary)
		if _wmn.has_method("peer_stage") and radar.has_method("set_peer_stage"):
			radar.set_peer_stage(_wmn.peer_stage() as Dictionary)
	if _heading != null and _heading.has_method("heading_rad"):
		radar.set_compass({
			"heading_rad": _heading.heading_rad(),
			"accuracy": _heading.accuracy(),
			"pose": _heading.pose(),
			"live": _heading.live(),
			"seen": _heading.seen(),
			"true_north": _heading.true_north(),
			"declination": _heading.declination(),
		})
	radar.refresh_blips()


## WHERE THIS PERSON IS IN THEIR OWN DAY, AND IN THEIR OWN STORY.
##
## W8e -- READ, NOT SAMPLED. The front used to fold a light, a motion, a
## screen flag and a spoken word into a clock of its own every beat. It does
## not any more: all four reach the gauge as Sense messages and this file only
## asks the gauge what hour it thinks it is. The internal hour that falls out
## is still the phase every other phone in the room compares itself against,
## and the chapter still comes from a rule table -- the gauge's own.
func _feed_clock() -> void:
	var day: int = _today()
	var wall: float = _wall_hour()
	## THE ESTIMATE, READ BACK ONCE A MINUTE. The front no longer SAMPLES
	## anything: the light, the motion, the screen and the spoken word all
	## reach the gauge as Sense messages, and this file only asks it what it
	## has made of them.
	var now_ms: int = Clock.now_ms()
	if _est_at_ms <= 0 or now_ms - _est_at_ms >= GAUGE_READ_EVERY_MS:
		_est_at_ms = now_ms
		_phase_est = (_gauge.call("estimate") as Dictionary) if _gauge != null else {}
	_phase = fposmod(_internal_hour(wall), 24.0) / 24.0
	var days_still: int = maxi(0, day - _still_since_day)
	var now_bits: int = _body_bits()
	if _cur_body < 0:
		_cur_body = now_bits
		_prev_body = now_bits
	## THE WHOLE WALK, NOT ONE STEP, and the rules are the gauge's own data
	## table rather than a const block: a second interpretation of the same
	## walk is a second gauge.json, not a second build.
	_stage = _stage_of(_body_path(), days_still)
	var shown: float = own_phase()
	if _wmn != null and _wmn.has_method("set_own_phase"):
		_wmn.set_own_phase(shown, _stage)
	if radar != null and radar.has_method("set_own_phase"):
		radar.set_own_phase(shown, _stage)


## THE PHASE THE GLASS IS SHOWING: the scrub's, while a finger holds the earth
## ring, and the clock's own otherwise.
func own_phase() -> float:
	return _scrub_phase if _scrub_phase >= 0.0 else _phase


## WHAT THE GAUGE HAS MADE OF THE SENSES, as a dictionary a dashboard or a
## test can read: offset_h, confidence, wake_h, sleep_h, plus the internal
## hour and its band name. A PURE READ -- nothing here writes the gauge, and
## a front with no gauge answers an honest zeroed clock rather than guessing.
func phase_estimate() -> Dictionary:
	var out: Dictionary = _phase_est.duplicate(true)
	var ih: float = _internal_hour(_wall_hour())
	out["internal_hour"] = ih
	out["phase_name"] = _phase_name(ih)
	out["phase"] = own_phase()
	if _gauge != null:
		out["confidence"] = float(_gauge.call("get_field", "confidence", 0.0))
		out["offset_h"] = float(_gauge.call("get_field", "clock_offset_h", 0.0))
	else:
		out["confidence"] = float(out.get("confidence", 0.0))
		out["offset_h"] = float(out.get("offset_h", 0.0))
	if not out.has("wake_h"):
		out["wake_h"] = 7.0
	if not out.has("sleep_h"):
		out["sleep_h"] = 23.0
	return out


## THE HOUR THE FLY SHOULD BELIEVE, off the gauge's own clock offset.
func _internal_hour(wall: float) -> float:
	if _gauge == null:
		return fposmod(wall, 24.0)
	return float(_gauge.call("internal_hour", wall))


## WHICH BAND AN INTERNAL HOUR FALLS IN, off the gauge's own band table.
func _phase_name(internal_h: float) -> String:
	if _gauge == null:
		return ""
	return String(_gauge.call("phase_name", internal_h))


## THE CHAPTER A WALK IS IN, off the gauge's own rule table.
func _stage_of(walked: Array, days_still: int) -> int:
	if _gauge == null or walked.is_empty():
		return maxi(_stage, 0)
	return int(_gauge.call("stage_of", walked, days_still))


## THE TWO KEYS A Body MESSAGE DOES NOT CARRY. Documented in HexyMsg as a
## gap, so they are polled -- and ONLY they are polled.
func _fly_gap() -> Dictionary:
	if _store == null or not _store.has_method("get_character"):
		return {}
	var ch: Variant = _store.get_character()
	if ch == null or not ch.has_method("get_fly_state"):
		return {}
	var fs: Dictionary = ch.get_fly_state() as Dictionary
	return {
		"acetylcholine": float(fs.get("acetylcholine", 0.0)),
		"is_startled": bool(fs.get("is_startled", false)),
	}


## A FINGER SCRUBBED THE EARTH RING. Preview only; released below.
func _on_earth_scrubbed(day_phase: float) -> void:
	_scrub_phase = clampf(day_phase, 0.0, 1.0)
	_refresh_sentence()


func _on_earth_released() -> void:
	_scrub_phase = -1.0
	_refresh_sentence()


## The walk the store remembers, or nothing when the store is too old to know.
func _body_path() -> Array[int]:
	if _store != null and _store.has_method("body_path"):
		return _store.body_path() as Array[int]
	return ([] as Array[int])


## THE ONE LINE. Composed by the core when the core is there, and by the figure
## alone when it is not. Trimmed here as well as there: the bar is forty-eight
## characters whoever wrote the sentence.
func _refresh_sentence() -> void:
	var s: String = _compose_sentence().strip_edges()
	if s.length() > SENTENCE_MAX:
		s = s.substr(0, SENTENCE_MAX)
	if s == "":
		s = "holding"
	_last_sentence = s
	if sentence_label != null:
		sentence_label.text = s


func _compose_sentence() -> String:
	var bits: int = _body_bits()
	if _sentence_script != null:
		## THE GAUGE IS HANDED IN when there is one, and every word table,
		## phrase and threshold in the line then comes off gauge.json rather
		## than off a const block in the core.
		var out: Variant = _sentence_script.call("of", bits, _cast_dict(), _peer_rows(),
			_day_dict(), _marks(), current_chapter(),
			_advice_clause(), _gauge)
		if out != null:
			return String(out)
	return "#%d %s" % [KingWen.number(bits), KingWen.name(bits)]


## What the altar is pointing at, as a dictionary: the earth figure, which is
## the last cast this app made.
func _cast_dict() -> Dictionary:
	if _store == null:
		return {}
	var e: Dictionary = (_store.get("earth") as Dictionary) if _store.get("earth") != null else {}
	return e.duplicate()


## The room, as the fabric keeps it. An empty array is an honest empty room.
func _peer_rows() -> Array:
	if _wmn != null and _wmn.has_method("peers"):
		return _wmn.peers() as Array
	return []


## THE DAY, AS THE FRONT KNOWS IT: which day of the person's own clock it is,
## how far round it they are, and which chapter they are in.
func _day_dict() -> Dictionary:
	return {
		"day": _today(),
		"hour": _wall_hour(),
		"internal_hour": _internal_hour(_wall_hour()),
		## THE BAND, NAMED, off the gauge's own band table. Derived from the
		## INTERNAL hour, so a night owl's "morning" is theirs -- and from the
		## scrub's hour instead while a finger is holding the earth ring,
		## which is the whole point of a preview.
		"phase_name": _phase_name(
			own_phase() * 24.0 if _scrub_phase >= 0.0
			else _internal_hour(_wall_hour())),
		"phase": own_phase(),
		"stage": _stage,
		"confidence": float(_gauge.call("get_field", "confidence", 0.0)) if _gauge != null else 0.0,
		"days_still": maxi(0, _today() - _still_since_day),
	}


## WHAT THE LIGHT IS DOING TO THE CLOCK, as one lowercase clause or "". Every
## number in it is the gauge's own -- the brightness that counts as bright,
## the window either side of wake and sleep, the words themselves.
func _advice_clause() -> String:
	if _gauge == null:
		return ""
	if _lux < float(_gauge.call("get_field", "bright_lux", 50.0)):
		return ""
	var est: Dictionary = phase_estimate()
	var a: Dictionary = _gauge.call("advice", _wall_hour(), _lux,
		float(est.get("wake_h", 7.0)), float(est.get("sleep_h", 23.0)))
	return String(_gauge.call("advice_clause", String(a.get("key", "none"))))


## THE ONE LIGHT READING, PUBLISHED, NOT KEPT. W8e: a lux sample is a Sense
## like any other, so whoever has a light sensor pushes it in here and it goes
## straight out on "/sense" as an ocelli message -- the organism routes it to
## its circadian clock and the gauge fits its own hour against it. The copy
## kept here is only what the advisory clause above reads back.
func set_lux(lux: float) -> void:
	_lux = lux
	if _topic == null or lux < 0.0:
		return
	_topic.publish(HexyTopic.TOPIC_SENSE, HexyMsg.sense("ocelli", "lux",
		Time.get_ticks_usec() * 1000, lux,
		{"wall_hour": _wall_hour(), "day": _today(), "screen_on": _screen_on()}))


## THE SIX STANDING LEANS, off the gauge. This is the reading layer's thumb
## on each line -- what the sentence calls a mark and the dashboard calls the
## weeks -- and it is data in one file, not a second body.
func _marks() -> Array:
	if _gauge == null:
		return []
	return (_gauge.call("get_field", "line_lean", []) as Array)


## THE CHAPTER THIS FIGURE IS STANDING IN, as the beat already worked it out,
## with every name and gloss off the gauge's own stage table. `_stage` is -1
## until the first beat; a caller asking before then gets stage 0 for
## whatever figure is standing, which is the honest chapter for a figure
## nobody has watched move yet.
func current_chapter() -> Dictionary:
	var bits: int = _body_bits()
	var s: int = maxi(_stage, 0)
	var stage_name: String = String(_gauge.call("stage_name", s)) if _gauge != null else ""
	var gloss: String = String(_gauge.call("stage_gloss", s)) if _gauge != null else ""
	var hexagram_name: String = KingWen.name(bits)
	return {
		"stage": s,
		"stage_name": stage_name,
		"gloss": gloss,
		"hexagram_no": KingWen.number(bits),
		"hexagram_name": hexagram_name,
		"title": "%s · %s" % [stage_name, hexagram_name],
	}


func _refresh_glyph() -> void:
	if glyph_label == null:
		return
	var bits: int = _body_bits()
	glyph_label.text = "%s  #%d %s" % [KingWen.glyph(bits), KingWen.number(bits), KingWen.name(bits)]


## The sentence currently on the bar, for whoever wants to read it back.
func sentence_text() -> String:
	return _last_sentence


## The same name the third glass answers to, so a caller that only wants the
## top line of whatever glass is mounted does not have to ask which one it is.
func status_text() -> String:
	return _last_sentence


func bubble_text() -> String:
	return bubble.says()


func bubble_visible() -> bool:
	return bubble.visible


# -- the finger --------------------------------------------------------------

## A TAP ON A BLIP PICKS SOMEBODY. The radar's own toggle still runs -- tapping
## the same blip again lets them go -- and the front says who was touched.
func _on_radar_input(event: InputEvent) -> void:
	if radar == null:
		return
	var at: Variant = _release_at(event)
	if at == null:
		return
	var p: Vector2 = at
	if p.distance_to(radar.disc_center()) > radar.field_radius():
		return
	var who: String = String(radar.blip_at(p))
	radar.tap(p)
	radar.accept_event()
	if who != "":
		peer_tapped.emit(who)


## A TAP ON THE CREATURE OPENS THE DIALS. It is the one page the front knows
## how to build, because it is the page the front replaced.
func _on_creature_input(event: InputEvent) -> void:
	if _release_at(event) == null:
		return
	creature_field.accept_event()
	open_dials()


## A TAP ON THE FIGURE ASKS FOR THE READING. The front does not know what a
## reading looks like; it says which figure was touched and stops.
func _on_glyph_input(event: InputEvent) -> void:
	if _release_at(event) == null:
		return
	glyph_band.accept_event()
	reading_tapped.emit(_body_bits())


## A SWIPE UP OFF THE COMPOSER ASKS FOR THE DASHBOARD. Pressed low, released
## eighty pixels higher: a drag, not a tap, so the field and the two buttons
## under the finger keep their own taps.
## A TAP IS SHORTER THAN THIS MUCH TRAVEL, whichever way it went. A finger on
## glass jitters a few pixels even when the person meant to stand perfectly
## still, and the fold's touch emulation can deliver a press and a release with
## no motion event at all between them.
const TAP_PX: float = 16.0

var _drag_from: Vector2 = Vector2.INF
## Which control the finger that is down went down ON. A release that belongs
## to some other control is not the far end of this gesture.
var _drag_on: Control = null

func _on_composer_input(event: InputEvent) -> void:
	_on_swipe_input(event, composer)


## THE FIELD AND THE BUTTONS ARE PART OF THE COMPOSER, as far as a swipe is
## concerned. The `ask` field fills nearly the whole band and STOPs input of
## its own, so a finger that starts on the composer almost never starts on the
## PanelContainer itself -- which is why the gesture was unreachable on a
## phone. Every child is read in ITS OWN coordinates, which is enough: the
## travel is a difference, and both ends are measured in the same rect.
func _on_swipe_input(event: InputEvent, from: Control) -> void:
	if from == null:
		return
	var press: Variant = _press_at(event)
	if press != null:
		_drag_from = press as Vector2
		_drag_on = from
		return
	var at: Variant = _release_at(event)
	if at == null:
		return
	## NO PRESS REMEMBERED, NO SWIPE. A release arriving with nothing behind it
	## -- the press was swallowed elsewhere, or the finger was taken over
	## mid-gesture -- used to subtract from INF, hand back INF of travel and
	## open the gear. THAT is why a plain tap on `ask` opened the dashboard on
	## the phone instead of taking the caret.
	if is_inf(_drag_from.x) or _drag_on != from:
		_drag_from = Vector2.INF
		_drag_on = null
		return
	## Positive y is travel UP the glass, which is the direction that asks.
	var d: Vector2 = _drag_from - (at as Vector2)
	_drag_from = Vector2.INF
	_drag_on = null
	## A TAP IS A TAP, jitter and all: under sixteen pixels the person stood
	## still, the field takes the caret, and the gear is not opened.
	if d.length() < TAP_PX:
		if (from == ask_field or from == composer) and ask_field != null:
			ask_field.grab_focus()
		return
	## AND A SWIPE IS UP, NOT ACROSS. The vertical leg has to beat twice the
	## horizontal one, so a finger dragged sideways along the band never counts.
	if d.y >= swipe_threshold() and absf(d.y) > 2.0 * absf(d.x):
		from.accept_event()
		dashboard_requested.emit()


## Whatever sits inside the composer hears the swipe too.
func _watch_swipe(c: Control) -> void:
	if c != null and not c.gui_input.is_connected(_on_swipe_input.bind(c)):
		c.gui_input.connect(_on_swipe_input.bind(c))


## HOW FAR IS A SWIPE. Eighty pixels, or a quarter of the glass when the glass
## is small enough that eighty would be most of it. DISTANCE ONLY: no fling
## velocity is required, so a slow drag -- the only kind `adb shell input
## swipe` can make -- opens the dashboard exactly as a flick does.
func swipe_threshold() -> float:
	var h: float = root.size.y if root != null else 0.0
	if h <= 8.0:
		return SWIPE_PX
	return minf(SWIPE_PX, h * 0.25)


func _on_send_pressed() -> void:
	composer_send(ask_field.text)


func _on_submitted(text: String) -> void:
	composer_send(text)


## A question, sent the way the send button sends one.
func composer_send(text: String) -> bool:
	var q: String = text.strip_edges()
	if q == "" or _qwen == null:
		return false
	_stream = ""
	_awaiting = true
	_spoke = true
	ask_field.text = ""
	bubble.say("...", _bubble_point())
	_qwen.ask(q)
	return true


# -- the mic -----------------------------------------------------------------

func _on_mic_pressed() -> void:
	if _mic == null:
		return
	if _mic_listening:
		_mic.call("stop")
	else:
		_mic.call("start")


func _on_mic_partial(text: String) -> void:
	ask_field.text = text
	ask_field.caret_column = text.length()


func _on_mic_result(text: String) -> void:
	if text.strip_edges() == "":
		return
	ask_field.text = text
	ask_field.caret_column = text.length()


func _on_mic_error(code: int, message: String) -> void:
	bubble.say("MIC\n%s (%d)" % [message, code], _bubble_point())


func _on_mic_level(rms: float) -> void:
	mic_meter.value = clampf(rms, 0.0, MIC_RMS_FULL)


func _on_mic_state(name_of: String) -> void:
	_mic_listening = name_of == "listening"
	btn_mic.text = MIC_LIVE if _mic_listening else MIC_IDLE
	mic_meter.visible = _mic_listening
	if not _mic_listening:
		mic_meter.value = 0.0


# -- what the store says back ------------------------------------------------

func _on_token(t: String) -> void:
	_stream += t
	if _awaiting:
		bubble.stream(_stream)


func _on_answer_changed(a: String) -> void:
	_stream = ""
	if a.strip_edges() == "":
		return
	if bubble.visible and not bubble.large():
		bubble.stream(a)
	elif _awaiting:
		bubble.say(a, _bubble_point())
	_awaiting = false


## THE JOURNEY IS A PATH, NOT A STATE. Where the figure came from is kept the
## moment it leaves, and the day it landed is the day the stillness starts
## counting from -- which is what a chapter is measured in.
func _on_body_changed(_b: Dictionary) -> void:
	var now_bits: int = _body_bits()
	if now_bits != _cur_body:
		_prev_body = _cur_body
		_cur_body = now_bits
		_still_since_day = _today()
	_refresh_glyph()


func _on_peer_gone(who: String) -> void:
	if radar != null:
		radar.drop_peer(who)
	if dials != null and dials.has_method("_on_peer_gone"):
		dials._on_peer_gone(who)


# -- the pages ---------------------------------------------------------------

## THE DIALS, BUILT ONCE AND SHOWN. The third glass is instantiated the first
## time a finger asks for it, handed the same six objects this front was handed,
## and parked over the front with the composer out of the way. Asking twice
## shows the page that is already there; it never builds a second one.
func open_dials() -> Node:
	close_peer_sheet()
	close_reading_sheet()
	if dials == null:
		dials = DIALS.new()
		dials.name = "Dials"
		add_child(dials)
		if dials.has_method("bind"):
			dials.bind(_store, _qwen, _mnn, _wmn)
		if dials.has_method("set_senses"):
			dials.set_senses(_senses)
		if dials.has_method("set_bus"):
			dials.set_bus(_topic, _gauge)
		if dials.has_method("set_mic"):
			dials.set_mic(_mic)
		if dials.has_method("set_heading"):
			dials.set_heading(_heading)
		if dials.has_method("set_addons"):
			dials.set_addons(_addons)
		if dials.has_method("set_broker"):
			dials.set_broker(_broker)
		if dials.has_method("set_who"):
			dials.set_who(_who)
		## THE DIALS' OWN GEAR OPENS THE SAME RADAR THIS FRONT STANDS, not a
		## second one built underneath the third glass.
		if dials.has_method("set_radar_lender"):
			dials.set_radar_lender(self)
		## ABOVE THE FRONT, whatever layer the page gave itself.
		if dials.get("layer") != null:
			(dials.get("layer") as CanvasLayer).layer = layer.layer + 1
		## THE PAGE MAY LEARN TO CLOSE ITSELF LATER. When it has a `closed`
		## signal the front listens to it; until then the front puts its own
		## back bar over the page, because a page with no way out is a trap.
		## THE EARTH SCRUB, PREVIEWED. The ring says a share of the day; the
		## sentence and the radar borrow it while the finger is down and give
		## it back on release. It never becomes a sample.
		_join(dials, "earth_scrubbed", _on_earth_scrubbed)
		_join(dials, "earth_released", _on_earth_released)
		if dials.has_signal("closed"):
			_join(dials, "closed", close_dials)
		else:
			_build_back_bar()
	if _creature != null and dials.has_method("set_creature"):
		dials.set_creature(_creature)
	_show_page(true)
	return dials


## The dials, if they have ever been opened. Null until a finger asks.
func dials_page() -> Node:
	return dials


## WHETHER THE FRONT PUT THE PAGE UP, which is the front's own book-keeping
## and NOT a reading of the page's CanvasLayer. The page may take its own
## layer down before it says `closed` -- hud3.close() does exactly that -- and
## a front that asked the layer would then decide there was nothing to close
## and leave its room hidden, its composer hidden and its creature parented
## inside the page: a black screen that answers no finger.
var _dials_shown: bool = false


func dials_open() -> bool:
	return dials != null and (_dials_shown or _page_layer_visible())


## Close whatever page is standing. On the front itself this does nothing,
## which is exactly what Android's back button should do on a home screen.
func close_dials() -> bool:
	if not dials_open():
		return false
	_dials_shown = false
	if _creature != null:
		set_creature(_creature)
	_show_page(false)
	## THE PAGE IS TOLD TOO, so a front-driven close leaves no half-held drag
	## behind on the page. Its `closed` comes back here and finds the door
	## already shut, which is not an error.
	## Only when the page is still standing: when it was the PAGE that closed
	## itself, it is already down and saying so twice is a second `closed`.
	if dials != null and dials.has_method("close") and dials.has_method("is_open") 			and bool(dials.is_open()):
		dials.close()
	return true


func _show_page(on: bool) -> void:
	_dials_shown = on
	if dials != null and dials.get("layer") != null:
		(dials.get("layer") as CanvasLayer).visible = on
	if back_layer != null:
		back_layer.visible = on
	if composer != null:
		composer.visible = not on
	## The front's own room keeps drawing behind a page nobody asked to see.
	if layer != null:
		layer.visible = not on


func _page_layer_visible() -> bool:
	if dials == null or dials.get("layer") == null:
		return false
	return (dials.get("layer") as CanvasLayer).visible


## THE FRONT'S OWN WAY OUT, for a page that has none. One bar across the top of
## the page, and a drag DOWN off it closes: the mirror of the swipe that opens
## the dashboard, so the two gestures cannot be confused.
func _build_back_bar() -> void:
	back_layer = CanvasLayer.new()
	back_layer.name = "BackBar"
	back_layer.layer = layer.layer + 2
	add_child(back_layer)

	back_bar = PanelContainer.new()
	back_bar.name = "Bar"
	back_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	back_bar.custom_minimum_size = Vector2(0.0, 44.0)
	back_bar.offset_bottom = 44.0
	back_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	back_bar.add_theme_stylebox_override("panel", SKIN.skin())
	back_bar.gui_input.connect(_on_back_input)
	back_layer.add_child(back_bar)

	var lab := Label.new()
	lab.name = "Hint"
	lab.text = "swipe down to close"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 0.9))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_bar.add_child(lab)
	back_layer.visible = false


var _back_from: float = INF

func _on_back_input(event: InputEvent) -> void:
	var press: Variant = _press_at(event)
	if press != null:
		_back_from = (press as Vector2).y
		return
	var at: Variant = _release_at(event)
	if at == null:
		return
	var travel: float = (at as Vector2).y - _back_from
	_back_from = INF
	if travel >= SWIPE_PX:
		back_bar.accept_event()
		close_dials()


## ANDROID'S OWN BACK BUTTON closes whatever page is open, and does nothing at
## all on the front -- there is nowhere further back to go. A SHEET CLOSES
## FIRST: it sits above the room, under nothing, so a back press unwinds the
## nearest page first and the dials second.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


## THE ONE BACK HANDLER. Android's back button and the desktop's ui_cancel say
## the same thing, and they say it here: shut the top page and stay; on the
## front itself -- where there is nowhere further back to go -- let the app
## leave. `application/config/quit_on_go_back` is off in project.godot so the
## engine no longer quits out from under a sheet before this ever runs.
func _go_back() -> void:
	if back_requested():
		return
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if back_requested():
			get_viewport().set_input_as_handled()


## The back request, as a test can raise it without a phone. The dashboard
## closes first -- it stands above everything else -- then whichever sheet is
## open, then the dials; failing all three, nothing.
func back_requested() -> bool:
	if close_dashboard():
		return true
	if close_peer_sheet():
		return true
	if close_reading_sheet():
		return true
	return close_dials()


# -- the gear's panel ----------------------------------------------------------

## THE DASHBOARD, OPENED. Built the first time: the dials page's own copy is
## reused when there is one (opening the gear from the dials page and from the
## composer's own swipe must land on the one dashboard, not two), and one the
## front owns outright otherwise. Either way the one radar this front stands
## is lent to it before it is shown, so panel 6·FLY draws the SAME creature
## the room does -- never a second one built underneath it.
func open_dashboard() -> Node:
	close_peer_sheet()
	close_reading_sheet()
	if dashboard == null:
		if dials != null and dials.has_method("dashboard_page"):
			dashboard = dials.dashboard_page()
		else:
			dashboard = DASHBOARD.new()
			dashboard.name = "Dashboard"
			root.add_child(dashboard)
			if dashboard.has_method("set_host"):
				dashboard.set_host(self)
			if dashboard.has_method("bind"):
				dashboard.bind(_store, _mnn, _wmn, _senses, null, _qwen)
			if dashboard.has_method("set_bus"):
				dashboard.set_bus(_topic, _gauge)
			if dashboard.has_method("set_addons"):
				dashboard.set_addons(_addons)
			if dashboard.has_method("set_broker"):
				dashboard.set_broker(_broker)
			if dashboard.has_method("set_heading"):
				dashboard.set_heading(_heading)
	if dashboard != null and radar != null and dashboard.has_method("borrow_radar"):
		dashboard.borrow_radar(radar)
	if dashboard != null and dashboard.has_method("open"):
		dashboard.open()
	if composer != null:
		composer.visible = false
	return dashboard


func dashboard_open() -> bool:
	return dashboard != null and dashboard.has_method("is_open") and bool(dashboard.is_open())


## THE DASHBOARD, CLOSED. The radar is reclaimed into the front's own room the
## moment it shuts, so the disc is never left parked in a hidden panel's slot.
func close_dashboard() -> bool:
	if not dashboard_open():
		return false
	dashboard.close()
	reclaim_radar()
	if composer != null and not peer_sheet_open() and not reading_sheet_open() and not dials_open():
		composer.visible = true
	return true


## THE RADAR COMES HOME. Called once whoever borrowed it has handed it back:
## the front's own layout -- size, quiet, the STOP filter and its own tap --
## is re-applied so the creature stands where the room wants it and answers a
## finger the way the room always has, not however the panel left it.
func reclaim_radar() -> void:
	if radar == null:
		return
	## THE BORROWER'S MINIMUM GOES BACK TOO. Panel 6 pins 210 x 190 on it so it
	## can share a row with the bars; the room wants the whole band and no floor
	## at all, and a 190-tall minimum left behind is a band that will not shrink.
	radar.custom_minimum_size = Vector2.ZERO
	## AND THE BORROWER'S RECT GOES BACK TOO. Panel 6's row is a Container: it
	## writes anchors 0 and a 210 x 210 rect onto the node, and the room band
	## lays nobody out, so without this the disc came home the size of a
	## dashboard tile and drew its 771 px room outside it -- the split front,
	## where a blip is painted where no `gui_input` can ever fire.
	radar.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	radar.position = Vector2.ZERO
	if room_band != null:
		radar.size = room_band.size
	radar.mouse_filter = Control.MOUSE_FILTER_STOP
	if not radar.gui_input.is_connected(_on_radar_input):
		radar.gui_input.connect(_on_radar_input)
	if radar.has_method("set_quiet"):
		radar.set_quiet(true)
	_layout_room()


# -- the two sheets ------------------------------------------------------------

## A PEER, LAZILY BUILT AND SHOWN. Reading a peer's row out of `wmn.peers()`
## and their plot out of `radar.peer_plots()` is this file's job because it is
## the file that was handed both objects; the sheet itself reads neither.
func _open_peer_sheet(who: String) -> void:
	close_reading_sheet()
	close_dials()
	if peer_sheet == null:
		peer_sheet = PEER_SHEET.new()
		peer_sheet.name = "PeerSheet"
		_peer_sheet_layer = CanvasLayer.new()
		_peer_sheet_layer.name = "PeerSheetLayer"
		_peer_sheet_layer.layer = layer.layer + 1
		add_child(_peer_sheet_layer)
		_peer_sheet_layer.add_child(peer_sheet)
		peer_sheet.guide_requested.connect(_on_guide_requested)
		peer_sheet.guide_cleared.connect(_on_guide_cleared)
		peer_sheet.closed.connect(close_peer_sheet)
		peer_sheet.set_gauge(_gauge)
	var row: Dictionary = _peer_row(who)
	## THE SHEET MUST KNOW WHO IT IS ABOUT. The row comes out of `wmn.peers()`
	## and the blip comes out of the radar, and the two do not always agree: a
	## peer the radar has plotted but the fabric has not listed yet gave an
	## EMPTY row, so the sheet's `_who` was "" and the guide tap asked the front
	## for guidance to nobody -- which is why the rim arrow never appeared. The
	## id under the finger is the one fact this is certain of; it is written in.
	if String(row.get("who", "")) == "":
		row = row.duplicate()
		row["who"] = who
	var plot: Dictionary = _peer_plot(who)
	peer_sheet.show_peer(row, plot)
	_peer_sheet_layer.visible = true
	peer_sheet.visible = true
	if composer != null:
		composer.visible = false


func peer_sheet_open() -> bool:
	return peer_sheet != null and _peer_sheet_layer != null and _peer_sheet_layer.visible


func close_peer_sheet() -> bool:
	if not peer_sheet_open():
		return false
	_peer_sheet_layer.visible = false
	## THE SHEET ITSELF IS TAKEN DOWN AS WELL, not just the layer it rides on:
	## a full-rect STOP that is only "invisible" is still a wall a finger runs
	## into, and this sheet is the one that was swallowing the front's swipe.
	peer_sheet.visible = false
	if composer != null and not reading_sheet_open() and not dials_open():
		composer.visible = true
	return true


func _peer_row(who: String) -> Dictionary:
	for row in _peer_rows():
		if String((row as Dictionary).get("who", "")) == who:
			return row as Dictionary
	return {}


func _peer_plot(who: String) -> Dictionary:
	if radar != null and radar.has_method("peer_plots"):
		var plots: Dictionary = radar.peer_plots()
		if plots.has(who):
			return plots[who] as Dictionary
	return {}


func _on_guide_requested(who: String) -> void:
	if radar != null:
		radar.guide_id = who


func _on_guide_cleared() -> void:
	if radar != null:
		radar.guide_id = ""


## A READING, LAZILY BUILT AND SHOWN. The chapter is the front's own tracked
## walk -- `current_chapter()`, every caption in it off the gauge -- because
## the sheet does not know what a stage or a body's path is; it only draws
## what it is handed.
func _open_reading_sheet(bits: int) -> void:
	close_peer_sheet()
	close_dials()
	if reading_sheet == null:
		reading_sheet = READING_SHEET.new()
		reading_sheet.name = "ReadingSheet"
		_reading_sheet_layer = CanvasLayer.new()
		_reading_sheet_layer.name = "ReadingSheetLayer"
		_reading_sheet_layer.layer = layer.layer + 1
		add_child(_reading_sheet_layer)
		_reading_sheet_layer.add_child(reading_sheet)
		reading_sheet.closed.connect(close_reading_sheet)
		reading_sheet.set_gauge(_gauge)
	reading_sheet.show_reading(bits, current_chapter())
	_reading_sheet_layer.visible = true
	if composer != null:
		composer.visible = false


func reading_sheet_open() -> bool:
	return reading_sheet != null and _reading_sheet_layer != null and _reading_sheet_layer.visible


func close_reading_sheet() -> bool:
	if not reading_sheet_open():
		return false
	_reading_sheet_layer.visible = false
	if composer != null and not peer_sheet_open() and not dials_open():
		composer.visible = true
	return true


# -- layout ------------------------------------------------------------------

func _process(_delta: float) -> void:
	_layout_room()


## THE RADAR TAKES THE BAND AND THE CREATURE TAKES THE HUB. The disc is sized
## off the band's own short side, and the square the creature is tapped in is
## the radar's `hub_rect()` moved into the band -- so the two can never drift
## apart, whatever the radar decides its floor plan is.
func _layout_room() -> void:
	if room_band == null or radar == null or creature_field == null:
		return
	## THE ROOM LAYS OUT THE RADAR ONLY WHILE THE RADAR IS IN THE ROOM.
	## `_process` runs this every single frame, and the dashboard BORROWS this
	## same instance into panel 6's row -- where the panel has sized it 88 px
	## and given it a 210-wide minimum. Left unguarded, the next frame read the
	## FRONT's band (the whole tall glass), wrote `radar_radius = 790` onto a
	## node living inside a ScrollContainer column, and the column's minimum
	## size exploded: no panels, no composer, and a creature framed off a hub
	## rect measured in the wrong coordinate space -- the fold's broken gear.
	## Whoever borrowed it owns its floor plan until `reclaim_radar` takes it
	## back.
	if radar.get_parent() != room_band:
		return
	var band: Vector2 = room_band.size
	if band.x < 8.0 or band.y < 8.0:
		return
	## THE RADAR TAKES THE WHOLE BAND, RE-STATED EVERY FRAME. The band is a
	## plain Control and never lays its children out, so the rect the radar
	## carries is whatever the LAST parent left on it -- and panel 6's row is a
	## Container, which pins anchors to 0 and writes a 210 x 210 rect straight
	## onto the node. Handed back, the radar kept that 210 px rect while
	## `radar_radius` went back to the band's own 771: a disc drawn far outside
	## its own rect (the "split" room), blips no finger could reach because
	## `gui_input` only fires inside the rect, and a hub square parked off to
	## one side. Anchors and offsets are re-applied here, not just in
	## `reclaim_radar`, so no borrower can leave the room bent.
	if radar.anchor_right != 1.0 or radar.anchor_bottom != 1.0 \
			or not radar.position.is_equal_approx(Vector2.ZERO) \
			or not radar.size.is_equal_approx(band):
		radar.set_anchors_preset(Control.PRESET_FULL_RECT, false)
		radar.position = Vector2.ZERO
		radar.size = band
	var want_r: float = minf(band.x * 0.44, band.y * 0.40)
	if absf(float(radar.radar_radius) - want_r) > 0.5:
		radar.radar_radius = want_r
		radar.ring_thickness = maxf(10.0, want_r * 0.16)
	var hub: Rect2 = radar.hub_rect() if radar.has_method("hub_rect") else Rect2()
	if hub.size.x < 4.0:
		var fr: float = radar.field_radius()
		var c: Vector2 = radar.disc_center()
		hub = Rect2(c - Vector2(fr, fr) * 0.34, Vector2(fr, fr) * 0.68)
	## THE HUB RECT IS THE RADAR'S OWN COORDINATES; the square is a SIBLING
	## of the radar, so the radar's seat in the band is added back in.
	creature_field.position = radar.position + hub.position
	creature_field.size = hub.size
	_frame_creature()


## WHERE THE EYE STANDS. The solid has to come out the width of the hub square
## and land on the middle of it, and the stage is the whole glass -- so the
## distance is solved from the eye's own field of view and the offset from how
## far the hub's middle is from the glass's.
func _frame_creature() -> void:
	if dials_open():
		return
	if _creature == null or _creature.camera == null or root == null or _creature.get_parent() != view:
		return
	var box: Vector2 = root.size
	var want_px: float = creature_field.size.x * CREATURE_FILL
	if want_px < 1.0 or box.y < 8.0:
		return
	var cam: Camera3D = _creature.camera
	var half: float = tan(deg_to_rad(cam.fov) * 0.5)
	var z: float = SOLID_DIAMETER * box.y / (2.0 * half * want_px)
	var mid: Vector2 = creature_field.global_position - root.global_position + creature_field.size * 0.5
	var world_per_px: float = 2.0 * half * z / box.y
	## THE EYE MOVES THE OTHER WAY ALONG X. Sliding the camera right puts the
	## solid further LEFT on the glass, so the offset is negated; Y already
	## reads that way because screen-down is world-up. While the hub sat dead
	## centre the sign could not be seen -- it showed the instant the room bent
	## and put the creature on the mirrored side of the disc.
	cam.position = Vector3(
		(box.x * 0.5 - mid.x) * world_per_px,
		(mid.y - box.y * 0.5) * world_per_px,
		z)


## Where a bubble the composer raised should stand.
func _bubble_point() -> Vector2:
	if composer == null or root == null:
		return Vector2.ZERO
	var r: Rect2 = composer.get_global_rect()
	return r.position + r.size * 0.5 - root.global_position


# -- the small arithmetic ----------------------------------------------------

func _body_bits() -> int:
	if _store == null:
		return 0
	if _store.has_method("body_bits"):
		return int(_store.body_bits()) & 63
	if _store.has_method("primary"):
		return int(_store.primary()) & 63
	return 0


func _today() -> int:
	return int(Time.get_unix_time_from_system()) / DAY_S


func _wall_hour() -> float:
	var d: Dictionary = Time.get_datetime_dict_from_system()
	return float(int(d.get("hour", 0))) + float(int(d.get("minute", 0))) / 60.0


## HOW MUCH THIS PHONE IS MOVING, 0..1, out of whatever the senses expose. A
## front with no senses bound reports stillness rather than guessing.
func _motion() -> float:
	if _senses == null:
		return 0.0
	if _senses.has_method("excitation"):
		return clampf(float(_senses.excitation()), 0.0, 1.0)
	if _senses.has_method("stillness"):
		return clampf(1.0 - float(_senses.stillness()), 0.0, 1.0)
	return 0.0


func _screen_on() -> bool:
	if _senses != null and _senses.has_method("screen_on"):
		return bool(_senses.screen_on())
	return true


## The release a finger leaves behind, as a point, or null. Mouse and touch
## both, because a test has a mouse and a phone does not.
static func _release_at(event: InputEvent) -> Variant:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			return mb.position
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if not st.pressed:
			return st.position
	return null


## Where a finger went down, or null.
static func _press_at(event: InputEvent) -> Variant:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			return mb.position
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			return st.position
	return null


## One connection, made once, whoever is missing.
static func _join(who_node: Object, what: String, to: Callable) -> void:
	if who_node == null or not who_node.has_signal(what):
		return
	if not who_node.is_connected(what, to):
		who_node.connect(what, to)

