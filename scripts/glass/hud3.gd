class_name Hud3
extends Node

## THE THIRD GLASS: FIVE BANDS, THREE DIALS, ONE VOICE.
##
## The surface before this one was a stack of panels that each wanted the whole
## width, and the two dials -- the only things on the screen a person actually
## reads -- were squeezed between them. This one inverts that. Top to bottom:
## one STATUS LINE, the HEAD dial small, the BODY dial big with the creature
## standing inside it, the EARTH dial small, and the composer. Everything else
## the app has to say arrives in a floating BUBBLE next to whatever said it,
## and leaves again after six seconds.
##
## THE BANDS ARE ANCHORED, NOT MEASURED. The five live in a box that fills the
## glass, three of them with a fixed small height and the body free to take
## what is left. That is why nothing overlaps at 1080x2408 and nothing overlaps
## at 1812x2176: no band is ever told a pixel size, only its share.
##
## THE THREE DIALS SPEAK THE SAME LANGUAGE. Same rim, same sixty-four ticks,
## same diamonds, same colours: cyan is the machine, gold is the human, orange
## is the Huohoutu, green is enhanced. The head walks the oracle, the body
## follows the senses, and the earth is the app's own eight controls -- so the
## chrome that used to be a row of buttons is now the third member of a family.
##
## TAP ONLY. Every act on this surface is one visible target touched once.

## The one skin, borrowed from the bubble so there is only one of it.
const SKIN := preload("res://scripts/glass/bubble.gd")

## Where Pacing's thresholds live, when the core has landed. The glass only
## needs them to choose a WORD, so it reads them if they are there and falls
## back to the same numbers if they are not.
const PACING_PATH: String = "res://scripts/core/iching/pacing.gd"

## The ground the whole surface stands on: the Environment colour of
## scenes/main.tscn, painted across the glass so that the creature's stage --
## which cannot be transparent and still bloom -- has no visible edge.
const GROUND: Color = Color(0.0588235, 0.0823529, 0.12549, 1.0)

## The fixed bands, in pixels of the band's own height. The body takes the rest.
const STATUS_H: float = 54.0
const HEAD_H: float = 300.0
const EARTH_H: float = 300.0
const COMPOSER_H: float = 54.0
const BAND_GAP: int = 8

## THE STAGE IS THE WHOLE GLASS, which is how the owner's own scene did it.
##
## A square stage inside the body band left a SEAM: a 3D viewport cleared to a
## colour does not land on the same bytes as a ColorRect painted the same
## colour -- measured, 13,22,34 against 15,21,32 -- and two shades meeting in a
## straight line down the middle of the owner's ring reads as a bug, because it
## is one. Making the square transparent closes the seam and takes the bloom
## with it: the halo around a lit strut falls 87,70,60,54 across the first
## eight pixels transparent against 112,107,100,97 opaque, where the owner's
## old scene reads 150,135,125,118. So the stage is opaque and it is EVERY
## pixel, exactly as scenes/main.tscn had it -- there is no edge to see because
## there is no edge.
##
## What that costs is framing, and framing is arithmetic. The creature's eye
## sizes the solid against the viewport's HEIGHT, so a stage the height of the
## glass would draw a solid far too big for the ring; the stage works out how
## far back to stand, and how far to look down, so the solid lands in the
## middle of the body band at the share of the ring named below.

## How much of the ring's inner circle the solid fills.
const CREATURE_FILL: float = 0.9

## The ring's inner circle as a share of the body band's short side: the body
## dial draws its rim at 0.46 of that side and its inner framing arc at 0.62 of
## the rim, and this is the diameter those two numbers make.
const INNER_CIRCLE: float = 0.5704

## The solid's own diameter in metres, which is the scale the creature builds
## itself at. Everything else about the framing follows from it and the eye's
## own field of view.
const SOLID_DIAMETER: float = 0.88

## How much of the body band answers a tap as the creature. Small, and inside
## the ring's inner circle, so the eight diamonds keep their own taps.
const FIELD_FRACTION: float = 0.5

## The stage's container stretches, which means the container owns the
## viewport's size and keeps it equal to the glass. Nothing here sets it.

## How long a flip stays the newest thing the status line has to say.
const FLIP_FRESH_MS: int = 6000

## The owner's own two marks for the two figures, kept byte for byte.
const MOON: String = "🌙"
const SUN: String = "☀️"

## The sense periods the earth ring walks through, in milliseconds. 3500 is the
## senses' own default and is the seat the ring starts on.
const PERIODS_MS: Array[int] = [3500, 1000, 2000, 8000]

## The two Pacing numbers, for when Pacing is not on disk to say them.
const CIVIL_FIRE_THRESHOLD: float = 2.5

## THE MIC'S THREE WORDS. The button says one of two things and the strip says
## the third, and none of them is ever a spinner: a person looking at the glass
## can tell whether the phone is listening without tapping anything.
const MIC_IDLE: String = "MIC"
const MIC_LIVE: String = "LISTENING"
const MIC_PHRASE: String = "MIC: listening"
## The loudest the meter draws, in the dB scale onRmsChanged speaks.
const MIC_RMS_FULL: float = 10.0
const MARTIAL_THRESHOLD: float = 0.85

var layer: CanvasLayer = null
var root: Control = null
var ground: ColorRect = null
var bands: VBoxContainer = null

var status_panel: PanelContainer = null
var status_label: Label = null

var head: MandalaDialTap = null
var body_band: Control = null
var body: BodyDialTap = null
var earth: EarthDial2D = null

var stage: SubViewportContainer = null
var view: SubViewport = null
var creature_field: Control = null

var composer: PanelContainer = null
var ask_field: LineEdit = null
var btn_mic: Button = null
var mic_meter: ProgressBar = null
var btn_send: Button = null

var bubble: GlassBubble = null

var _store: Node = null
var _qwen: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
var _creature: Node = null
var _alchemy: Node = null
var _mic: Node = null
var _mic_listening: bool = false

var _who: String = "hexy"
var _stream: String = ""
var _enhanced: bool = true
## Whether this glass asked the question whose answer is coming. An answer the
## model produced on its own is written to the store all the same, but it does
## not throw a panel over the head dial at boot: the bubble is a REPLY.
var _awaiting: bool = false
var _pacing: Script = null


# -- building ----------------------------------------------------------------

func _ready() -> void:
	_pacing = (load(PACING_PATH) as Script) if ResourceLoader.exists(PACING_PATH) else null

	layer = CanvasLayer.new()
	layer.name = "Glass3"
	layer.layer = 1
	add_child(layer)

	root = Control.new()
	root.name = "Glass"
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

	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	root.add_child(pad)

	bands = VBoxContainer.new()
	bands.name = "Bands"
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override("separation", BAND_GAP)
	pad.add_child(bands)

	_build_status()
	_build_head()
	_build_body()
	_build_earth()
	_build_composer()

	bubble = GlassBubble.new()
	root.add_child(bubble)

	set_process(true)


## 1. THE STATUS STRIP: one line that keeps a person informed, newest first,
## with a configure button on the top-right.
func _build_status() -> void:
	status_panel = PanelContainer.new()
	status_panel.name = "Status"
	status_panel.custom_minimum_size = Vector2(0.0, STATUS_H)
	status_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override("panel", SKIN.skin())
	bands.add_child(status_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	status_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.name = "HBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(hbox)

	status_label = Label.new()
	status_label.name = "Line"
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.68, 0.82, 0.92, 1.0))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(status_label)
	status_label.text = "waking"

	var btn_config := Button.new()
	btn_config.name = "ConfigBtn"
	btn_config.text = "⚙"
	btn_config.flat = true
	btn_config.add_theme_font_size_override("font_size", 16)
	btn_config.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.9))
	btn_config.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_config.pressed.connect(_on_configure_pressed)
	hbox.add_child(btn_config)


## 2. THE HEAD DIAL, SMALL: the oracle, walked by a finger on its own ticks.
func _build_head() -> void:
	head = MandalaDialTap.new()
	head.name = "HeadDial"
	head.custom_minimum_size = Vector2(0.0, HEAD_H)
	head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bands.add_child(head)
	head.ring_slot_tapped.connect(_on_head_ring_tapped)
	head.human_station_clicked.connect(_on_human_dot_tapped)
	head.center_hub_clicked.connect(_on_head_hub_tapped)


## 3. THE BODY DIAL, BIG, DRAWN AROUND THE CREATURE. The ring is the whole
## band; the solid stands in a square in the middle of it; and the square is
## the only place a tap reaches the creature, so no point has two owners.
func _build_body() -> void:
	body_band = Control.new()
	body_band.name = "BodyBand"
	body_band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_band.resized.connect(_layout_stage)
	bands.add_child(body_band)

	body = BodyDialTap.new()
	body.name = "BodyDial"
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body_band.add_child(body)
	body.machine_station_clicked.connect(_on_machine_diamond_tapped)
	body.center_clicked.connect(_on_body_center_tapped)
	body.dial_dragged.connect(_on_body_dial_dragged)

	creature_field = Control.new()
	creature_field.name = "CreatureField"
	creature_field.set_anchors_preset(Control.PRESET_TOP_LEFT)
	creature_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creature_field.gui_input.connect(_on_creature_input)
	body_band.add_child(creature_field)
	_layout_stage.call_deferred()


## THE STAGE, UNDER EVERY OTHER PIXEL. Opaque, the full size of the glass, and
## first in the tree, so the five bands and the three rings all draw over it
## and the colour it clears to IS the colour of the app.
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
	root.resized.connect(_layout_stage)


## The 3D setup of scenes/main.tscn, carried in whole: one environment with the
## same glow, one key light, one blue fill. The creature brings its own camera.
func _light_the_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0588235, 0.0823529, 0.12549, 1.0)
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


## 4. THE EARTH DIAL, SMALL: the app's own eight controls, and the room.
func _build_earth() -> void:
	earth = EarthDial2D.new()
	earth.name = "EarthDial"
	earth.custom_minimum_size = Vector2(0.0, EARTH_H)
	earth.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bands.add_child(earth)
	earth.station_tapped.connect(_on_earth_station_tapped)
	earth.hub_tapped.connect(_on_earth_hub_tapped)
	earth.ring_slot_tapped.connect(_on_earth_ring_tapped)


## 5. THE COMPOSER: ask, a mic that is honest about being a stub, and send.
func _build_composer() -> void:
	composer = PanelContainer.new()
	composer.name = "Composer"
	composer.custom_minimum_size = Vector2(0.0, COMPOSER_H)
	composer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	composer.add_theme_stylebox_override("panel", SKIN.skin())
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
	ask_field.add_theme_font_size_override("font_size", 14)
	ask_field.text_submitted.connect(_on_submitted)
	row.add_child(ask_field)

	btn_mic = Button.new()
	btn_mic.name = "Mic"
	btn_mic.text = MIC_IDLE
	btn_mic.disabled = true
	btn_mic.add_theme_font_size_override("font_size", 13)
	btn_mic.pressed.connect(_on_mic_pressed)
	row.add_child(btn_mic)

	## The loudness the recogniser reports, and nothing else. It stands beside
	## the button rather than inside it, so the word on the button never moves.
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
	btn_send.add_theme_font_size_override("font_size", 13)
	btn_send.pressed.connect(_on_send_pressed)
	row.add_child(btn_send)


# -- wiring ------------------------------------------------------------------

## The same bind surface the bridge had, so the app barely changes.
func bind(store: Node, qwen: Node, mnn: Node, wmn: Node) -> void:
	_store = store
	_qwen = qwen
	_mnn = mnn
	_wmn = wmn
	if _store != null:
		_join(_store, "head_changed", _on_head_changed)
		_join(_store, "body_changed", _on_body_changed)
		_join(_store, "earth_changed", _on_earth_changed)
		_join(_store, "flipped", _on_flipped)
		_join(_store, "hexagram_changed", _on_body_changed)
		_join(_store, "machine_changed", _on_family_changed)
		_join(_store, "human_changed", _on_family_changed)
		_join(_store, "room_changed", _on_room_changed)
		_join(_store, "answer_changed", _on_answer_changed)
	_join(_mnn, "token", _on_token)
	_refresh_dials()


func set_senses(senses: Node) -> void:
	_senses = senses
	_refresh_dials()


## The creature is re-parented into the stage, exactly as the bridge did it.
func set_creature(creature: Node) -> void:
	_creature = creature
	if creature == null:
		return
	if creature.get_parent() != null:
		creature.get_parent().remove_child(creature)
	view.add_child(creature)
	_join(creature, "throw_requested", _on_throw_requested)
	_layout_stage()


func set_who(who_name: String) -> void:
	_who = who_name


func who() -> String:
	return _who


## THE MIC. The button is grey until the core says there is a recogniser --
## the phone's own, or the desktop mock -- and from then on a tap starts it and
## a second tap stops it. What comes back is WRITTEN INTO THE COMPOSER AND LEFT
## THERE: the person still taps SEND. Nothing here sends by itself.
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


## The alchemy is held only so the glass can say what it last did.
func set_alchemy(alchemy: Node) -> void:
	_alchemy = alchemy


func alchemy() -> Node:
	return _alchemy


# -- what the glass is asked for ---------------------------------------------

func status_text() -> String:
	return status_label.text


func status_strip() -> Control:
	return status_panel


func bubble_text() -> String:
	return bubble.says()


func bubble_visible() -> bool:
	return bubble.visible


func head_dial() -> Node:
	return head


func body_dial() -> Node:
	return body


func earth_dial() -> Node:
	return earth


func head_rect() -> Rect2:
	return head.get_global_rect()


func body_rect() -> Rect2:
	return body.get_global_rect()


func earth_rect() -> Rect2:
	return earth.get_global_rect()


## A question, sent the way the send button sends one.
func composer_send(text: String) -> bool:
	var q: String = text.strip_edges()
	if q == "" or _qwen == null:
		return false
	_stream = ""
	_awaiting = true
	ask_field.text = ""
	bubble.say("...", _hub_point(head))
	_qwen.ask(q)
	return true


# -- the finger --------------------------------------------------------------

## A tick on the head ring, touched: the HEAD walks to that slot and stays.
func _on_head_ring_tapped(slot: int) -> void:
	_walk_head(slot, "tap")


func _on_human_dot_tapped(trigram: int) -> void:
	bubble.say(_sentence_of(1, trigram), _point_in_root(head, head.trigram_position(trigram)))


func _on_head_hub_tapped() -> void:
	var at: Vector2 = _hub_point(head)
	bubble.say("🌙 HEAD (MIND & INTENT)\nThought Prior: Qwen 0.5B Active\nFocus: Human Consciousness\n[Inquiring Thought Engine...]", at)
	if _qwen != null:
		_stream = ""
		_awaiting = true
		_qwen.ask(Qwen.THOUGHT_QUESTION)


func _on_machine_diamond_tapped(trigram: int) -> void:
	var at: Vector2 = _point_in_root(body, body.station_position(trigram))
	var s_text: String = _sentence_of(0, trigram)
	var tri_name: String = KingWen.trigram_name(trigram)
	bubble.say("☀️ SENSOR: %s\n%s" % [tri_name, s_text], at)
	if _creature != null and _creature.has_method("tap"):
		_creature.tap(_to_stage(at))


## The twelve earth stations, in the order they are drawn.
func _on_earth_station_tapped(index: int) -> void:
	var at: Vector2 = _point_in_root(earth, earth.station_position(index))
	match index:
		0:
			_cast_earth()
			bubble.say("CAST ALTAR: %s" % _figure_word(_earth_bits()), at)
		1:
			_walk_earth(earth.earth_slot() - 1, "tap")
			bubble.say("earth %s" % _figure_word(_earth_bits()), at)
		2:
			_walk_earth(earth.earth_slot() + 1, "tap")
			bubble.say("earth %s" % _figure_word(_earth_bits()), at)
		3:
			_enhanced = not _enhanced
			stage.visible = _enhanced
			bubble.say("ENHANCED 3D" if _enhanced else "PURE 2D", at)
		4:
			_cycle_geometry()
			bubble.say("geometry: %s" % _geometry_word(), at)
		5:
			bubble.open_large(telemetry_text(), at)
		6:
			bubble.open_large(brain_text(), at)
		7:
			bubble.say("sense period %d ms" % _cycle_period(), at)
		8:
			if _wmn != null and _wmn.has_method("broadcast"):
				_wmn.broadcast(_head_dict(), _body_dict())
				bubble.say("mesh broadcast: %d peers" % _peer_count(), at)
			else:
				bubble.say("mesh beacon: solo mode", at)
		9:
			if _creature != null and _creature.has_method("reset_orientation"):
				_creature.reset_orientation()
			bubble.say("camera reset", at)
		10:
			if _senses != null and _senses.has_method("toggle_freeze"):
				var frz: bool = bool(_senses.toggle_freeze())
				bubble.say("sensors " + ("FROZEN" if frz else "ACTIVE"), at)
			else:
				bubble.say("sensors active", at)
		11:
			bubble.open_large(config_text(), at)
		_:
			pass


## The earth hub: Master Casting Altar and mesh broadcast.
func _on_earth_hub_tapped() -> void:
	var at: Vector2 = _hub_point(earth)
	_cast_earth()
	bubble.say("CAST ALTAR (EARTH)\nThrew 6 coins -> %s\nBroadcasting to %d peers" % [
		_figure_word(_earth_bits()), _peer_count()], at)


func _on_earth_ring_tapped(slot: int) -> void:
	_walk_earth(slot, "tap")


func _on_body_center_tapped() -> void:
	var at: Vector2 = _hub_point(body)
	var bb: int = _body_bits()
	bubble.say("☀️ BODY (MACHINE PHYSICAL STATE)\n%s\nGeometry: %s | Civil Fire: %s\nStillness: %.1fs / 2.5s" % [
		_figure_word(bb), _geometry_word(), _pacing_phrase(), _pacing_phrase()], at)
	if _creature != null and _creature.has_method("tap"):
		_creature.tap(_to_stage(at))


func _on_body_dial_dragged(delta_ang: float) -> void:
	if _creature != null and _creature.ball != null:
		_creature.ball.rotate_y(delta_ang * 2.0)


## A finger in the creature's square: the solid answers, not the ring.
func _on_creature_input(event: InputEvent) -> void:
	if _creature == null or not GlassBubble._is_release(event):
		return
	creature_field.accept_event()
	_creature.tap(_to_stage(event.position))


func _on_throw_requested(_trigram: int) -> void:
	var at: Vector2 = _hub_point(body)
	var bb: int = _body_bits()
	bubble.say("BODY (MACHINE SENSORS)\n%s\n%s | %s" % [
		_figure_word(bb), _geometry_word(), _pacing_phrase()], at)


func _on_send_pressed() -> void:
	composer_send(ask_field.text)


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
	bubble.say("MIC
%s (%d)" % [message, code], _hub_point(head))


func _on_mic_level(rms: float) -> void:
	mic_meter.value = clampf(rms, 0.0, MIC_RMS_FULL)


func _on_mic_state(name_of: String) -> void:
	_mic_listening = name_of == "listening"
	btn_mic.text = MIC_LIVE if _mic_listening else MIC_IDLE
	mic_meter.visible = _mic_listening
	if not _mic_listening:
		mic_meter.value = 0.0


func _on_submitted(text: String) -> void:
	composer_send(text)


# -- what the store says back ------------------------------------------------

func _on_head_changed(_h: Dictionary) -> void:
	head.set_head_bits(_head_bits())


func _on_earth_changed(_e: Dictionary) -> void:
	if earth != null:
		earth.set_hexagram(_earth_bits())


func _on_body_changed(_b: Dictionary) -> void:
	body.set_body_bits(_body_bits())


## A flip is not drawn: it is the newest sentence the status line has, and the
## status line reads it off the store every frame.
func _on_flipped(_f: Dictionary) -> void:
	pass


func _on_family_changed(_f: Dictionary) -> void:
	_refresh_dials()


func _on_room_changed(_r: Dictionary) -> void:
	_refresh_room()


func _on_answer_changed(a: String) -> void:
	_stream = ""
	if a.strip_edges() == "":
		return
	if bubble.visible and not bubble.large():
		bubble.stream(a)
	elif _awaiting:
		bubble.say(a, _hub_point(head))
	_awaiting = false


func _on_token(t: String) -> void:
	_stream += t
	if _awaiting:
		bubble.stream(_stream)


# -- refreshing --------------------------------------------------------------

func _process(_delta: float) -> void:
	status_label.text = _status_line()


func _refresh_dials() -> void:
	if _store == null:
		return
	head.set_head_bits(_head_bits())
	body.set_body_bits(_body_bits())
	if earth != null:
		earth.set_hexagram(_earth_bits())
	head.active_human_trigram = int(_store.human.get("trigram", 0))
	body.active_machine_trigram = int(_store.machine.get("trigram", 7))
	if _senses != null and _senses.has_method("scores"):
		var rows: Dictionary = _senses.scores()
		body.set_scores(rows.get("machine", []) as Array)
		head.set_scores(rows.get("human", []) as Array)
	_refresh_room()


func _refresh_room() -> void:
	if _store == null:
		return
	earth.set_room(int(_store.room.get("bits", 0)), int(_store.room.get("peers", 0)))


## The stage takes the whole glass, the tap square takes the middle of the body
## band, and the eye is told where to stand so the two agree.
func _layout_stage() -> void:
	if root == null or stage == null or body_band == null:
		return
	var box: Vector2 = root.size
	if box.x < 8.0 or box.y < 8.0:
		return

	var band: Vector2 = body_band.size
	if band.x < 8.0 or band.y < 8.0:
		return
	var reach: float = minf(band.x, band.y) * FIELD_FRACTION
	creature_field.position = (band - Vector2(reach, reach)) * 0.5
	creature_field.size = Vector2(reach, reach)
	_frame_creature()


## WHERE THE EYE STANDS. The solid has to come out the width of the ring's
## inner circle and land on the middle of the body band, and the glass is not
## the shape of the band -- so the distance is solved from the eye's own field
## of view, and the height from how far the band's middle is from the glass's.
## Nothing of the creature is altered but where it is looked at from, which is
## the stage's business and no one else's.
func _frame_creature() -> void:
	if _creature == null or _creature.camera == null:
		return
	var box: Vector2 = root.size
	var band: Vector2 = body_band.size
	var want_px: float = minf(band.x, band.y) * INNER_CIRCLE * CREATURE_FILL
	if want_px < 1.0 or box.y < 8.0:
		return
	var cam: Camera3D = _creature.camera
	var half: float = tan(deg_to_rad(cam.fov) * 0.5)
	var z: float = SOLID_DIAMETER * box.y / (2.0 * half * want_px)
	var drop_px: float = _band_middle().y - box.y * 0.5
	var world_per_px: float = 2.0 * half * z / box.y
	cam.position = Vector3(0.0, drop_px * world_per_px, z)


## The middle of the body band, in the glass's own coordinates.
func _band_middle() -> Vector2:
	return body_band.global_position - root.global_position + body_band.size * 0.5


## A point in the creature's tap square, in the pixels of the stage viewport.
## The stage is the whole glass now, so the square's own corner has to be added
## back or every tap lands up and to the left of where the finger was.
func _to_stage(p: Vector2) -> Vector2:
	var box: Vector2 = root.size
	var v := Vector2(view.size)
	if box.x < 1.0 or box.y < 1.0:
		return p
	var at: Vector2 = creature_field.global_position - root.global_position + p
	var q: Vector2 = Vector2(at.x * v.x / box.x, at.y * v.y / box.y)
	return Vector2(clampf(q.x, 0.0, v.x), clampf(q.y, 0.0, v.y))


# -- the status line ---------------------------------------------------------

## TWO LINES, NEWEST FIRST. The top line is whatever just happened -- a line
## of the body turning, and how it was earned -- and when nothing has just
## happened it falls back to the thing the owner's old surface put in the
## biggest type it had: WHICH TWO FIGURES ARE STANDING. The second line is the
## state that is always true and never news: the fabric, the pacing, the tier
## and the frame rate.
## THE FIGURES ALWAYS HOLD THE TOP LINE, and the news displaces the STATE
## underneath them. The first arrangement gave a fresh flip the top line, which
## read well and worked badly: under stillness the alchemy turns a line about
## as often as a flip stays news, so the two figures -- the thing the owner's
## old surface set in the biggest type it had -- would have been shown almost
## never. What a person is holding outranks what just happened to it.
func _status_line() -> String:
	if _mic_listening:
		return _figures_phrase() + "
" + MIC_PHRASE
	var news: String = _flip_phrase()
	return _figures_phrase() + "\n" + (news if news != "" else _state_phrase())


## The strip with no news on it: the two figures over the state. This is the
## glass's OWN sentence, and it is ASCII but for the owner's two marks. The
## news that displaces it is the core's own words and is left as it is spoken.
func status_summary() -> String:
	return _figures_phrase() + "\n" + _state_phrase()


## The two figures, marked with the owner's moon and sun.
func _figures_phrase() -> String:
	return "%s HEAD %s   %s BODY %s" % [
		MOON, _figure_word(_head_bits()), SUN, _figure_word(_body_bits())]


## What is always true and never news.
func _state_phrase() -> String:
	var state: Array[String] = ([] as Array[String])
	state.append(_mesh_phrase())
	state.append(_pacing_phrase())
	state.append(_tier_phrase())
	state.append("%d FPS" % Engine.get_frames_per_second())
	return " | ".join(state)


func _flip_phrase() -> String:
	if _store == null or not ("last_flip" in _store):
		return ""
	var f: Dictionary = _store.last_flip
	var when: int = int(f.get("when", 0))
	if when <= 0 or (_now_ms() - when) > FLIP_FRESH_MS:
		return ""
	return "flip L%d %s %s" % [
		int(f.get("line", 0)) + 1,
		"yang" if bool(f.get("to_yang", false)) else "yin",
		String(f.get("reason", "")),
	]


func _mesh_phrase() -> String:
	if _wmn == null:
		return "mesh off"
	var fabric: String = "lan" if bool(_wmn.force_lan) else "nearby"
	var backend: String = String(_mnn.backend_name()) if _mnn != null else "none"
	return "%s %s %dp" % [fabric, backend, _peer_count()]


func _pacing_phrase() -> String:
	if _senses == null:
		return "pacing idle"
	var still: float = float(_senses.stillness()) if _senses.has_method("stillness") else 0.0
	var hot: float = float(_senses.excitation()) if _senses.has_method("excitation") else 0.0
	if hot >= _threshold("MARTIAL_THRESHOLD", MARTIAL_THRESHOLD):
		return "martial %.2f" % hot
	return "civil %.1fs of %.1f" % [still, _threshold("CIVIL_FIRE_THRESHOLD", CIVIL_FIRE_THRESHOLD)]


func _tier_phrase() -> String:
	if _mnn == null:
		return "no model"
	var t: String = String(_mnn.tier())
	return t if t != "" else "no tier"


## A Pacing constant when Pacing is there to give one, and the same number
## written down here when it is not.
func _threshold(key: String, fallback: float) -> float:
	if _pacing == null:
		return fallback
	var map: Dictionary = _pacing.get_script_constant_map()
	return float(map.get(key, fallback))


# -- the two large views -----------------------------------------------------

## Everything the sixteen are saying, as one block of plain text.
func telemetry_text() -> String:
	var lines: Array[String] = (["TELEMETRY"] as Array[String])
	lines.append("head %s   body %s" % [_figure_word(_head_bits()), _figure_word(_body_bits())])
	lines.append(_pacing_phrase())
	if _senses == null or not _senses.has_method("scores"):
		lines.append("the sixteen are not attached")
		return "\n".join(lines)
	var rows: Dictionary = _senses.scores()
	for family in [0, 1]:
		var row: Array = (rows.get("machine", []) if family == 0 else rows.get("human", [])) as Array
		lines.append("-- %s --" % ("machine" if family == 0 else "human"))
		for i in range(row.size()):
			lines.append("%d %s %.2f  %s" % [
				i, _seat_label(family, i), float(row[i]), _sentence_of(family, i)])
	return "\n".join(lines)


func config_text() -> String:
	var lines: Array[String] = (["HEXY CONFIG & IDENTITY"] as Array[String])
	lines.append("node: %s" % _who)
	lines.append("mesh fabric: %s" % ("lan" if _wmn != null and bool(_wmn.force_lan) else "nearby"))
	lines.append("peers connected: %d" % _peer_count())
	lines.append("geometry: %s" % _geometry_word())
	lines.append("mnn tier: %s" % _tier_phrase())
	lines.append("sense period: %d ms" % (int(_senses.period_ms) if _senses != null else 0))
	lines.append("enhanced 3d: %s" % ("enabled" if _enhanced else "disabled"))
	return "\n".join(lines)


func _on_configure_pressed() -> void:
	var at: Vector2 = _point_in_root(status_panel, status_panel.size - Vector2(24.0, -10.0))
	bubble.open_large(config_text(), at)


## What the model is, what the fruit fly connectome is living, and what it is allowed to be on this phone.
func brain_text() -> String:
	var lines: Array[String] = (["BRAIN & CONNECTOME"] as Array[String])
	if _store != null and _store.has_method("get_character"):
		var char_node: Variant = _store.get_character()
		if char_node != null:
			lines.append("-- DROSOPHILA CONNECTOME --")
			## ONE BRAIN, ONE DICTIONARY. The glass asks the character for the
			## state of the fly and reads fixed keys; it never reaches inside a
			## subsystem for a member that may or may not be spelled that way.
			var fly: Dictionary = char_node.get_fly_state() if char_node.has_method("get_fly_state") else {}
			if not fly.is_empty():
				lines.append("circadian: %.1fh (%s) PDF: %.2f" % [
					float(fly.get("solar_hour", 12.0)),
					String(fly.get("phase", "Day")),
					float(fly.get("pdf", 0.0))
				])
				lines.append("EB/PB compass: %.1f deg %s (align: %.2f, coherence: %.2f)" % [
					rad_to_deg(float(fly.get("heading_rad", 0.0))),
					String(fly.get("dominant_trigram", "")),
					float(fly.get("target_alignment", 0.0)),
					float(fly.get("coherence", 0.0))
				])
				var habit: Array = (fly.get("habit_bias", []) as Array)
				var habit_words: Array[String] = ([] as Array[String])
				for h in habit:
					habit_words.append("%+.2f" % float(h))
				lines.append("mushroom body: %d KCs active | habit: %s" % [
					int(fly.get("kc_count", 0)),
					", ".join(habit_words)
				])
				lines.append("giant fiber: startle %.2f curl %.2f (%s)" % [
					float(fly.get("startle", 0.0)),
					float(fly.get("curl", 0.0)),
					"ESCAPING" if bool(fly.get("is_startled", false)) else "calm"
				])
				lines.append("conductance: DA:%.2f OA:%.2f 5HT:%.2f ACh:%.2f" % [
					float(fly.get("dopamine", 0.0)),
					float(fly.get("octopamine", 0.0)),
					float(fly.get("serotonin", 0.0)),
					float(fly.get("acetylcholine", 0.0))
				])
	if _mnn == null:
		lines.append("no model is attached")
		return "\n".join(lines)
	lines.append("-- ON-DEVICE INFERENCE (MNN) --")
	lines.append("backend %s" % String(_mnn.backend_name()))
	lines.append("tier %s" % _tier_phrase())
	lines.append("on device: %s" % ("yes" if bool(_mnn.available()) else "no"))
	for t in _mnn.tiers():
		var row: Dictionary = t as Dictionary
		lines.append("- %s %s" % [String(row.get("id", "")), String(row.get("name", ""))])
	lines.append("answer: %s" % (String(_store.answer) if _store != null else ""))
	return "\n".join(lines)


# -- the head and the body, as the store keeps them --------------------------

func _head_dict() -> Dictionary:
	if _store != null and ("head" in _store):
		return _store.head as Dictionary
	return {}


func _body_dict() -> Dictionary:
	if _store != null and ("body" in _store):
		return _store.body as Dictionary
	return {}


func _head_bits() -> int:
	if _store != null and _store.has_method("head_bits"):
		return int(_store.head_bits()) & 63
	return int(_head_dict().get("bits", 0)) & 63


func _body_bits() -> int:
	if _store == null:
		return 0
	if _store.has_method("body_bits"):
		return int(_store.body_bits()) & 63
	return int(_store.primary()) & 63


## Walk the HEAD to a slot of the head sequence and write it down. The store is
## the only place a figure lives; the ring follows the store, never the reverse.
func _walk_head(slot: int, why: String) -> void:
	var idx: int = posmod(slot, HuohoutuData.HEAD_SEQUENCE.size())
	var hex: Dictionary = HuohoutuData.get_head_hex(idx)
	_write_head(int(hex.get("bits", 0)), ([] as Array[int]), why, idx)


## The coin throw, on the head only: six lines, thrown once, signed.
func _cast_head() -> void:
	var now: int = _now_ms()
	var cast: Dictionary = Cast.tap_cast(Cast.seed_of(now, _who, 0))
	var bits: int = int(cast.get("bits", 0)) & 63
	var throws: Array[int] = ([] as Array[int])
	for v in (cast.get("throws", []) as Array):
		throws.append(int(v))
	var id: int = int(HuohoutuData.get_by_bits(bits).get("id", 1))
	_write_head(bits, throws, "tap", HuohoutuData.find_head_index_by_id(id))


func _write_head(bits: int, throws: Array[int], why: String, slot: int) -> void:
	head.set_head_slot(slot)
	if _store == null or not _store.has_method("set_head"):
		return
	_store.set_head({
		"bits": bits,
		"moving": 0,
		"throws": throws,
		"when": _now_ms(),
		"who": _who,
		"source": why,
		"sig": "",
		"seq_index": slot,
	})


# -- small helps -------------------------------------------------------------

## THE SENSE PERIOD, WALKED ROUND A RING OF FOUR. The senses own the number and
## announce it; the app's ticker follows the announcement, so this station sets
## one value and everything downstream of it moves on its own.
func _cycle_period() -> int:
	if _senses == null:
		return 0
	var now: int = int(_senses.period_ms)
	var i: int = PERIODS_MS.find(now)
	var next: int = PERIODS_MS[posmod(i + 1, PERIODS_MS.size())]
	_senses.period_ms = next
	return next


func _cycle_geometry() -> void:
	if _creature == null or _creature.ball == null:
		return
	_creature.ball.cycle_geometry_mode()


func _geometry_word() -> String:
	return String(_creature.geometry_name()) if _creature != null else "none"


## A figure, said the way the owner's old card said it: the number, his own
## character, and the name. The character is HuohoutuData's own spelling and it
## is carried through untouched.
func _figure_word(bits: int) -> String:
	return "#%d %s %s" % [KingWen.number(bits), KingWen.zh(bits), KingWen.name(bits)]


func _peer_count() -> int:
	if _wmn != null and _wmn.has_method("peer_count"):
		return int(_wmn.peer_count())
	return int(_store.room.get("peers", 0)) if _store != null else 0


func _now_ms() -> int:
	if _wmn != null and _wmn.has_method("now_ms"):
		return int(_wmn.now_ms())
	return Time.get_ticks_msec()


func _sentence_of(family: int, index: int) -> String:
	if _senses != null and _senses.has_method("sense"):
		return String(_senses.sense(family, index).sentence())
	if _store == null:
		return "not sensed"
	var f: Dictionary = _store.machine if family == 0 else _store.human
	if int(f.get("trigram", -1)) == index:
		return String(f.get("sentence", "not sensed"))
	return "not sensed"


func _seat_label(family: int, index: int) -> String:
	if _senses != null and _senses.has_method("sense"):
		var l: String = String(_senses.sense(family, index).label())
		if l != "":
			return l
	return KingWen.trigram_name(index)


## A point on a dial, said in the bubble's own coordinates.
func _point_in_root(from: Control, at: Vector2) -> Vector2:
	return (from.get_global_transform() * at) - root.get_global_transform().origin


func _hub_point(from: Control) -> Vector2:
	return _point_in_root(from, from.size * 0.5)


## Connect once, and only to a signal that is really there.
static func _join(who_node: Object, what: String, to: Callable) -> void:
	if who_node == null or not who_node.has_signal(what):
		return
	if not who_node.is_connected(what, to):
		who_node.connect(what, to)


func _walk_earth(slot: int, why: String) -> void:
	var idx: int = posmod(slot, 64)
	var hex: Dictionary = HuohoutuData.get_head_hex(idx)
	var bits: int = int(hex.get("bits", 2))
	_write_earth(bits, ([] as Array[int]), why, idx)


func _cast_earth() -> void:
	var now: int = _now_ms()
	var cast: Dictionary = Cast.tap_cast(Cast.seed_of(now, _who, 0))
	var bits: int = int(cast.get("bits", 0)) & 63
	var throws: Array[int] = ([] as Array[int])
	for v in (cast.get("throws", []) as Array):
		throws.append(int(v))
	var id: int = int(HuohoutuData.get_by_bits(bits).get("id", 1))
	_write_earth(bits, throws, "tap", HuohoutuData.find_head_index_by_id(id))


func _write_earth(bits: int, throws: Array[int], why: String, slot: int) -> void:
	if earth != null:
		earth.set_earth_slot(slot)
	if _store == null or not _store.has_method("set_earth"):
		return
	_store.set_earth({
		"bits": bits,
		"moving": 0,
		"throws": throws,
		"when": _now_ms(),
		"who": _who,
		"source": why,
	})
	if _wmn != null and _wmn.has_method("broadcast"):
		_wmn.broadcast(_earth_dict(), _body_dict())


func _earth_bits() -> int:
	if _store != null and _store.has_method("earth_bits"):
		return int(_store.earth_bits())
	return earth.hex_bits if earth != null else 2


func _earth_dict() -> Dictionary:
	if _store != null and _store.get("earth") is Dictionary:
		return _store.earth as Dictionary
	return {}
