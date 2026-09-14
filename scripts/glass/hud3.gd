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
const STATUS_H: float = 52.0
const HEAD_H: float = 270.0
const EARTH_H: float = 270.0
const COMPOSER_H: float = 54.0
const BAND_GAP: int = 12
## The left column the radar takes on a fold that is open, in pixels, and the
## two sizes the radar itself is given in its two placements.
const RADAR_PANE_W: float = 300.0
const RADAR_TALL_H: float = 420.0
const RADAR_DISC_H: float = 190.0

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
const EARTH_ICON: String = "🌍"

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

## The strip is composed four times a second, not sixty.
const STATUS_PERIOD_MS: int = 250

## THE SIX DRAWER KEYS THIS GLASS OBEYS. Every one of them is pulled once at
## boot and again the moment the drawer says it moved, so a person turning a
## switch in the dashboard sees the glass change under their finger rather than
## on the next restart.
const KEY_DWELL_RING: String = "hud.dwell_ring"
const KEY_LINE_FLASH: String = "hud.line_flash"
const KEY_EARTH_MODE: String = "hud.earth_mode"
const KEY_STATUS_MODE: String = "hud.status_mode"
const KEY_ROOM_HIGHLIGHT: String = "hud.room_highlight"
const KEY_BREATHE: String = "creature.breathe_with_dwell"

## How long the tick of a line that just turned stays lit, in milliseconds.
const FLASH_MS: int = 600

## How many journal entries the status bubble carries.
const JOURNAL_TAIL: int = 12

## A day, in milliseconds, for counting the journal's own days.
const DAY_MS: int = 86400000

## The dwell arc's two colours: the civil fire banking, and the martial fire
## taking over. They are the body dial's own cyan and the Huohoutu orange.
const COL_DWELL: Color = Color(0.25, 0.80, 1.0, 0.9)
const COL_FIRE: Color = Color(1.0, 0.45, 0.12, 0.95)
const COL_FLASH: Color = Color(1.0, 0.92, 0.55, 0.98)
## The second colour a head tick wears when somebody else in the room is
## standing on the same figure.
const COL_ROOM: Color = Color(0.35, 1.0, 0.65, 0.95)

var _status_at: int = 0
var _pacing_consts: Dictionary = {}

## The live answers to the six keys, cached so `_process` reads a bool and not
## a dictionary sixty times a second.
var _cfg_dwell_ring: bool = true
var _cfg_line_flash: bool = true
var _cfg_earth_mode: String = "lines"
var _cfg_status_mode: String = "day"
var _cfg_room_highlight: bool = true
var _cfg_breathe: bool = true

## The line that just turned and how long it stays lit.
var _flash_line: int = -1
var _flash_until_ms: int = 0
## Which earth line the last tap moved, so an answer can be anchored on it.
var _last_moved_line: int = -1

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
## THE EARTH BAND'S OTHER FACE. Both dials are built and both stay in the band;
## only one of them is ever visible, because rebuilding a Control on a config
## change is how a signal ends up connected twice.
var earth_lines: EarthLinesDial = null

## The two thin overlays: the dwell arc and the flashing line over the body
## dial, and the room mark over the head dial. Neither takes a tap.
var dwell_ring: Control = null
var room_mark: Control = null

## THE CALCIUM RADAR, the fly's own ellipsoid body drawn where a person can
## see it. It is fed one `get_fly_state()` dictionary a frame and nothing else,
## and where it stands is DeviceProfile's decision, not this file's:
##   dual pane   a column of its own down the left, the bands moved off it
##   tall slab   a small disc in a band of its own directly under the body
## Either way it is laid out beside the three dials and never over them.
var radar: Control = null
var radar_pane: CenterContainer = null
var pad: MarginContainer = null

var stage: SubViewportContainer = null
var view: SubViewport = null
var creature_field: Control = null

var composer: PanelContainer = null
var ask_field: LineEdit = null
var btn_mic: Button = null
var mic_meter: ProgressBar = null
var btn_send: Button = null

var bubble: GlassBubble = null

## THE GEAR'S OWN PANEL: the whole base app drawn as gauges, hidden until the
## configure button is pressed. It is a sibling laid OVER the bands, never one
## of them, so the three dials measure the same whether it stands or not.
var dashboard: HexyDashboard = null

## The add-on loader, held only to hand on to the doors panel.
var _addons: Node = null

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
## Which of the two radar placements is standing. Re-read on every resize, and
## the radar is only moved when the answer actually changed.
var _radar_layout: String = ""


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

	pad = MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	root.add_child(pad)

	# AxisSpine cut off per layout request - dials are cleanly separated with proportional spacing
	# (No central vertical line slicing through components)

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
	_build_radar()

	bubble = GlassBubble.new()
	root.add_child(bubble)

	_watch_config()
	set_process(true)


# -- the drawer --------------------------------------------------------------

## PULLED ONCE, THEN FOLLOWED. `peek` and never `instance`, so a headless test
## that never asked for a drawer keeps the defaults written above and does not
## have one built underneath it.
func _watch_config() -> void:
	var cfg: HexyConfig = HexyConfig.peek()
	if cfg == null:
		_apply_config()
		return
	_cfg_dwell_ring = bool(cfg.get_value(KEY_DWELL_RING))
	_cfg_line_flash = bool(cfg.get_value(KEY_LINE_FLASH))
	_cfg_earth_mode = String(cfg.get_value(KEY_EARTH_MODE))
	_cfg_status_mode = String(cfg.get_value(KEY_STATUS_MODE))
	_cfg_room_highlight = bool(cfg.get_value(KEY_ROOM_HIGHLIGHT))
	_cfg_breathe = bool(cfg.get_value(KEY_BREATHE))
	if not cfg.changed.is_connected(_on_config_changed):
		cfg.changed.connect(_on_config_changed)
	_apply_config()


func _on_config_changed(key: String, value: Variant) -> void:
	match key:
		KEY_DWELL_RING: _cfg_dwell_ring = bool(value)
		KEY_LINE_FLASH: _cfg_line_flash = bool(value)
		KEY_EARTH_MODE: _cfg_earth_mode = String(value)
		KEY_STATUS_MODE: _cfg_status_mode = String(value)
		KEY_ROOM_HIGHLIGHT: _cfg_room_highlight = bool(value)
		KEY_BREATHE: _cfg_breathe = bool(value)
		_: return
	_apply_config()


## What the six answers mean on the glass, applied in one place so a live
## change and a boot take exactly the same path.
func _apply_config() -> void:
	if dwell_ring != null:
		dwell_ring.visible = _cfg_dwell_ring
	if room_mark != null:
		room_mark.visible = _cfg_room_highlight
	_apply_earth_mode()
	_refresh_status_strip(true)


## Which face the earth band wears. Nothing is rebuilt: one is shown, the other
## is hidden, and the hidden one stops answering fingers with it.
func _apply_earth_mode() -> void:
	var lines_on: bool = _cfg_earth_mode == "lines"
	if earth != null:
		earth.visible = not lines_on
		earth.mouse_filter = Control.MOUSE_FILTER_IGNORE if lines_on else Control.MOUSE_FILTER_STOP
		earth.custom_minimum_size = Vector2(0.0, 0.0 if lines_on else EARTH_H)
	if earth_lines != null:
		earth_lines.visible = lines_on
		earth_lines.mouse_filter = Control.MOUSE_FILTER_STOP if lines_on else Control.MOUSE_FILTER_IGNORE
		earth_lines.custom_minimum_size = Vector2(0.0, EARTH_H if lines_on else 0.0)
		_refresh_earth_lines()


## The earth band's mode, as a word.
func earth_mode() -> String:
	return _cfg_earth_mode


func _refresh_earth_lines() -> void:
	if earth_lines != null:
		earth_lines.set_figures(_body_bits(), _head_bits())


## THE RADAR AND ITS LEFT PANE. The pane is a container of its own so the
## radar is centred in it without this file doing arithmetic, and the bands are
## pushed off it by the one margin that already exists.
func _build_radar() -> void:
	radar_pane = CenterContainer.new()
	radar_pane.name = "RadarPane"
	radar_pane.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	radar_pane.offset_left = 8.0
	radar_pane.offset_right = 8.0 + RADAR_PANE_W
	radar_pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar_pane.visible = false
	root.add_child(radar_pane)

	radar = FlyCalciumRadar2D.new()
	radar.name = "CalciumRadar"
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_radar_layout()


## WHERE THE RADAR STANDS, asked of DeviceProfile and nobody else. A fold open
## has room for a column beside the glass; a slab does not, and gets the disc.
func _apply_radar_layout() -> void:
	if radar == null or root == null or bands == null or pad == null:
		return
	var box: Vector2i = Vector2i(root.size)
	if box.x < 8 or box.y < 8:
		box = DisplayServer.window_get_size()
	var profile: Dictionary = DeviceProfile.resolve(-1, box, "")
	var want: String = "dual_pane" if bool(profile.get("is_dual_pane", false)) else "tall_slab"
	if want == _radar_layout and radar.get_parent() != null:
		return
	_radar_layout = want
	if radar.get_parent() != null:
		radar.get_parent().remove_child(radar)
	if want == "dual_pane":
		radar_pane.visible = true
		radar_pane.add_child(radar)
		radar.radar_radius = 108.0
		radar.ring_thickness = 24.0
		radar.show_neuromodulators = true
		radar.custom_minimum_size = Vector2(RADAR_PANE_W, RADAR_TALL_H)
		pad.add_theme_constant_override("margin_left", int(RADAR_PANE_W) + 16)
	else:
		radar_pane.visible = false
		radar.radar_radius = 66.0
		radar.ring_thickness = 15.0
		radar.show_neuromodulators = false
		radar.custom_minimum_size = Vector2.ZERO
		radar_pane.add_child(radar)
		pad.add_theme_constant_override("margin_left", 8)


## The radar's placement, as a word: "dual_pane" or "tall_slab".
func radar_layout() -> String:
	return _radar_layout


func radar_dial() -> Control:
	return radar


## 1. THE STATUS STRIP: one line that keeps a person informed, newest first,
## with a configure button on the top-right.
func _build_status() -> void:
	status_panel = PanelContainer.new()
	status_panel.name = "Status"
	status_panel.custom_minimum_size = Vector2(0.0, STATUS_H)
	status_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	## THE STRIP ANSWERS A FINGER NOW. It is the shortest sentence the app has
	## about the day, and the journal behind it is the longest, so the one opens
	## the other. The gear button is still a child with its own STOP filter and
	## keeps its own tap.
	status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	status_panel.gui_input.connect(_on_status_input)
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
	status_label.add_theme_font_size_override("font_size", 11)
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

	room_mark = RoomMark.new(self)
	head.add_child(room_mark)


## 3. THE BODY DIAL, BIG, DRAWN AROUND THE CREATURE. The ring is the whole
## band; the solid stands in a square in the middle of it; and the square is
## the only place a tap reaches the creature, so no point has two owners.
func _build_body() -> void:
	body_band = Control.new()
	body_band.name = "BodyBand"
	body_band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_child(body_band)

	body = BodyDialTap.new()
	body.name = "BodyDial"
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body_band.add_child(body)
	body.machine_station_clicked.connect(_on_machine_diamond_tapped)
	body.center_clicked.connect(_on_body_center_tapped)
	body.dial_dragged.connect(_on_body_dial_dragged)
	body.ring_slot_tapped.connect(_on_body_ring_tapped)

	## THE DWELL ARC LIES OVER THE RIM, not in the dial. The body dial is a
	## family member with two subclasses and eight other readers; an arc that is
	## only ever the glass's opinion of the senses has no business inside it.
	dwell_ring = DwellRing.new(self)
	body_band.add_child(dwell_ring)

	creature_field = Control.new()
	creature_field.name = "CreatureField"
	creature_field.set_anchors_preset(Control.PRESET_TOP_LEFT)
	creature_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creature_field.gui_input.connect(_on_creature_input)
	body_band.add_child(creature_field)
	body_band.resized.connect(_layout_stage)
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

	earth_lines = EarthLinesDial.new()
	earth_lines.name = "EarthLines"
	earth_lines.custom_minimum_size = Vector2(0.0, EARTH_H)
	earth_lines.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bands.add_child(earth_lines)
	earth_lines.line_tapped.connect(_on_earth_line_tapped)
	earth_lines.hub_tapped.connect(_on_earth_hub_tapped)
	_apply_earth_mode()


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
		## ONE OF THE TWO, NEVER BOTH. `hexagram_changed` is the old name of
		## `body_changed` and the store fires both on every body write; joining
		## both would redraw the dial twice for one move. The old name is kept
		## for the readers written before there were two figures.
		if not _store.has_signal("body_changed"):
			_join(_store, "hexagram_changed", _on_body_changed)
		_join(_store, "machine_changed", _on_family_changed)
		_join(_store, "human_changed", _on_family_changed)
		_join(_store, "room_changed", _on_room_changed)
		_join(_store, "answer_changed", _on_answer_changed)
	_join(_mnn, "token", _on_token)
	_build_dashboard()
	_refresh_dials()


func set_senses(senses: Node) -> void:
	_senses = senses
	if dashboard != null:
		dashboard.set_senses(senses)
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


## THE ADD-ON LOADER, passed straight through to the doors panel. The glass
## itself has no opinion about add-ons; it only knows where the panel is.
func set_addons(addons: Node) -> void:
	_addons = addons
	if dashboard != null:
		dashboard.set_addons(addons)


## The alchemy is held only so the glass can say what it last did.
func set_alchemy(alchemy: Node) -> void:
	_alchemy = alchemy
	if dashboard != null:
		dashboard.set_alchemy(alchemy)


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
	return _earth_control().get_global_rect()


## Whichever face of the earth band is standing. Every point and every rect the
## glass asks for comes through here, so nothing has to know which mode is on.
func _earth_control() -> Control:
	if earth_lines != null and earth_lines.visible:
		return earth_lines
	return earth


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


## The twelve earth stations, in the order they are drawn. EVERY ONE OF THEM IS
## NOW A METHOD, not a branch: the stations are evicted from the band the moment
## `hud.earth_mode` is "lines", and an action that only exists inside a `match`
## on a Control that is no longer drawn is an action a person has lost. The
## dashboard reaches these by name; this handler is one of its callers, not the
## owner of the behaviour.
func _on_earth_station_tapped(index: int) -> void:
	var at: Vector2 = _point_in_root(earth, earth.station_position(index))
	match index:
		0:
			cast_earth()
			bubble.say("CAST ALTAR: %s" % _figure_word(_earth_bits()), at)
		1:
			walk_earth(-1)
			bubble.say("earth %s" % _figure_word(_earth_bits()), at)
		2:
			walk_earth(1)
			bubble.say("earth %s" % _figure_word(_earth_bits()), at)
		3:
			bubble.say("ENHANCED 3D" if toggle_enhanced() else "PURE 2D", at)
		4:
			bubble.say("geometry: %s" % cycle_geometry(), at)
		5:
			bubble.open_large(telemetry_text(), at)
		6:
			bubble.open_large(brain_text(), at)
		7:
			bubble.say("sense period %d ms" % cycle_sense_period(), at)
		8:
			var peers: int = mesh_broadcast()
			var word: String = "mesh beacon: solo mode"
			if peers >= 0:
				word = "mesh broadcast: %d peers" % peers
			bubble.say(word, at)
		9:
			camera_reset()
			bubble.say("camera reset", at)
		10:
			bubble.say("sensors " + ("FROZEN" if toggle_sensor_freeze() else "ACTIVE"), at)
		11:
			bubble.open_large(config_text(), at)
		_:
			pass


# -- the evicted twelve, as methods ------------------------------------------

## The 3D stage, shown or hidden. Returns whether it now stands.
func toggle_enhanced() -> bool:
	_enhanced = not _enhanced
	if stage != null:
		stage.visible = _enhanced
	return _enhanced


## The solid turns to its next geometry. Returns the name it landed on.
func cycle_geometry() -> String:
	_cycle_geometry()
	return _geometry_word()


## The sixteen are read on the next of four beats. Returns the new period in ms.
func cycle_sense_period() -> int:
	return _cycle_period()


## Both figures go on the air. Returns the peer count, or -1 when there is no
## mesh at all to put them on.
func mesh_broadcast() -> int:
	if _wmn == null or not _wmn.has_method("broadcast"):
		return -1
	_wmn.broadcast(_head_dict(), _body_dict())
	return _peer_count()


## The eye goes back where it started.
func camera_reset() -> void:
	if _creature != null and _creature.has_method("reset_orientation"):
		_creature.reset_orientation()


## The sixteen are held, or let go. Returns whether they are now frozen.
func toggle_sensor_freeze() -> bool:
	if _senses == null or not _senses.has_method("toggle_freeze"):
		return false
	return bool(_senses.toggle_freeze())


## Six coins on the altar. Returns the earth seat as the store now holds it.
func cast_earth() -> Dictionary:
	_cast_earth()
	return _earth_dict()


## The altar walks `delta` seats along the head's wheel.
func walk_earth(delta: int) -> void:
	var from: int = earth.earth_slot() if earth != null else 0
	_walk_earth(from + delta, "tap")


## A line of the earth ring, touched: that one line of the BODY is chosen as the
## moving line and the altar is seated on the figure it makes. The event is the
## same shape `_write_earth` builds for a cast, because the seat bus has one
## shape and a tap is not a special case of it.
func _on_earth_line_tapped(i: int) -> void:
	var line: int = clampi(i, 0, 5)
	var bits: int = (_body_bits() ^ (1 << line)) & 63
	var id: int = int(HuohoutuData.get_by_bits(bits).get("id", 1))
	_last_moved_line = line
	_write_earth(bits, ([] as Array[int]), "tap",
		HuohoutuData.find_head_index_by_id(id), 1 << line)
	_refresh_earth_lines()
	bubble.say("%s %s -> %s" % [
		earth_lines.line_name(line), earth_lines.line_state(line), _figure_word(bits),
	], _earth_line_point(line))


## Where a line of the earth ring is, in the bubble's own coordinates.
func _earth_line_point(i: int) -> Vector2:
	if earth_lines == null or not earth_lines.visible:
		return _hub_point(composer)
	return _point_in_root(earth_lines, earth_lines.line_position(clampi(i, 0, 5)))


## The earth hub: Master Casting Altar and mesh broadcast.
func _on_earth_hub_tapped() -> void:
	var at: Vector2 = _hub_point(_earth_control())
	_cast_earth()
	_refresh_earth_lines()
	bubble.say("CAST ALTAR (EARTH)\nThrew 6 coins -> %s\nBroadcasting to %d peers" % [
		_figure_word(_earth_bits()), _peer_count()], at)


func _on_earth_ring_tapped(slot: int) -> void:
	_walk_earth(slot, "tap")


func _on_body_center_tapped() -> void:
	var at: Vector2 = _hub_point(body)
	var bb: int = _body_bits()
	var still_s: float = float(_senses.stillness()) if (_senses != null and _senses.has_method("stillness")) else 0.0
	bubble.say("☀️ BODY (MACHINE PHYSICAL STATE)\n%s\nGeometry: %s | Pacing: %s\nStillness: %.1fs / 2.5s" % [
		_figure_word(bb), _geometry_word(), _pacing_phrase(), still_s], at)
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
	_refresh_status_strip(true)


func _on_submitted(text: String) -> void:
	composer_send(text)


# -- what the store says back ------------------------------------------------

func _on_head_changed(_h: Dictionary) -> void:
	head.set_head_bits(_head_bits())
	_refresh_earth_lines()


func _on_earth_changed(_e: Dictionary) -> void:
	if earth != null:
		earth.set_hexagram(_earth_bits())
	_refresh_earth_lines()


func _on_body_changed(_b: Dictionary) -> void:
	body.set_body_bits(_body_bits())
	_refresh_earth_lines()


## A FLIP IS THE ONE EVENT ON THIS GLASS THAT IS WORTH INTERRUPTING FOR. It
## still writes no text -- the status line reads the store for that -- but the
## tick of the line that turned is lit for six hundred milliseconds and the
## creature is given one flare, so a person who was not reading the strip still
## sees their own body move.
func _on_flipped(f: Dictionary) -> void:
	if not _cfg_line_flash:
		return
	_flash_line = clampi(int(f.get("line", 0)), 0, 5)
	_flash_until_ms = Time.get_ticks_msec() + FLASH_MS
	if _creature != null and _creature.has_method("pulse"):
		_creature.pulse()


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
		bubble.say(a, _answer_point())
	_awaiting = false


## WHERE AN ANSWER LANDS. In lines mode the last line a finger moved is the
## thing the question was about, so the answer arrives beside it; with no line
## moved yet, and in stations mode, it arrives at the composer that asked.
func _answer_point() -> Vector2:
	if _cfg_earth_mode == "lines" and _last_moved_line >= 0 and earth_lines != null:
		return _earth_line_point(_last_moved_line)
	return _hub_point(composer)


func _on_token(t: String) -> void:
	_stream += t
	if _awaiting:
		bubble.stream(_stream)


# -- refreshing --------------------------------------------------------------

func _process(_delta: float) -> void:
	_refresh_status_strip()
	_feed_radar()
	_feed_breath()


## THE CREATURE BREATHES WITH THE DWELL, when the drawer says it may. One float
## a frame, pushed rather than pulled, so the creature stays a thing that knows
## nothing about senses or pacing.
func _feed_breath() -> void:
	if not _cfg_breathe or _creature == null or not _creature.has_method("set_breath_rate"):
		return
	_creature.set_breath_rate(dwell_fraction())


## THE STRIP IS NOT A FRAME-RATE COUNTER FOR THE RENDERER TO CHASE. The strip
## carries an FPS number, and a Label reshapes its whole line whenever the text
## it is handed differs from the text it holds. Written every frame, the number
## differed every frame the moment the phone left a flat 60, so the strip paid
## a full text shaping on every frame, which cost frames, which moved the
## number again: the phone latched at 22-24 FPS and stayed there. Now the
## sentence is composed four times a second and only assigned when it really
## changed, so a still screen shapes no text at all.
func _refresh_status_strip(force: bool = false) -> void:
	var now: int = Time.get_ticks_msec()
	if not force and now - _status_at < STATUS_PERIOD_MS:
		return
	_status_at = now
	var line: String = _status_line()
	if line != status_label.text:
		status_label.text = line


## ONE DICTIONARY A FRAME, and the swarm's headings beside it. Both are read
## duck-typed through the objects bind() handed over; the glass names no brain
## and no transport.
func _feed_radar() -> void:
	if radar == null:
		return
	if _store != null and _store.has_method("get_character"):
		var ch: Variant = _store.get_character()
		if ch != null and ch.has_method("get_fly_state"):
			radar.set_state(ch.get_fly_state() as Dictionary)
	if _wmn != null and _wmn.has_method("peer_headings"):
		radar.set_peer_headings(_wmn.peer_headings() as Dictionary)
	if _wmn != null and _wmn.has_method("peer_proximity"):
		radar.set_peer_proximity(_wmn.peer_proximity() as Dictionary)


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
	_refresh_earth_lines()
	_refresh_room()


func _refresh_room() -> void:
	if _store == null:
		return
	earth.set_room(int(_store.room.get("bits", 0)), int(_store.room.get("peers", 0)))


## The stage takes the whole glass, the tap square takes the middle of the body
## band, and the eye is told where to stand so the two agree.
func _layout_stage() -> void:
	if root == null or stage == null or body_band == null or creature_field == null or body == null:
		return
	_apply_radar_layout()
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
	## THE DAY DISPLACES THE STATE, NOT THE FIGURES. The rule written above
	## holds for this mode too: what a person is HOLDING keeps the top line, and
	## the day's one sentence takes the line the fabric and the frame rate used
	## to have. `day_line` is the sentence on its own, for whoever wants it.
	if _mic_listening:
		return _figures_phrase() + "\n" + MIC_PHRASE
	if _cfg_status_mode == "day":
		return _figures_phrase() + "\n" + day_line()
	var news: String = _flip_phrase()
	return _figures_phrase() + "\n" + (news if news != "" else _state_phrase())


## The strip with no news on it: the two figures over the state. This is the
## glass's OWN sentence, and it is ASCII but for the owner's two marks. The
## news that displaces it is the core's own words and is left as it is spoken.
func status_summary() -> String:
	return _figures_phrase() + "\n" + _state_phrase()


## THE DAY, IN ONE SENTENCE: "Day 3 · Breath opens". Which day of the journal a
## person is on, which of the six habits is the one currently turning, and which
## way it is turning. This is the strip a person who has never read a hexagram
## can still act on, which is why it is the default and telemetry is the option.
##
## WHICH LINE IS MOVING is the difference between where the body stands and
## where the altar is pointing -- the LOWEST line of `earth ^ body`, because
## that is the line the fire turns next. With nothing between them the last
## flip the store recorded still has something to say, and with neither the
## sentence honestly says the day is holding.
func day_line() -> String:
	var i: int = moving_line()
	if i < 0:
		return "Day %d · holding" % day_count()
	return "Day %d · %s %s" % [day_count(), _line_name(i), _line_verb(i)]


## The line that is currently turning, 0..5, or -1 when nothing is.
func moving_line() -> int:
	var diff: int = (_earth_bits() ^ _body_bits()) & 63
	for b in range(6):
		if ((diff >> b) & 1) == 1:
			return b
	if _store != null and ("last_flip" in _store):
		var f: Dictionary = _store.last_flip
		if int(f.get("when", 0)) > 0:
			return clampi(int(f.get("line", 0)), 0, 5)
	return -1


## Whether that line is opening into yang or closing into yin. The altar is the
## one being asked for, so the altar's own bit is the answer; with no altar to
## differ from, the last flip's direction stands.
func _line_verb(i: int) -> String:
	var diff: int = (_earth_bits() ^ _body_bits()) & 63
	if ((diff >> i) & 1) == 1:
		return "opens" if ((_earth_bits() >> i) & 1) == 1 else "closes"
	if _store != null and ("last_flip" in _store):
		return "opens" if bool((_store.last_flip as Dictionary).get("to_yang", false)) else "closes"
	return "closes"


## One of Pacing's six names, read off Pacing when it is on disk and off the
## dial's own copy when it is not.
func _line_name(i: int) -> String:
	var idx: int = clampi(i, 0, 5)
	if _pacing != null:
		if _pacing_consts.is_empty():
			_pacing_consts = _pacing.get_script_constant_map()
		var names: Array = _pacing_consts.get("LINE_NAMES", []) as Array
		if idx < names.size():
			return String(names[idx])
	return EarthLinesDial.LINE_NAMES[idx]


## WHICH DAY THIS IS, counted off the pacing journal rather than a calendar the
## app does not keep: the number of distinct days the journal's own clock has
## entries on, and never less than one, because a body that has run at all has
## run for a day.
func day_count() -> int:
	var j: Array = _journal()
	if j.is_empty():
		return 1
	var seen: Dictionary = {}
	for e in j:
		seen[int(int((e as Dictionary).get("t_ms", 0)) / DAY_MS)] = true
	return maxi(1, seen.size())


## The pacing journal, when Alchemy is bound and carrying one.
func _journal() -> Array:
	if _alchemy == null or not ("pacing" in _alchemy) or _alchemy.pacing == null:
		return []
	return _alchemy.pacing.journal as Array


## THE LAST TWELVE THINGS THE FIRE DID, one per line. This is what the status
## strip opens into: the sentence is the day, and this is the day's working.
func journal_text() -> String:
	var lines: Array[String] = (["DAY %d · JOURNAL" % day_count()] as Array[String])
	var j: Array = _journal()
	if j.is_empty():
		lines.append("the fire has not been lit")
		return "\n".join(lines)
	var from: int = maxi(0, j.size() - JOURNAL_TAIL)
	for k in range(from, j.size()):
		var e: Dictionary = j[k] as Dictionary
		var op: String = String(e.get("op", ""))
		var row: String = "%8d %-6s %s" % [
			int(e.get("t_ms", 0)), op, _figure_word(int(e.get("bits_after", 0)))]
		if op == "flip":
			row += "  L%d %s" % [
				int(e.get("line", 0)) + 1,
				"yang" if bool(e.get("to_yang", false)) else "yin"]
		lines.append(row)
	return "\n".join(lines)


## A finger on the strip opens the journal behind it.
func _on_status_input(event: InputEvent) -> void:
	if not GlassBubble._is_release(event):
		return
	status_panel.accept_event()
	bubble.open_large(journal_text(), _hub_point(status_panel))


# -- the dwell ---------------------------------------------------------------

## HOW FULL THE CIVIL FIRE IS, 0..1: the stillness the senses are reporting over
## the seconds of it Pacing wants. Pacing's own live number is used when Alchemy
## is bound -- a person moving the slider in the dashboard must see the ring
## fill faster -- and the const stands in when it is not.
func dwell_fraction() -> float:
	var span: float = civil_fire_s()
	if span <= 0.0 or _senses == null or not _senses.has_method("stillness"):
		return 0.0
	return clampf(float(_senses.stillness()) / span, 0.0, 1.0)


## The seconds of stillness the civil fire wants, live from Pacing when it is
## bound and from the const when it is not.
func civil_fire_s() -> float:
	if _alchemy != null and ("pacing" in _alchemy) and _alchemy.pacing != null:
		return float(_alchemy.pacing.civil_fire_s)
	return _threshold("CIVIL_FIRE_THRESHOLD", CIVIL_FIRE_THRESHOLD)


## The excitation at which the martial fire takes the ring's colour.
func martial_threshold() -> float:
	if _alchemy != null and ("pacing" in _alchemy) and _alchemy.pacing != null:
		return float(_alchemy.pacing.martial_threshold)
	return _threshold("MARTIAL_THRESHOLD", MARTIAL_THRESHOLD)


## Whether the martial fire is the one burning right now.
func martial_now() -> bool:
	if _senses == null or not _senses.has_method("excitation"):
		return false
	return float(_senses.excitation()) >= martial_threshold()


## The line that is flashing, 0..5, or -1. The overlay reads this and nothing
## else, so the flash has exactly one clock.
func flash_line() -> int:
	if _flash_line < 0 or Time.get_ticks_msec() >= _flash_until_ms:
		return -1
	return _flash_line


## WHETHER SOMEBODY ELSE IS STANDING WHERE WE ARE. Minimal on purpose: one pass
## over the room the mesh reports, looking for a head on our own bits.
func room_echo() -> bool:
	if not _cfg_room_highlight or _wmn == null or not _wmn.has_method("peers"):
		return false
	var mine: int = _head_bits()
	for p in (_wmn.peers() as Array):
		if (int((p as Dictionary).get("bits", -1)) & 63) == mine:
			return true
	return false


## The two figures, marked with the owner's moon and sun.
func _figures_phrase() -> String:
	return "%s HEAD %s   %s BODY %s   %s EARTH %s" % [
		MOON, _figure_word(_head_bits()), SUN, _figure_word(_body_bits()), EARTH_ICON, _figure_word(_earth_bits())]


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
	## ASKED ONCE, NOT FOUR TIMES A SECOND. get_script_constant_map() builds a
	## fresh dictionary of every constant in Pacing on every call, and the strip
	## called it twice each time it composed itself; it was the most expensive
	## thing on the glass after the dials.
	if _pacing_consts.is_empty():
		_pacing_consts = _pacing.get_script_constant_map()
	return float(_pacing_consts.get(key, fallback))


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


## THE GEAR OPENS THE DASHBOARD. config_text() is still the words, and the
## telemetry tests still read them; the finger gets the gauges.
func _on_configure_pressed() -> void:
	toggle_dashboard()


## The dashboard, opened or shut. Returns whether it now stands.
func toggle_dashboard() -> bool:
	if dashboard == null:
		_build_dashboard()
	if dashboard == null:
		return false
	return bool(dashboard.toggle())


func dashboard_open() -> bool:
	return dashboard != null and bool(dashboard.is_open())


## Built once, the moment the glass is handed the core, and laid over
## everything else on the root -- above the radar pane, above the bands.
func _build_dashboard() -> void:
	if dashboard != null or root == null:
		return
	dashboard = HexyDashboard.new()
	root.add_child(dashboard)
	dashboard.set_host(self)
	dashboard.bind(_store, _mnn, _wmn, _senses, _alchemy, _qwen)
	if _addons != null:
		dashboard.set_addons(_addons)


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
	## WHAT THIS PHONE IS ALLOWED TO CARRY. The glass does not do the judging:
	## every row arrives with its own verdict, and a refused tier is shown with
	## the reason rather than hidden or silently offered.
	for t in _mnn.tiers():
		var row: Dictionary = t as Dictionary
		var mark: String = "ok" if bool(row.get("allowed", true)) else "--"
		var why: String = String(row.get("reason", ""))
		lines.append("%s %s %s%s" % [
			mark,
			String(row.get("id", "")),
			String(row.get("params", "")),
			("" if why == "" else "  (%s)" % why)])
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
func _on_body_ring_tapped(slot: int) -> void:
	_walk_body(slot, "tap")


func _walk_head(slot: int, why: String) -> void:
	var idx: int = posmod(slot, HuohoutuData.HEAD_SEQUENCE.size())
	var hex: Dictionary = HuohoutuData.get_head_hex(idx)
	var bits: int = int(hex.get("bits", 0))
	_write_head(bits, ([] as Array[int]), why, idx)
	var at: Vector2 = _hub_point(head)
	bubble.say("🌙 HEAD: %s" % _figure_word(bits), at)


## A WALK OF THE WHEEL, and it says so: the finger picked a seat, it did not
## throw coins, and the journal must be able to tell the two apart. Nothing is
## moving in a walk, so the moving mask is honestly zero.
func _walk_body(slot: int, _why: String) -> void:
	var idx: int = posmod(slot, HuohoutuData.BODY_SEQUENCE.size())
	var hex: Dictionary = HuohoutuData.get_body_hex(idx)
	var bits: int = int(hex.get("bits", 0))
	_write_body(bits, ([] as Array[int]), "wheel", idx, 0)
	var at: Vector2 = _hub_point(body)
	bubble.say("☀️ BODY: %s" % _figure_word(bits), at)


## The body is ANNOUNCED, never written: Alchemy alone writes it, so a walk of
## the wheel re-anchors the cube instead of being wiped by the next senses tick.
func _write_body(bits: int, throws: Array[int], why: String, slot: int, moving: int = 0) -> void:
	if body != null:
		body.set_body_slot(slot)
	if _store == null or not _store.has_method("note_seat"):
		return
	_store.note_seat(HexyStore.Seat.BODY, {
		"bits": bits,
		"moving": moving & 63,
		"throws": throws,
		"when": _now_ms(),
		"who": _who,
		"source": why,
		"seq_index": slot,
	})


## The coin throw, on the head only: six lines, thrown once, signed.
func _cast_head() -> void:
	var now: int = _now_ms()
	var cast: Dictionary = Cast.tap_cast(Cast.seed_of(now, _who, 0))
	var bits: int = int(cast.get("bits", 0)) & 63
	var throws: Array[int] = ([] as Array[int])
	for v in (cast.get("throws", []) as Array):
		throws.append(int(v))
	var id: int = int(HuohoutuData.get_by_bits(bits).get("id", 1))
	_write_head(bits, throws, "tap", HuohoutuData.find_head_index_by_id(id),
		int(cast.get("moving", 0)) & 63)


## The head is announced on the same bus as every other seat, so all three have
## one event shape; the store stays the head's writer and no cube is touched.
func _write_head(bits: int, throws: Array[int], why: String, slot: int, moving: int = 0) -> void:
	head.set_head_slot(slot)
	if _store == null or not _store.has_method("note_seat"):
		return
	_store.note_seat(HexyStore.Seat.HEAD, {
		"bits": bits,
		"moving": moving & 63,
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
	return "#%d %s" % [KingWen.number(bits), KingWen.name(bits)]


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
	var at: Vector2 = _hub_point(_earth_control())
	bubble.say("EARTH: %s" % _figure_word(bits), at)


func _cast_earth() -> void:
	var now: int = _now_ms()
	var cast: Dictionary = Cast.tap_cast(Cast.seed_of(now, _who, 0))
	var bits: int = int(cast.get("bits", 0)) & 63
	var throws: Array[int] = ([] as Array[int])
	for v in (cast.get("throws", []) as Array):
		throws.append(int(v))
	var id: int = int(HuohoutuData.get_by_bits(bits).get("id", 1))
	_write_earth(bits, throws, "tap", HuohoutuData.find_head_index_by_id(id),
		int(cast.get("moving", 0)) & 63)


## THE ALTAR WALKS THE HEAD'S WHEEL. `_cast_earth` and `_walk_earth` both seat
## it by `find_head_index_by_id`, so the seat is passed explicitly and the
## store never falls back to the BODY wheel to guess where the altar sits.
func _write_earth(bits: int, throws: Array[int], why: String, slot: int, moving: int = 0) -> void:
	if earth != null:
		earth.set_earth_slot(slot)
	if _store == null or not _store.has_method("note_seat"):
		return
	_store.note_seat(HexyStore.Seat.EARTH, {
		"bits": bits,
		"moving": moving & 63,
		"throws": throws,
		"when": _now_ms(),
		"who": _who,
		"source": why,
		"sig": "",
		"seq_index": slot,
	})
	# One arg on purpose: the earth is the altar, not the body, so this cast is
	# a reward only -- it must not be announced on the BODY seat for injection.
	if _store.has_method("note_cast"):
		_store.note_cast("cast_confirmed")
	## THE ROOM VOTES ON HEADS. The altar rides along as its own optional
	## field; it is never passed off as this hexy's head.
	if _wmn != null and _wmn.has_method("broadcast"):
		_wmn.broadcast(_head_dict(), _body_dict(), _earth_dict())


func _earth_bits() -> int:
	if _store != null and _store.has_method("earth_bits"):
		return int(_store.earth_bits())
	return earth.hex_bits if earth != null else 2


func _earth_dict() -> Dictionary:
	if _store != null and _store.get("earth") is Dictionary:
		return _store.earth as Dictionary
	return {}


## THE DWELL ARC AND THE FLASHING LINE, drawn on a Control of their own laid
## over the body band. It answers no finger and holds no state: every number it
## draws is asked of the hud on the frame it draws it, so there is exactly one
## copy of "how full is the fire" in this app and it is not in here.
class DwellRing extends Control:
	var _hud: Node = null

	func _init(h: Node) -> void:
		_hud = h
		name = "DwellRing"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if _hud == null or size.x < 8.0 or size.y < 8.0:
			return
		var mid: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.46 + 7.0
		var frac: float = float(_hud.call("dwell_fraction"))
		var hot: bool = bool(_hud.call("martial_now"))
		var col: Color = Hud3.COL_FIRE if hot else Hud3.COL_DWELL

		## The empty track first, so an arc at zero still says there is one.
		draw_arc(mid, r, 0.0, TAU, 96, Color(col, 0.14), 3.0, true)
		if frac > 0.001:
			## From twelve o'clock, clockwise, the way a thing that is filling
			## up reads.
			draw_arc(mid, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 96, col, 3.5, true)

		var line: int = int(_hud.call("flash_line"))
		if line >= 0:
			## SIX SPOKES, ONE PER LINE, line 1 at the bottom and climbing
			## counter-clockwise -- the same six the earth band names.
			var ang: float = PI * 0.5 - float(line) * (TAU / 6.0)
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(mid + dir * (r - 22.0), mid + dir * (r + 6.0), Hud3.COL_FLASH, 4.0)


## ONE MARK ON THE HEAD RIM when somebody else in the room is holding the same
## figure we are. Minimal by instruction and by taste: a second colour on the
## tick the head is already standing on, and nothing else.
class RoomMark extends Control:
	var _hud: Node = null

	func _init(h: Node) -> void:
		_hud = h
		name = "RoomMark"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if _hud == null or size.x < 8.0 or size.y < 8.0:
			return
		if not bool(_hud.call("room_echo")):
			return
		var dial: Control = _hud.get("head")
		if dial == null:
			return
		var mid: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.44
		var ang: float = float(dial.get("dial_angle")) + float(int(dial.call("head_slot"))) * (TAU / 64.0)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(mid + dir * (r * 0.86), mid + dir * (r * 1.06), Hud3.COL_ROOM, 3.0)


class AxisSpine extends Control:
	var _hud: Node = null
	func _init(h: Node) -> void:
		_hud = h
		name = "AxisSpine"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		return
		if _hud == null:
			return
		var st: Control = _hud.get("status_panel")
		var hd: Control = _hud.get("head")
		var bd: Control = _hud.get("body_band")
		var et: Control = _hud.get("earth")
		var cp: Control = _hud.get("composer")
		if st == null or hd == null or bd == null or et == null or cp == null:
			return

		var cx: float = size.x * 0.5
		var col_glow := Color(0.12, 0.65, 0.95, 0.28)
		var col_line := Color(0.25, 0.80, 1.0, 0.65)
		var col_pip := Color(1.0, 0.85, 0.35, 0.95)

		# Pairs of (upper_bottom_y, lower_top_y) representing the meridian gaps
		# | [status] | (head) | (body) | (earth) | [chat] |
		var gaps: Array = [
			[0.0, st.position.y],
			[st.position.y + st.size.y, hd.position.y],
			[hd.position.y + hd.size.y, bd.position.y],
			[bd.position.y + bd.size.y, et.position.y],
			[et.position.y + et.size.y, cp.position.y],
			[cp.position.y + cp.size.y, size.y]
		]

		for g in gaps:
			var y0: float = float(g[0])
			var y1: float = float(g[1])
			if y1 > y0 + 2.0:
				draw_line(Vector2(cx, y0), Vector2(cx, y1), col_glow, 4.0)
				draw_line(Vector2(cx, y0), Vector2(cx, y1), col_line, 1.8)
				var mid_y: float = (y0 + y1) * 0.5
				var pip_h: float = minf(4.0, (y1 - y0) * 0.25)
				var pip_w: float = 3.0
				var pts: PackedVector2Array = [
					Vector2(cx, mid_y - pip_h),
					Vector2(cx + pip_w, mid_y),
					Vector2(cx, mid_y + pip_h),
					Vector2(cx - pip_w, mid_y)
				]
				draw_colored_polygon(pts, col_pip)
