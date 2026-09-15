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

## THE SENTENCE, LOADED RATHER THAN NAMED, exactly as the app loads the
## alchemy: it belongs to the core and the core may land after the glass does.
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

## A day, in milliseconds and in seconds, for counting the journey's own days.
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

var _store: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
var _alchemy: Node = null
var _qwen: Node = null
var _heading: Node = null
var _mic: Node = null
var _creature: Node = null
var _addons: Node = null

var _who: String = "hexy"
var _stream: String = ""
var _awaiting: bool = false
var _mic_listening: bool = false

## The clock that learns when this person's day actually is. Fed one sample a
## beat out of whatever is available with no device attached: the wall hour,
## the senses' own excitation, the screen, and whether a question was asked.
var _entrain: Entrain = null
## Whether a question left the composer since the last beat.
var _spoke: bool = false

## The journey, tracked from the store's body changes: where the figure came
## from, and how many days it has been sitting where it is.
var _prev_body: int = -1
var _cur_body: int = -1
var _still_since_day: int = -1
var _stage: int = -1
var _phase: float = -1.0

var _sentence_script: Script = null
var _beat_timer: Timer = null
var _last_sentence: String = ""


# -- building ----------------------------------------------------------------

func _ready() -> void:
	if ResourceLoader.exists(SENTENCE_PATH):
		_sentence_script = load(SENTENCE_PATH) as Script
	_entrain = Entrain.new()

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
func bind(store: Node, mnn: Node, wmn: Node, senses: Node, alchemy: Node, qwen: Node) -> void:
	_store = store
	_mnn = mnn
	_wmn = wmn
	_senses = senses
	_alchemy = alchemy
	_qwen = qwen
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


func set_alchemy(alchemy: Node) -> void:
	_alchemy = alchemy


func alchemy() -> Node:
	return _alchemy


func set_addons(addons: Node) -> void:
	_addons = addons
	if dials != null and dials.has_method("set_addons"):
		dials.set_addons(addons)


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
	_spoke = false


## EVERYTHING THE ROOM KNOWS, PUSHED. The radar reaches for nothing: the fly
## state, the headings, the proximity classes, the bearings, the phases, the
## chapters and the compass all arrive here or not at all.
func _feed_radar() -> void:
	if radar == null:
		return
	if _store != null and _store.has_method("get_character"):
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
## One [Entrain] sample a beat out of what a phone with nothing attached can
## still honestly say: the wall hour, the senses' excitation as motion, the
## screen, and whether a question was asked. Light is -1 -- unknown -- because
## the front has no lux and a zero would read as pitch dark. The internal hour
## that falls out becomes the phase every other phone in the room compares
## itself against, and the chapter comes from the journey's own rule.
func _feed_clock() -> void:
	var day: int = _today()
	var wall: float = _wall_hour()
	_entrain.sample(day, wall, -1.0, _motion(), _screen_on(), _spoke)
	_entrain.trim(day, 7)
	_phase = fposmod(_entrain.internal_hour(wall), 24.0) / 24.0
	var days_still: int = maxi(0, day - _still_since_day)
	var now_bits: int = _body_bits()
	if _cur_body < 0:
		_cur_body = now_bits
		_prev_body = now_bits
	_stage = Journey.stage_of(_prev_body, now_bits, days_still)
	if _wmn != null and _wmn.has_method("set_own_phase"):
		_wmn.set_own_phase(_phase, _stage)
	if radar != null and radar.has_method("set_own_phase"):
		radar.set_own_phase(_phase, _stage)


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
		var out: Variant = _sentence_script.call("of", bits, _cast_dict(), _peer_rows(),
			_day_dict(), _marks(), Journey.chapter(bits, maxi(_stage, 0)))
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
		"internal_hour": _entrain.internal_hour(_wall_hour()),
		"phase": _phase,
		"stage": _stage,
		"confidence": _entrain.confidence,
		"days_still": maxi(0, _today() - _still_since_day),
	}


## The six standing marks, when there is an alchemy to ask.
func _marks() -> Array:
	if _alchemy != null and _alchemy.has_method("marks"):
		return _alchemy.marks() as Array
	return []


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
var _drag_from: float = INF

func _on_composer_input(event: InputEvent) -> void:
	var press: Variant = _press_at(event)
	if press != null:
		_drag_from = (press as Vector2).y
		return
	var at: Variant = _release_at(event)
	if at == null:
		return
	var travel: float = _drag_from - (at as Vector2).y
	_drag_from = INF
	if travel >= SWIPE_PX:
		composer.accept_event()
		dashboard_requested.emit()


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
	if dials == null:
		dials = DIALS.new()
		dials.name = "Dials"
		add_child(dials)
		if dials.has_method("bind"):
			dials.bind(_store, _qwen, _mnn, _wmn)
		if dials.has_method("set_senses"):
			dials.set_senses(_senses)
		if dials.has_method("set_alchemy"):
			dials.set_alchemy(_alchemy)
		if dials.has_method("set_mic"):
			dials.set_mic(_mic)
		if dials.has_method("set_heading"):
			dials.set_heading(_heading)
		if dials.has_method("set_addons"):
			dials.set_addons(_addons)
		if dials.has_method("set_who"):
			dials.set_who(_who)
		## ABOVE THE FRONT, whatever layer the page gave itself.
		if dials.get("layer") != null:
			(dials.get("layer") as CanvasLayer).layer = layer.layer + 1
		## THE PAGE MAY LEARN TO CLOSE ITSELF LATER. When it has a `closed`
		## signal the front listens to it; until then the front puts its own
		## back bar over the page, because a page with no way out is a trap.
		if dials.has_signal("closed"):
			_join(dials, "closed", close_dials)
		else:
			_build_back_bar()
	_show_page(true)
	return dials


## The dials, if they have ever been opened. Null until a finger asks.
func dials_page() -> Node:
	return dials


func dials_open() -> bool:
	return dials != null and _page_layer_visible()


## Close whatever page is standing. On the front itself this does nothing,
## which is exactly what Android's back button should do on a home screen.
func close_dials() -> bool:
	if not dials_open():
		return false
	_show_page(false)
	return true


func _show_page(on: bool) -> void:
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
## all on the front -- there is nowhere further back to go.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		close_dials()


## The back request, as a test can raise it without a phone.
func back_requested() -> bool:
	return close_dials()


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
	var band: Vector2 = room_band.size
	if band.x < 8.0 or band.y < 8.0:
		return
	var want_r: float = minf(band.x * 0.44, band.y * 0.40)
	if absf(float(radar.radar_radius) - want_r) > 0.5:
		radar.radar_radius = want_r
		radar.ring_thickness = maxf(10.0, want_r * 0.16)
	var hub: Rect2 = radar.hub_rect() if radar.has_method("hub_rect") else Rect2()
	if hub.size.x < 4.0:
		var fr: float = radar.field_radius()
		var c: Vector2 = radar.disc_center()
		hub = Rect2(c - Vector2(fr, fr) * 0.34, Vector2(fr, fr) * 0.68)
	creature_field.position = hub.position
	creature_field.size = hub.size
	_frame_creature()


## WHERE THE EYE STANDS. The solid has to come out the width of the hub square
## and land on the middle of it, and the stage is the whole glass -- so the
## distance is solved from the eye's own field of view and the offset from how
## far the hub's middle is from the glass's.
func _frame_creature() -> void:
	if _creature == null or _creature.camera == null or root == null:
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
	cam.position = Vector3(
		(mid.x - box.x * 0.5) * world_per_px,
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
