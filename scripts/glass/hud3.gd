class_name Hud3
extends Node

## THE DIALS PAGE: THREE DIALS, ONE VOICE, AND A WAY BACK.
##
## This used to be the whole surface -- a status strip, a radar, a composer and
## the three dials all at once. It is a PAGE now. `scripts/glass/front.gd` is
## what a person carries; this is what they open when they want to READ the
## machine, and it is opened from the front and closed back to it. Everything
## the front already owns has been taken out of here: the sentence, the one
## room, the mic and the field, the compass. What is left is the part the front
## has no room for.
##
## Top to bottom there are four things and no more: a slim BACK BAR, the HEAD
## dial, the BODY dial with the creature standing inside it, and the EARTH
## dial. Each dial carries one CAPTION under it saying which figure it is
## holding, which is the one sentence the strip above them used to say.
##
## THE BANDS ARE ANCHORED, NOT MEASURED. They live in a box that fills the
## glass, the small ones with a fixed height and the body free to take what is
## left. That is why nothing overlaps at 1080x2408 and nothing overlaps at
## 1812x2176: no band is ever told a pixel size, only its share.
##
## THE THREE DIALS SPEAK THE SAME LANGUAGE. Same rim, same sixty-four ticks,
## same diamonds, same colours: cyan is the machine, gold is the human, orange
## is the Huohoutu, green is enhanced.
##
## TAP, AND TWO DRAGS. Every act is one visible target touched once, except the
## two joysticks: a finger dragged round the HEAD ring steers the fly's goal
## heading, and a finger dragged round the EARTH ring scrubs the day. Both end
## where they always did -- the release is still the tap.
##
## THE WAY OUT IS ALWAYS THERE. The bar closes the page, a swipe down anywhere
## that is not a dial closes the page, and Android's own back button closes the
## page. All three come out of the one `closed` signal the front listens to.

## THE PAGE IS SHUT. Whoever put this page on the glass hears this and takes
## it off again; the page never removes itself, because it does not own where
## it stands.
signal closed

## THE HEAD JOYSTICK. A finger dragged round the head ring says where round the
## allocentric circle it is pointing, in radians, 0..TAU. The fly's own goal
## heading is set from it when there is a fly to set; the signal is raised
## either way, so a listener never has to know whether a brain was attached.
signal head_steered(angle_rad: float)

## THE EARTH SCRUB. Where round the earth ring the finger is, as a share of the
## day, 0..1, raised every frame the finger is held and moving. Nothing in base
## consumes it yet; it is the hook a day-scrubber lands on.
signal earth_scrubbed(day_phase: float)
## And the finger came up again.
signal earth_released

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
## The back bar's height, and the caption under each dial's.
const BACK_H: float = 40.0
const CAPTION_H: float = 22.0

const HEAD_H: float = 270.0
const EARTH_H: float = 270.0
const BAND_GAP: int = 16
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

const MARTIAL_THRESHOLD: float = 0.85

## THE SIX DRAWER KEYS THIS GLASS OBEYS. Every one of them is pulled once at
## boot and again the moment the drawer says it moved, so a person turning a
## switch in the dashboard sees the glass change under their finger rather than
## on the next restart.
const KEY_DWELL_RING: String = "hud.dwell_ring"
const KEY_LINE_FLASH: String = "hud.line_flash"
const KEY_EARTH_MODE: String = "hud.earth_mode"
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

## How far DOWN a finger has to travel off the glass before the page closes.
## The same eighty pixels the front uses for its own swipe, so the gesture that
## opens a page and the gesture that shuts one are mirror images.
const SWIPE_PX: float = 80.0

## THE RING A JOYSTICK ANSWERS IN, as a share of the dial's own radius. Inside
## the inner bound is the hub and the stations, which are taps and stay taps;
## past the outer bound is the band's own margin.
const RING_INNER: float = 0.55
const RING_OUTER: float = 1.35

var _pacing_consts: Dictionary = {}

## The live answers to the six keys, cached so `_process` reads a bool and not
## a dictionary sixty times a second.
var _cfg_dwell_ring: bool = true
var _cfg_line_flash: bool = true
var _cfg_earth_mode: String = "lines"
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

## THE WAY BACK, and the full-glass sheet under the bands that hears a swipe.
## The sheet is added to the root BEFORE the pad, so every dial and every panel
## is picked ahead of it and it only ever hears a finger that touched nothing.
var back_bar: PanelContainer = null
var gestures: Control = null

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
var tiller_ghost: Control = null

## ONE CAPTION UNDER EACH DIAL: the figure that dial is holding, said the way
## the strip above them used to say all three at once.
var head_cap: Label = null
var body_cap: Label = null
var earth_cap: Label = null

var pad: MarginContainer = null

var stage: SubViewportContainer = null
var view: SubViewport = null
var creature_field: Control = null

var bubble: GlassBubble = null

## THE GEAR'S OWN PANEL: the whole base app drawn as gauges, hidden until the
## configure button is pressed. It is a sibling laid OVER the bands, never one
## of them, so the three dials measure the same whether it stands or not.
var dashboard: HexyDashboard = null

## The add-on loader, held only to hand on to the doors panel.
var _addons: Node = null

## WHOEVER STANDS THE ONE RADAR. Set by the front when it builds this page, so
## the gear opened from here borrows the front's own creature instead of
## growing a second one underneath the dials.
var _radar_lender: Object = null

var _store: Node = null
var _qwen: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
var _creature: Node = null
## W8e -- THE BUS AND THE GAUGE. The dials page is the ONE page that
## publishes, and it publishes a Sense (a finger on the head ring says a
## heading), never a state. Everything else here is a read of the gauge.
var _topic: RefCounted = null
var _body_sub: int = -1
var _gauge: RefCounted = null

## THE ORGANISM'S OWN BODY MESSAGE, as the bus last carried it. The BODY dial
## reads its bits from here (the front does the same) and falls back to the
## store only when no bus has spoken; the HEAD ring reads its heading to find
## out whether the brain has actually followed the tiller.
var _body: Dictionary = {}

## WHAT THE FINGER LAST ASKED THE HEAD FOR, in radians, and whether it has ever
## asked. A request is not a heading: the brain may refuse it or lag behind it,
## and this page has no right to pretend otherwise.
var _tiller_rad: float = 0.0
var _tiller_asked: bool = false

## HOW FAR APART REQUEST AND REALITY MAY STAND before the refusal is drawn.
## Ten degrees: closer than that and a ghost pointer would be noise.
const TILLER_SLACK_RAD: float = 0.174532925
var _who: String = "hexy"
var _stream: String = ""
var _enhanced: bool = true
## Whether this glass asked the question whose answer is coming. An answer the
## model produced on its own is written to the store all the same, but it does
## not throw a panel over the head dial at boot: the bubble is a REPLY.
var _awaiting: bool = false
var _pacing: Script = null

## The two joysticks, and where a swipe went down. INF is nothing held.
var _head_steering: bool = false
var _earth_scrubbing: bool = false
## Whether the finger actually TRAVELLED round the ring. A press that never
## moved is a tap and must reach the dial; only a real scrub is swallowed.
var _earth_scrubbed_any: bool = false
var _swipe_from: float = INF

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

	_build_back_bar()
	_build_head()
	_build_body()
	_build_earth()
	_build_gestures()
	_refresh_captions()

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
	_refresh_captions()


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
	## THE JOYSTICK LISTENS BESIDE THE DIAL, NOT INSIDE IT. Every Control emits
	## `gui_input` for the same events its own `_gui_input` is handed, so the
	## drag is read here without one line changing in MandalaDialTap -- and the
	## dial's own tap, walk and snap all still happen exactly as before.
	head.gui_input.connect(_on_head_gesture)

	room_mark = RoomMark.new(self)
	head.add_child(room_mark)

	tiller_ghost = TillerGhost.new(self)
	head.add_child(tiller_ghost)

	head_cap = _build_caption("HeadCaption")


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
	body_cap = _build_caption("BodyCaption")
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
	## BOTH FACES ARE SCRUBBED THE SAME WAY, and neither of them knows it.
	earth.gui_input.connect(_on_earth_gesture)
	earth_lines.gui_input.connect(_on_earth_gesture)

	earth_cap = _build_caption("EarthCaption")
	_apply_earth_mode()


# -- the way out, the captions and the two joysticks -------------------------

## THE BACK BAR: the first band, and the only chrome on the page. One word and
## an arrow, because the page it goes back to has a name and a person knows it.
func _build_back_bar() -> void:
	back_bar = PanelContainer.new()
	back_bar.name = "BackBar"
	back_bar.custom_minimum_size = Vector2(0.0, BACK_H)
	back_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	back_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	back_bar.add_theme_stylebox_override("panel", SKIN.skin())
	back_bar.gui_input.connect(_on_back_input)
	bands.add_child(back_bar)

	var lab := Label.new()
	lab.name = "Back"
	lab.text = "\u2190 front"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 15)
	lab.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98, 1.0))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_bar.add_child(lab)


## ONE CAPTION, BUILT AND PARKED IN THE BAND ORDER. It is a band of its own
## rather than a child of the dial, so the dial's rect stays the dial's rect
## and the three bands can still be measured against each other.
func _build_caption(node_name: String) -> Label:
	var lab := Label.new()
	lab.name = node_name
	lab.custom_minimum_size = Vector2(0.0, CAPTION_H)
	lab.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98, 1.0))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_child(lab)
	return lab


## THE SHEET THAT HEARS A SWIPE. Full glass, STOP, and third in the root so
## every dial and every panel is picked ahead of it: it only ever hears a
## finger that landed on nothing, which is exactly what "outside the dials"
## means without this file having to measure a single rect.
func _build_gestures() -> void:
	gestures = Control.new()
	gestures.name = "Gestures"
	gestures.set_anchors_preset(Control.PRESET_FULL_RECT)
	gestures.mouse_filter = Control.MOUSE_FILTER_STOP
	gestures.gui_input.connect(_on_sheet_input)
	root.add_child(gestures)
	root.move_child(gestures, 2)


## The three captions, one figure each, marked the way the strip marked them.
func _refresh_captions() -> void:
	if head_cap != null:
		head_cap.text = "%s HEAD %s" % [MOON, _figure_word(_head_bits())]
	if body_cap != null:
		body_cap.text = "%s BODY %s" % [SUN, _figure_word(_body_bits())]
	if earth_cap != null:
		earth_cap.text = "%s EARTH %s" % [EARTH_ICON, _figure_word(_earth_bits())]


## The three figures in one line, which is what the captions say between them.
func figures_phrase() -> String:
	return _figures_phrase()


## THE PAGE IS PUT UP. Whoever owns the layer may also show it themselves; this
## is the same act said in one word, so a caller does not have to know that a
## CanvasLayer is what a page is made of.
func open() -> void:
	if layer != null:
		layer.visible = true


## AND TAKEN DOWN. The page hides itself and SAYS SO, and it is the saying that
## matters: the front owns the composer and its own room and has to know they
## may come back. Closing a page that is already down is not an error -- the
## back button is allowed to be pressed twice.
func close() -> void:
	if layer != null:
		layer.visible = false
	_head_steering = false
	_earth_scrubbing = false
	_earth_scrubbed_any = false
	_swipe_from = INF
	closed.emit()


## Whether the page is standing.
func is_open() -> bool:
	return layer != null and layer.visible


## ANDROID'S OWN BACK BUTTON shuts the page, which is the only thing back can
## mean on a page that was opened from somewhere.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		close()


## A tap anywhere on the bar goes back.
func _on_back_input(event: InputEvent) -> void:
	if not _is_release(event):
		return
	back_bar.accept_event()
	close()


## A DRAG DOWN OFF THE GLASS GOES BACK TOO. Eighty pixels, the same distance
## the front asks for upward, and nothing shorter: a tap on the ground between
## two dials must not throw the page away.
func _on_sheet_input(event: InputEvent) -> void:
	var down: Variant = _press_at(event)
	if down != null:
		_swipe_from = (down as Vector2).y
		return
	var up: Variant = _release_at(event)
	if up == null:
		return
	var travel: float = (up as Vector2).y - _swipe_from
	_swipe_from = INF
	if travel >= SWIPE_PX:
		gestures.accept_event()
		close()


## THE HEAD JOYSTICK. Down on the ring arms it, every motion while it is armed
## says the angle the finger is standing at, and the release disarms it and
## leaves the dial's own tap to do what it has always done.
func _on_head_gesture(event: InputEvent) -> void:
	if head == null:
		return
	var mid: Vector2 = head.size * 0.5
	var r: float = minf(head.size.x, head.size.y) * 0.44
	var down: Variant = _press_at(event)
	if down != null:
		var d: float = (down as Vector2).distance_to(mid)
		_head_steering = r > 1.0 and d >= r * RING_INNER and d <= r * RING_OUTER
		return
	if _release_at(event) != null:
		_head_steering = false
		return
	var moved: Variant = _drag_at(event)
	if moved == null or not _head_steering:
		return
	steer_head(fposmod(((moved as Vector2) - mid).angle(), TAU))


## WHERE THE HEAD IS POINTED, SAID ONCE AND PUBLISHED ONCE.
##
## W8e -- THE ONE PLACE THE GLASS PUBLISHES, AND IT PUBLISHES A SENSE. The
## tiller used to reach through the store into the organism and write the
## fan-shaped body's goal vector, which made a dial a writer of brain state.
## It no longer does: the drag becomes a tarsi Sense at door "head_tiller",
## published on "/sense" -- the bus fans every Sense carrying a door out to
## "/sense/<door>" of its own accord, so a subscriber may listen to
## "/sense/head_tiller" alone -- and the organism decides what a finger on a
## ring is worth. The signal is still always raised, bus or no bus.
const DOOR_HEAD_TILLER: String = "head_tiller"

func steer_head(angle_rad: float) -> void:
	var a: float = fposmod(angle_rad, TAU)
	_tiller_rad = a
	_tiller_asked = true
	head_steered.emit(a)
	if _topic == null:
		return
	_topic.publish(HexyTopic.TOPIC_SENSE, HexyMsg.sense("tarsi", DOOR_HEAD_TILLER,
		Time.get_ticks_usec() * 1000, a, {}))


## THE EARTH SCRUB. The same shape as the head's, saying a share of the day
## rather than an angle, because the earth ring is the year and not a compass.
func _on_earth_gesture(event: InputEvent) -> void:
	var dial: Control = _earth_control()
	if dial == null:
		return
	var mid: Vector2 = dial.size * 0.5
	var r: float = minf(dial.size.x, dial.size.y) * 0.44
	var down: Variant = _press_at(event)
	if down != null:
		var d: float = (down as Vector2).distance_to(mid)
		_earth_scrubbing = r > 1.0 and d >= r * RING_INNER and d <= r * RING_OUTER
		_earth_scrubbed_any = false
		return
	if _release_at(event) != null:
		if _earth_scrubbing:
			var dragged: bool = _earth_scrubbed_any
			_earth_scrubbing = false
			_earth_scrubbed_any = false
			earth_released.emit()
			## A SCRUB SNAPS BACK. The dial's own `_gui_input` would read this
			## release as a TAP -- writing the earth and leaving a balloon up --
			## which would turn a preview into a sample and is exactly the thing
			## a scrub must not do. Godot emits `gui_input` BEFORE the virtual,
			## so consuming it here is what keeps the ring a question. The page
			## is then put back to now: the balloon is dismissed and the three
			## captions are re-read off the store.
			if dragged:
				dial.accept_event()
				if bubble != null:
					bubble.close()
				_refresh_earth_lines()
				_refresh_captions()
		return
	var moved: Variant = _drag_at(event)
	if moved == null or not _earth_scrubbing:
		return
	_earth_scrubbed_any = true
	earth_scrubbed.emit(day_phase_of(((moved as Vector2) - mid).angle()))


## AN ANGLE ROUND THE EARTH RING, AS A SHARE OF THE DAY. Midnight is straight
## up and the day runs clockwise, which is the way every dial on this glass
## already reads.
static func day_phase_of(angle_rad: float) -> float:
	return clampf(fposmod(angle_rad + PI * 0.5, TAU) / TAU, 0.0, 1.0)


## WHAT THE SCRUBBED HOUR IS CALLED. A PREVIEW AND NOTHING ELSE: the gauge is
## asked what band and what word that hour falls in, and nothing is written --
## a scrub is a question, not an observation. "" with no gauge to ask.
func scrub_caption(day_phase: float) -> String:
	if _gauge == null:
		return ""
	var band: String = String(_gauge.call("phase_of_frac", day_phase))
	var word: String = String(_gauge.call("day_word", band))
	return "%02d:%02d %s" % [
		int(clampf(day_phase, 0.0, 1.0) * 24.0),
		int(fposmod(clampf(day_phase, 0.0, 1.0) * 24.0, 1.0) * 60.0), word]


## Where a finger went down, or null if this event is not a press.
static func _press_at(event: InputEvent) -> Variant:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			return mb.position
	return null


## Where a finger came up, or null.
static func _release_at(event: InputEvent) -> Variant:
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			return mb.position
	return null


## Where a finger that is still down has moved to, or null.
static func _drag_at(event: InputEvent) -> Variant:
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	return null


static func _is_release(event: InputEvent) -> bool:
	return _release_at(event) != null


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


## THE ADD-ON LOADER, passed straight through to the doors panel. The glass
## itself has no opinion about add-ons; it only knows where the panel is.
func set_addons(addons: Node) -> void:
	_addons = addons
	if dashboard != null:
		dashboard.set_addons(addons)


## THE BROKER, passed straight through to the doors panel the same way. This
## page has no opinion about who holds a door either; it only knows where the
## panel that shows it is.
var _broker: Node = null


func set_broker(b: Node) -> void:
	_broker = b
	if dashboard != null and dashboard.has_method("set_broker"):
		dashboard.set_broker(b)


## THE BUS AND THE GAUGE, handed down from the app through the front. The
## topic is used for exactly one publish (see [method steer_head]); the gauge
## is read and never written.
func set_bus(topic: RefCounted, gauge: RefCounted) -> void:
	if _topic != null and _body_sub >= 0:
		_topic.unsubscribe(_body_sub)
	_body_sub = -1
	_topic = topic
	_gauge = gauge
	if _topic != null:
		_body_sub = int(_topic.subscribe(HexyTopic.TOPIC_BODY, Callable(self, "_on_body_msg")))
		## A LATCHED BODY IS STILL A BODY -- a page opened after the organism
		## has already spoken stands on what is live, not on an empty room.
		var latched: Dictionary = _topic.last(HexyTopic.TOPIC_BODY)
		if not latched.is_empty():
			_on_body_msg(latched)
	if dashboard != null and dashboard.has_method("set_bus"):
		dashboard.set_bus(topic, gauge)


## THE BODY, OFF THE BUS, KEPT WHOLE. No writes follow from it: the dials are
## redrawn from it on the next refresh, exactly as they were from the store.
func _on_body_msg(msg: Dictionary) -> void:
	if typeof(msg) != TYPE_DICTIONARY or String(msg.get("kind", "")) != "body":
		return
	_body = msg.duplicate(true)
	if body != null:
		body.set_body_bits(_body_bits())


## ---- THE TILLER'S REFUSAL, MADE VISIBLE --------------------------------
##
## W10c -- the head ring is a REQUEST, not a command. `steer_head` publishes a
## tarsi Sense and the organism decides what a finger on a ring is worth: it
## may refuse it outright or take its time getting there. Until now the glass
## drew only the request, so a refusal looked exactly like a success.
##
## Now there are two pointers while they disagree: the solid one at the
## heading the brain actually reports on "/body", and a faint ghost at the
## angle the finger asked for. When the brain follows, the ghost merges into
## the pointer and there is one again. No new button, no new gesture.

## WHERE THE FINGER LAST ASKED THE HEAD TO POINT, in radians.
func tiller_heading() -> float:
	return _tiller_rad


## WHERE THE BODY ACTUALLY POINTS, as the bus last said. Zero with no bus.
func body_heading() -> float:
	return fposmod(float(_body.get("heading_rad", 0.0)), TAU)


## THE SHORTEST ANGLE BETWEEN THE TWO, always 0..PI.
func tiller_gap_rad() -> float:
	if not _tiller_asked:
		return 0.0
	return absf(angle_difference(body_heading(), tiller_heading()))


## TRUE WHILE THE REQUEST AND THE REAL HEADING STAND MORE THAN
## [constant TILLER_SLACK_RAD] apart -- which is exactly when the ghost is drawn.
func tiller_refused() -> bool:
	return _tiller_asked and tiller_gap_rad() > TILLER_SLACK_RAD


func gauge() -> RefCounted:
	return _gauge


## THE ONE RADAR'S OWNER, handed in by whoever mounted this page (the front).
## Read only when the dashboard is built, so the gear's panel borrows that
## instance instead of the copy this page used to carry.
func set_radar_lender(lender: Object) -> void:
	_radar_lender = lender


# -- what the glass is asked for ---------------------------------------------

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
			var peers: int = mesh_peers()
			var word: String = "mesh beacon: solo mode"
			if peers >= 0:
				word = "mesh: %d peers" % peers
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


## WHO IS IN THE ROOM. W10c -- this station used to push both figures onto the
## wire itself, which made a page a writer of the mesh. It no longer does: Wmn
## already follows the store's own `hexagram_changed` and `head_changed`, so a
## figure is on the air the moment it moves and a button that says so again is
## a second writer for nothing. What is left is the reading: the peer count, or
## -1 when there is no mesh at all to count.
func mesh_peers() -> int:
	if _wmn == null or not _wmn.has_method("peer_count"):
		return -1
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
		return _hub_point(head)
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
	return _hub_point(head)


func _on_token(t: String) -> void:
	_stream += t
	if _awaiting:
		bubble.stream(_stream)


# -- refreshing --------------------------------------------------------------

func _process(_delta: float) -> void:
	_feed_breath()


## THE CREATURE BREATHES WITH THE DWELL, when the drawer says it may. One float
## a frame, pushed rather than pulled, so the creature stays a thing that knows
## nothing about senses or pacing.
func _feed_breath() -> void:
	if not _cfg_breathe or _creature == null or not _creature.has_method("set_breath_rate"):
		return
	_creature.set_breath_rate(dwell_fraction())


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
	cam.position = Vector3(0.0, -drop_px * world_per_px, z)


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


# -- the day ---------------------------------------------------------------

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


## THE JOURNAL. W8e removed the core object that kept one: nothing on the
## glass holds a writer of organism state any more, so there is no per-flip
## journal to read and this answers an honest empty array. The strip below
## says so in words rather than drawing a blank block.
func _journal() -> Array:
	return []


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


# -- the dwell ---------------------------------------------------------------

## HOW FULL THE CIVIL FIRE IS, 0..1: the stillness the senses are reporting over
## the seconds of it Pacing wants -- so a person moving that slider in the
## dashboard sees the ring fill faster -- and the const stands in when there
## is no Pacing to ask.
func dwell_fraction() -> float:
	var span: float = civil_fire_s()
	if span <= 0.0 or _senses == null or not _senses.has_method("stillness"):
		return 0.0
	return clampf(float(_senses.stillness()) / span, 0.0, 1.0)


## The seconds of stillness the civil fire wants, live from Pacing when it is
## bound and from the const when it is not.
func civil_fire_s() -> float:
	return _threshold("CIVIL_FIRE_THRESHOLD", CIVIL_FIRE_THRESHOLD)


## The excitation at which the martial fire takes the ring's colour.
func martial_threshold() -> float:
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


## The dashboard, opened or shut. Returns whether it now stands.
func toggle_dashboard() -> bool:
	return bool(dashboard_page().toggle()) if dashboard_page() != null else false


## THE DASHBOARD, BUILT THE FIRST TIME SOMEBODY ASKS FOR IT AND NOT AT BIND.
## It carries a calcium radar of its own, and the front already stands one in
## the room; building it at bind would have put a second radar in the tree the
## moment a finger opened the dials, which is exactly the thing this page was
## taken apart to stop. Asked for, it is built, hidden, and returned.
func dashboard_page() -> HexyDashboard:
	if dashboard == null:
		_build_dashboard()
	return dashboard


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
	dashboard.bind(_store, _mnn, _wmn, _senses, null, _qwen)
	if dashboard.has_method("set_bus"):
		dashboard.set_bus(_topic, _gauge)
	if _addons != null:
		dashboard.set_addons(_addons)
	if _broker != null and dashboard.has_method("set_broker"):
		dashboard.set_broker(_broker)
	## BORROW THE ONE RADAR, if somebody is standing one. Without a lender
	## (this page built on its own, as the standalone dashboard test still
	## does) the panel keeps the radar it just built for itself.
	if _radar_lender != null and _radar_lender.has_method("radar_dial"):
		var lent: Control = _radar_lender.radar_dial() as Control
		if lent != null and dashboard.has_method("borrow_radar"):
			dashboard.borrow_radar(lent)


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


## THE BODY'S BITS, OFF THE BUS FIRST. W10c -- the BODY dial reads the
## organism's own Body message, exactly as the front does, and falls back to
## the store only when nothing has ever spoken on "/body".
func _body_bits() -> int:
	if not _body.is_empty():
		return int(_body.get("bits", 0)) & 63
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


## The body is ANNOUNCED, never written: the seat bus carries the walk and the
## organism decides what the body actually stands on, so a walk of the wheel
## is a statement rather than a write the next tick wipes.
func _write_body(bits: int, throws: Array[int], why: String, slot: int, moving: int = 0) -> void:
	if body != null:
		body.set_body_slot(slot)
	_say_seat(HexyStore.Seat.BODY, {
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
	_say_seat(HexyStore.Seat.HEAD, {
		"bits": bits,
		"moving": moving & 63,
		"throws": throws,
		"when": _now_ms(),
		"who": _who,
		"source": why,
		"sig": "",
		"seq_index": slot,
	})


## ---- THE ONE WAY THIS PAGE SAYS A SEAT MOVED ------------------------------
##
## W10c -- THE DIALS PUBLISH A SENSE, NOT A STATE. A dial used to call
## `store.note_seat` (and, on the altar, `store.note_cast` and `wmn.broadcast`)
## straight, which made this page a writer of three seats at once. It no longer
## writes anything: the gesture becomes a tarsi Sense at door
## [constant DOOR_SEAT], published on "/sense" -- the bus fans a Sense with a
## door out to "/sense/<door>" of its own accord -- and the store, which is the
## one writer of seat state, subscribes there and applies it. `cast` names the
## note_cast kind a throw also deserves and is "" for a plain walk.
##
## Returns true when the Sense went out on a bus. With no bus there is nothing
## to say it on, and the glass stays a thing that only looks.
const DOOR_SEAT: String = "earth_seat"

func _say_seat(seat: int, figure: Dictionary, cast_kind: String = "") -> bool:
	if _topic == null:
		return false
	var value: Dictionary = figure.duplicate(true)
	value["seat"] = seat
	value["cast"] = cast_kind
	return bool(_topic.publish(HexyTopic.TOPIC_SENSE, HexyMsg.sense("tarsi", DOOR_SEAT,
			Time.get_ticks_usec() * 1000, value, {"seat": seat, "source": String(figure.get("source", ""))})))



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
	## The reward rides in the value: the store applies the seat and then notes
	## the cast itself, with one arg, so the altar's throw is a reward only and
	## is never announced on the BODY seat for injection.
	##
	## THE ROOM VOTES ON HEADS, and it no longer does so from here: the store
	## emits `earth_changed` when the altar moves, and whoever owns the wire
	## listens to the store, not to a dial. (Wmn today connects hexagram_changed
	## and head_changed only -- see the W10c report.)
	_say_seat(HexyStore.Seat.EARTH, {
		"bits": bits,
		"moving": moving & 63,
		"throws": throws,
		"when": _now_ms(),
		"who": _who,
		"source": why,
		"sig": "",
		"seq_index": slot,
	}, "cast_confirmed")


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


## THE TILLER'S TWO POINTERS. A finger on the head ring ASKS for a heading; the
## organism answers on "/body" in its own time, or not at all. While the two
## stand more than [constant Hud3.TILLER_SLACK_RAD] apart this draws them both
## -- the solid needle where the body really points, a faint ghost where the
## finger asked -- so a refusal looks like a refusal instead of like a success.
## When the brain follows, the ghost merges into the needle and there is one
## pointer again. It answers no finger and holds no state of its own: every
## number it draws is asked of the hud on the frame it draws it.
class TillerGhost extends Control:
	var _hud: Node = null

	func _init(h: Node) -> void:
		_hud = h
		name = "TillerGhost"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if _hud == null or size.x < 8.0 or size.y < 8.0:
			return
		if not bool(_hud.call("tiller_refused")):
			return
		var mid: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.44
		var real: float = float(_hud.call("body_heading"))
		var asked: float = float(_hud.call("tiller_heading"))
		var real_dir := Vector2(cos(real), sin(real))
		var ask_dir := Vector2(cos(asked), sin(asked))
		## The ghost first, so the solid needle stands over it where they meet.
		draw_line(mid, mid + ask_dir * (r * 0.92), Color(Hud3.COL_DWELL, 0.30), 2.0, true)
		draw_circle(mid + ask_dir * (r * 0.92), 3.0, Color(Hud3.COL_DWELL, 0.30))
		draw_line(mid, mid + real_dir * (r * 0.92), Hud3.COL_DWELL, 3.0, true)
