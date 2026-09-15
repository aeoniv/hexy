class_name HexyDashboard
extends Control

## THE INSTRUMENT PANEL: the whole base app, drawn, on one scrolling column.
##
## The gear on the status strip used to open a bubble with seven lines of text
## in it. Text is what you write when you do not know what the number means;
## a gauge is what you draw when you do. This is every live number the base app
## has -- device, engine, figures, the sixteen, the two fires, the fly, the
## mesh -- as bars, arcs, lamps, hexagrams, a heat grid and a radar, readable
## at arm's length on a phone.
##
## IT KNOWS NOTHING IT WAS NOT HANDED. Store, mnn, wmn, senses, gauge and
## qwen arrive through bind() and are read DUCK-TYPED, exactly as the rest of
## the glass reads them. No path below the glass is named here, and no engine
## singleton is asked for anything.
##
## IT REDRAWS TEN TIMES A SECOND, NOT SIXTY. Every panel paints from one
## snapshot dictionary taken on a timer; between beats the panels are still
## pictures and cost the renderer nothing. The one exception is the fly radar,
## which is the creature's own FlyCalciumRadar2D and keeps its own clock.
##
## IT IS AN OVERLAY. Hidden at boot, hidden after close, and it never takes a
## pixel from the three dials underneath -- it is a sibling laid over them, so
## the bands measure the same whether it stands or not.

## The one skin, borrowed from the bubble so there is only one look.
const SKIN := preload("res://scripts/glass/bubble.gd")
## The one place a `hexy-xxxx` name is spelled, and the one place a heading in
## radians becomes a trigram glyph -- KingWen.heading_glyph carries the radar's
## wedge order, so the glass reads it without reaching into the brain.
const IdentityScript := preload("res://scripts/social/identity.gd")

## The seven panels, in the order they are read, top to bottom.
const PANELS: Array[String] = [
	"identity", "engine", "figures", "senses", "fires", "fly", "mesh",
]

const TITLES: Dictionary = {
	"identity": "1 · IDENTITY & DEVICE",
	"engine": "2 · ENGINE — MNN & QWEN",
	"figures": "3 · FIGURES — HEAD / BODY / EARTH",
	"senses": "4 · SIXTEEN SENSES — 8×8",
	"fires": "5 · FIRES & PACING",
	"fly": "6 · FLY ORGANISM",
	"mesh": "7 · MESH",
	"tunables": "8 · TUNABLES",
	"controls": "9 · CONTROLS",
	"doors": "10 · DOORS",
	"phase": "11 · PHASE — FOUR TIMESCALES",
}

## THE FOUR TIMESCALES, in the order they are stacked: the second the radar is
## painting, the day the user's own clock is in, the weeks of line_lean standing
## on the six lines, and the life the gauge's chapter rules put this figure in.
const PHASE_ROWS: Array[String] = ["seconds", "day", "weeks", "life"]

## Five heights of block, so a signed mark's magnitude reads as a bar without
## a single line of _draw.
const MARK_BLOCKS: Array[String] = ["▁", "▃", "▅", "▇", "█"]

## The two panels that are WIDGETS, not paintings. A gauge shows you a number;
## these two let you MOVE one, which no _draw can do. They stand on the same
## column, under the seven, and are built out of real Controls.
const WIDGET_PANELS: Array[String] = ["tunables", "controls", "doors", "phase"]

## The twelve app controls that used to live on the earth dial, in the order a
## thumb should meet them. `kind` says what the button does with what it gets
## back: "" throws it away, "text" writes it into the panel's readout, and
## "walk" hands the method its own `arg`.
const CONTROL_ROWS: Array[Dictionary] = [
	{"method": "toggle_enhanced", "label": "ENHANCED", "kind": "flag"},
	{"method": "cycle_geometry", "label": "GEOMETRY", "kind": "text"},
	{"method": "telemetry_text", "label": "TELEMETRY", "kind": "text"},
	{"method": "brain_text", "label": "BRAIN", "kind": "text"},
	{"method": "config_text", "label": "CONFIG", "kind": "text"},
	{"method": "cycle_sense_period", "label": "SENSE PERIOD", "kind": "flag"},
	{"method": "mesh_peers", "label": "PEERS", "kind": "flag"},
	{"method": "camera_reset", "label": "CAMERA RESET", "kind": ""},
	{"method": "toggle_sensor_freeze", "label": "FREEZE SENSORS", "kind": "flag"},
	{"method": "cast_earth", "label": "CAST EARTH", "kind": "flag"},
	{"method": "walk_earth", "label": "◀ PREV", "kind": "walk", "arg": -1},
	{"method": "walk_earth", "label": "NEXT ▶", "kind": "walk", "arg": 1},
]

const HEIGHTS: Dictionary = {
	"identity": 210.0,
	"engine": 150.0,
	"figures": 196.0,
	"senses": 330.0,
	"fires": 170.0,
	"fly": 210.0,
	"mesh": 240.0,
}

## How often the snapshot is taken and the panels repaint, in seconds.
const BEAT_S: float = 0.1

## How many frame-rate samples the sparkline holds.
const FPS_SAMPLES: int = 60

## The frame budget line drawn across the sparkline, in frames per second.
const BUDGET_FPS: float = 60.0

## The widest RAM the bar draws, in bytes, and the widest free storage.
const RAM_FULL: float = 16.0 * 1073741824.0
const STORAGE_FULL: float = 64.0 * 1073741824.0

## The palette, the same three voices the dials speak with.
const INK: Color = Color(0.82, 0.9, 0.97, 1.0)
const DIM: Color = Color(0.52, 0.62, 0.74, 1.0)
const MACHINE: Color = Color(0.35, 0.78, 0.95, 1.0)
const HUMAN: Color = Color(0.95, 0.78, 0.35, 1.0)
const FIRE: Color = Color(0.95, 0.52, 0.25, 1.0)
const GOOD: Color = Color(0.42, 0.88, 0.55, 1.0)
const BAD: Color = Color(0.90, 0.35, 0.40, 1.0)
const WIRE: Color = Color(0.2, 0.5, 0.8, 0.45)
const GROUND: Color = Color(0.0392157, 0.0588235, 0.0901961, 0.94)

## Where a file with the build id would be, if a build ever wrote one.
const BUILD_PATH: String = "res://BUILD"


## ONE PANEL'S GEOMETRY. It holds no state of its own: it paints whatever the
## dashboard's snapshot says, and counts its own paints so a test can prove it
## ran.
class Geom extends Control:
	var dash: Object = null
	var kind: String = ""
	var draws: int = 0

	func _draw() -> void:
		draws += 1
		if dash != null:
			dash.call("_paint_" + kind, self)


var backdrop: ColorRect = null
var column: VBoxContainer = null
var scroll: ScrollContainer = null
var close_button: Button = null
var build_label: Label = null
var radar: Control = null

## THE ONE RADAR RULE. `radar` above is this panel's own -- built at _ready
## exactly as before -- until somebody LENDS one with `borrow_radar()`, at
## which point it is swapped for the lent instance and the built one is freed,
## so the tree never carries two. `_fly_row` is the row `radar` (whichever one
## it is) stands beside its bars in; `_lender` is who to hand it back to.
var _fly_row: HBoxContainer = null
var _lender: Control = null
var _lent_from_parent: Node = null
var _lent_from_index: int = -1
var _using_borrowed: bool = false

var _store: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
## W8e -- THE GAUGE, READ AND NEVER WRITTEN. Every caption on this panel
## that used to come off a core object with an opinion (the pressure, the
## chapter, the day bands) now comes off the one gauge file.
var _gauge: RefCounted = null
## The broker, so panel 10 can say who is actually holding a door right now.
var _broker: Node = null
var _qwen: Node = null

## The compass the glass hands down, so the dashboard's radar turns north-up
## and can speak a guide line. Null is a legal state: headless has none.
var _heading: Node = null
## The glass that owns this panel, read only for the words it already holds
## (the node name, the token stream). Never written to.
var _host: Node = null

var _panels: Dictionary = {}
var _geoms: Dictionary = {}
var _beat: Timer = null
var _fps: PackedFloat32Array = PackedFloat32Array()
var _snap: Dictionary = {}

## key -> the one Control that edits it, and key -> the Label that reads it
## back. A panel that has to reflect an OUTSIDE write needs both.
var _tunable_controls: Dictionary = {}
var _tunable_labels: Dictionary = {}

## True while the panel is writing a control's value from the registry. Every
## signal handler leaves at once while this stands, which is the whole of the
## feedback-loop defence: a slider moved by code must not write back.
var _applying: bool = false

## method name -> the Button that calls it. `walk_earth` has two, so they are
## keyed by method plus the direction they walk.
var _control_buttons: Dictionary = {}
var _control_readout: RichTextLabel = null
var _config: HexyConfig = null

## The loader, if the app built one. Read-only, and duck-typed like everything
## else the glass is handed: a dashboard with no loader draws six dashes.
var _addons: Node = null

## line or circuit id -> the Label that names the doors feeding it.
var _door_labels: Dictionary = {}
## The one gauge line on panel 8 -- see [method _build_tunables].
var _gauge_label: Label = null

## The four timescale rows of panel 11, by key, and the last dictionary Front
## pushed into them.
var _phase_labels: Dictionary = {}
var _phase_snapshot: Dictionary = {}


# -- building ----------------------------------------------------------------

func _ready() -> void:
	name = "Dashboard"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = GROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	add_child(pad)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 8)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(stack)

	var head := Label.new()
	head.name = "Heading"
	head.text = "HEXY · LIVE DASHBOARD"
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", INK)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	stack.add_child(scroll)

	column = VBoxContainer.new()
	column.name = "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	for kind in PANELS:
		column.add_child(_build_panel(kind))
	for kind in WIDGET_PANELS:
		column.add_child(_build_panel(kind))

	stack.add_child(_build_footer())

	_beat = Timer.new()
	_beat.name = "Beat"
	_beat.wait_time = BEAT_S
	_beat.one_shot = false
	_beat.timeout.connect(_refresh)
	add_child(_beat)


func _build_panel(kind: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = kind.capitalize() + "Panel"
	panel.add_theme_stylebox_override("panel", SKIN.skin())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = String(TITLES.get(kind, kind.to_upper()))
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", DIM)
	box.add_child(title)

	var geom := Geom.new()
	geom.name = "Geom"
	geom.dash = self
	geom.kind = kind
	geom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	geom.custom_minimum_size = Vector2(0.0, float(HEIGHTS.get(kind, 140.0)))
	geom.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if kind == "tunables":
		_build_tunables(box)
		_panels[kind] = panel
		return panel
	if kind == "controls":
		_build_controls(box)
		_panels[kind] = panel
		return panel
	if kind == "doors":
		_build_doors(box)
		_panels[kind] = panel
		return panel
	if kind == "phase":
		_build_phase(box)
		_panels[kind] = panel
		return panel

	if kind == "fly":
		## The fly panel carries the creature's own radar beside its bars: the
		## one drawing on this surface that is allowed its own clock.
		var row := HBoxContainer.new()
		row.name = "Row"
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		radar = FlyCalciumRadar2D.new()
		radar.name = "DashRadar"
		## THE ONE RADAR A SLAB PHONE CAN REACH. On a fold the glass keeps a
		## column of its own for the dial; on a slab that pane is not drawn at
		## all, so THIS is the radar a person opens -- panel 6, on the one
		## scrolling column -- and it must answer a finger exactly as the
		## fold's does. STOP, not IGNORE: the tap is the whole point.
		radar.mouse_filter = Control.MOUSE_FILTER_STOP
		radar.gui_input.connect(_on_radar_input)
		radar.radar_radius = 88.0
		radar.ring_thickness = 18.0
		radar.show_neuromodulators = false
		radar.custom_minimum_size = Vector2(210.0, float(HEIGHTS["fly"]))
		row.add_child(radar)
		row.add_child(geom)
		_fly_row = row
	else:
		box.add_child(geom)

	_panels[kind] = panel
	_geoms[kind] = geom
	return panel


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.name = "Footer"
	row.add_theme_constant_override("separation", 8)

	build_label = Label.new()
	build_label.name = "Build"
	build_label.text = "build %s" % build_id()
	build_label.add_theme_font_size_override("font_size", 12)
	build_label.add_theme_color_override("font_color", DIM)
	build_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(build_label)

	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(120.0, 44.0)
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return row


# -- panel 8: the tunables ---------------------------------------------------

## EVERY KEY IN THE REGISTRY, AS SOMETHING A THUMB CAN MOVE.
##
## The rows are not written here -- they are read from [method HexyConfig.schema],
## which is the only place a tunable exists. Add a key to the schema and a row
## appears on this panel with the right control, the right bounds and the right
## default, and nothing in this file has to be told about it.
func _build_tunables(box: VBoxContainer) -> void:
	_config = HexyConfig.instance()

	## W8e -- THE GAUGE, AS ONE LINE. The gauge is the app's whole
	## interpretation layer and it is the one thing on this panel that is NOT
	## a knob: it is fitted by the bus, not by a thumb. So it gets a label and
	## no control -- the only door onto it from here is
	## [method HexyGauge.correct], and the controls that already exist for the
	## fields it shares with the schema are the controls it uses.
	_gauge_label = Label.new()
	_gauge_label.name = "Gauge"
	_gauge_label.text = "gauge —"
	_gauge_label.add_theme_font_size_override("font_size", 11)
	_gauge_label.add_theme_color_override("font_color", HUMAN)
	box.add_child(_gauge_label)

	var tools := HBoxContainer.new()
	tools.name = "Tools"
	tools.add_theme_constant_override("separation", 6)
	box.add_child(tools)
	tools.add_child(_tool_button("ResetAll", "RESET ALL", _on_reset_all))
	tools.add_child(_tool_button("CopyJson", "COPY JSON", _on_copy_json))
	tools.add_child(_tool_button("PasteJson", "PASTE JSON", _on_paste_json))

	var note := Label.new()
	note.name = "Note"
	note.text = "clipboard is the bridge to tools/visualizer"
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", DIM)
	box.add_child(note)

	var seen: Dictionary = {}
	for row in _config.schema():
		var group: String = String(row["group"])
		if not seen.has(group):
			seen[group] = true
			var head := Label.new()
			head.name = "Group" + group.capitalize()
			head.text = "— " + group.to_upper()
			head.add_theme_font_size_override("font_size", 11)
			head.add_theme_color_override("font_color", MACHINE)
			box.add_child(head)
		box.add_child(_build_tunable_row(row))

	if not _config.changed.is_connected(_on_config_changed):
		_config.changed.connect(_on_config_changed)


func _tool_button(node_name: String, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 34.0)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(handler)
	return b


## ONE KEY, ONE LINE: its name, the control that moves it, what it reads now,
## and the arrow that puts it back where it started.
func _build_tunable_row(row: Dictionary) -> Control:
	var key: String = String(row["key"])
	var line := HBoxContainer.new()
	line.name = "Row:" + key
	line.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = key.get_slice(".", 1)
	name_label.tooltip_text = String(row.get("doc", ""))
	name_label.custom_minimum_size = Vector2(150.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", INK)
	line.add_child(name_label)

	var value: Variant = _config.get_value(key)
	var kind: String = String(row["type"])
	var control: Control = null
	match kind:
		"bool":
			var check := CheckButton.new()
			check.button_pressed = bool(value)
			check.toggled.connect(_on_tunable_bool.bind(key))
			control = check
		"enum":
			var opt := OptionButton.new()
			var options: Array = row["options"]
			for i in range(options.size()):
				opt.add_item(String(options[i]), i)
			opt.selected = maxi(0, options.find(String(value)))
			opt.item_selected.connect(_on_tunable_enum.bind(key))
			control = opt
		_:
			var slider := HSlider.new()
			slider.min_value = float(row["min"])
			slider.max_value = float(row["max"])
			slider.step = maxf(float(row["step"]), 0.0001 if kind == "float" else 1.0)
			slider.value = float(value)
			slider.custom_minimum_size = Vector2(140.0, 28.0)
			slider.value_changed.connect(_on_tunable_number.bind(key))
			control = slider
	control.name = "Control"
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(control)

	var read := Label.new()
	read.name = "Value"
	read.text = _format_value(row, value)
	read.custom_minimum_size = Vector2(76.0, 0.0)
	read.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	read.add_theme_font_size_override("font_size", 11)
	read.add_theme_color_override("font_color", HUMAN)
	line.add_child(read)

	var undo := Button.new()
	undo.name = "Reset"
	undo.text = "↺"
	undo.tooltip_text = "back to %s" % str(row["default"])
	undo.custom_minimum_size = Vector2(34.0, 28.0)
	undo.pressed.connect(_on_reset_key.bind(key))
	line.add_child(undo)

	_tunable_controls[key] = control
	_tunable_labels[key] = read
	return line


static func _format_value(row: Dictionary, value: Variant) -> String:
	match String(row["type"]):
		"bool":
			return "on" if bool(value) else "off"
		"int":
			return str(int(value))
		"enum":
			return String(value)
	return "%.3f" % float(value)


## The control for one key, so a test may move it the way a thumb would.
func tunable_control(key: String) -> Control:
	return _tunable_controls.get(key, null) as Control


## What the panel is CURRENTLY READING BACK for one key, as a string.
func tunable_text(key: String) -> String:
	var l: Label = _tunable_labels.get(key, null) as Label
	return "" if l == null else l.text


# -- the tunable handlers -----------------------------------------------------

func _on_tunable_number(value: float, key: String) -> void:
	if _applying:
		return
	_config.set_value(key, value)


func _on_tunable_bool(pressed: bool, key: String) -> void:
	if _applying:
		return
	_config.set_value(key, pressed)


func _on_tunable_enum(index: int, key: String) -> void:
	if _applying:
		return
	var opt: OptionButton = _tunable_controls.get(key, null) as OptionButton
	if opt == null:
		return
	_config.set_value(key, opt.get_item_text(index))


func _on_reset_key(key: String) -> void:
	_config.reset(key)


func _on_reset_all() -> void:
	_config.reset()


func _on_copy_json() -> void:
	DisplayServer.clipboard_set(_config.to_json())


func _on_paste_json() -> bool:
	return _config.from_json(DisplayServer.clipboard_get())


## AN OUTSIDE WRITE, REFLECTED. `_applying` is raised for exactly as long as it
## takes to set the control, so the control's own signal -- which fires whether
## a thumb or this line moved it -- finds the guard up and goes home.
func _on_config_changed(key: String, value: Variant) -> void:
	var control: Control = _tunable_controls.get(key, null) as Control
	if control == null:
		return
	var row: Dictionary = _config.row(key)
	_applying = true
	if control is HSlider:
		(control as HSlider).value = float(value)
	elif control is CheckButton:
		(control as CheckButton).button_pressed = bool(value)
	elif control is OptionButton:
		var opt := control as OptionButton
		for i in range(opt.item_count):
			if opt.get_item_text(i) == String(value):
				opt.selected = i
				break
	_applying = false
	var l: Label = _tunable_labels.get(key, null) as Label
	if l != null and not row.is_empty():
		l.text = _format_value(row, value)


# -- panel 9: the controls ----------------------------------------------------

## THE TWELVE THINGS THE EARTH DIAL USED TO DO.
##
## A dial is for one figure; it was never the right place for a camera reset.
## Each row here is a button that calls the HOST by name, guarded by
## [method Object.has_method], so this panel stands complete whether the glass
## has grown the method yet or not -- a missing method is a greyed button, not
## a crash.
func _build_controls(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	for row in CONTROL_ROWS:
		var b := Button.new()
		b.name = _control_id(row)
		b.text = String(row["label"])
		b.custom_minimum_size = Vector2(0.0, 40.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.disabled = true
		b.pressed.connect(_on_control_pressed.bind(row))
		grid.add_child(b)
		_control_buttons[b.name] = b

	_control_readout = RichTextLabel.new()
	_control_readout.name = "Readout"
	_control_readout.bbcode_enabled = false
	_control_readout.fit_content = false
	_control_readout.scroll_active = true
	_control_readout.custom_minimum_size = Vector2(0.0, 96.0)
	_control_readout.add_theme_font_size_override("normal_font_size", 11)
	_control_readout.add_theme_color_override("default_color", DIM)
	_control_readout.text = "press a control; anything it says lands here"
	box.add_child(_control_readout)
	_sync_controls()


## The button's node name. `walk_earth` owns two, so the direction joins the id.
static func _control_id(row: Dictionary) -> String:
	var id: String = String(row["method"])
	if String(row.get("kind", "")) == "walk":
		id += "_prev" if int(row.get("arg", 1)) < 0 else "_next"
	return id


## Grey every button whose method the host does not have. Called whenever the
## host changes, which is the only time the answer can change.
func _sync_controls() -> void:
	for row in CONTROL_ROWS:
		var b: Button = _control_buttons.get(_control_id(row), null) as Button
		if b == null:
			continue
		b.disabled = _host == null or not _host.has_method(String(row["method"]))


func _on_control_pressed(row: Dictionary) -> void:
	var method: String = String(row["method"])
	if _host == null or not _host.has_method(method):
		return
	var kind: String = String(row.get("kind", ""))
	var out: Variant = null
	if kind == "walk":
		out = _host.call(method, int(row.get("arg", 1)))
	else:
		out = _host.call(method)
	if _control_readout == null:
		return
	if kind == "text":
		_control_readout.text = String(out)
	elif kind == "flag":
		_control_readout.text = "%s → %s" % [method, str(out)]


## One control button by its id, so a test may press what a thumb would press.
func control_button(id: String) -> Button:
	return _control_buttons.get(id, null) as Button


## What the controls panel last had to say.
func control_text() -> String:
	return "" if _control_readout == null else _control_readout.text


# -- panel 10: the doors ------------------------------------------------------

## WHO IS HOLDING WHICH DOOR, AND WHO IS WRITING WHICH TOPIC.
##
## W8e -- THE ROWS ARE THE BUS'S, NOT A FIXED TABLE. An add-on no longer
## claims a line of the body; it declares DOORS (broker resources) and the
## TOPICS it writes. So this panel is two blocks, both of them empty on a
## base app with no add-ons on disk, which is the picture "add-on off = base
## unchanged" should make:
##
##   DOORS    -- one row per door any attached add-on declared, naming the
##               holder the broker says is standing on it right now.
##   WRITERS  -- one row per topic, naming every add-on publishing on it.
## THE PHASE PANEL: four rows of plain text, one per timescale.
##
## NOTHING HERE REACHES FOR A BRAIN. scripts/glass may not preload
## scripts/brain, and the four numbers this panel wants -- calcium phase,
## internal hour, marks, chapter -- live on four different objects on the far
## side of that wall. So they arrive the only way they may: Front already
## computes all four every beat and pushes them in through
## [method set_phase_snapshot]. With nobody pushing, the rows read "—", which
## is the honest thing for a panel nobody has told anything.
## N3 -- the organism's stage, as pushed in on the phase snapshot.
var _stage: int = 0
var _stage_word: String = ""


func _build_phase(box: VBoxContainer) -> void:
	for key in PHASE_ROWS:
		var line := HBoxContainer.new()
		line.name = "Phase:" + key
		line.add_theme_constant_override("separation", 6)

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = key.to_upper()
		name_label.custom_minimum_size = Vector2(80.0, 0.0)
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", DIM)
		line.add_child(name_label)

		var read := Label.new()
		read.name = "Read"
		read.text = "—"
		read.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		read.add_theme_font_size_override("font_size", 11)
		read.add_theme_color_override("font_color", INK)
		line.add_child(read)

		_phase_labels[key] = read
		box.add_child(line)


## WHAT ONE OF THE FOUR ROWS CURRENTLY SAYS, for a caller that wants to read
## the panel back without walking the tree.
func phase_row_text(key: String) -> String:
	var l: Label = _phase_labels.get(key, null) as Label
	return l.text if l != null else ""


## THE SIX MARKS AS SIX SMALL BARS. A mark is signed and in [-1, 1]; each is
## drawn as one of five block characters so the whole body fits in six
## glyphs, with the days-toward count after it.
static func _mark_bars(marks: Array, days: Array) -> String:
	var out: String = ""
	for i in range(6):
		var m: float = absf(float(marks[i])) if i < marks.size() else 0.0
		out += MARK_BLOCKS[clampi(int(m * 4.999), 0, 4)]
	var total: int = 0
	for d in days:
		total += int(d)
	return "%s  days %d" % [out, total]


## THE ONE DOOR DATA COMES IN THROUGH. Front calls this each beat while the
## dashboard stands open; every key is optional and a missing one leaves its
## row alone rather than blanking it.
func set_phase_snapshot(d: Dictionary) -> void:
	## N3 -- THE STAGE IS PUSHED, NOT WORKED OUT. It came off "/body" at the
	## front; this panel spells it out and computes nothing about it.
	if d.has("stage"):
		_stage = int(d["stage"])
		_stage_word = String(d.get("stage_word", ""))
		_sync_gauge_row()
	if d.has("seconds"):
		_set_phase_row("seconds", String(d["seconds"]))
	elif d.has("radar_phase"):
		_set_phase_row("seconds", "calcium %.3f" % float(d["radar_phase"]))
	if d.has("internal_hour"):
		_set_phase_row("day", "%02d:%02d  offset %+.2fh  conf %.2f" % [
			int(float(d["internal_hour"])),
			int(fposmod(float(d["internal_hour"]), 1.0) * 60.0),
			float(d.get("offset_h", 0.0)),
			float(d.get("confidence", 0.0)),
		])
	if d.has("marks"):
		_set_phase_row("weeks", _mark_bars(d["marks"] as Array,
			(d.get("days_toward", []) as Array)))
	if d.has("chapter_title"):
		_set_phase_row("life", "%s · %s" % [
			String(d["chapter_title"]), String(d.get("stage_name", ""))])
	_phase_snapshot = d.duplicate(true)


## The snapshot exactly as it last arrived, for a test or a tool.
func phase_snapshot() -> Dictionary:
	return _phase_snapshot.duplicate(true)


func _set_phase_row(key: String, text: String) -> void:
	var l: Label = _phase_labels.get(key, null) as Label
	if l != null:
		l.text = text


## The heading of each block, and the one line a block shows when the bus is
## carrying nothing for it. Both are read by [method doors_text], so the text
## a test reads and the text a person reads are the same string.
const DOORS_EMPTY: String = "no add-on holds a door"
const WRITERS_EMPTY: String = "no add-on writes a topic"

var _doors_box: VBoxContainer = null


func _build_doors(box: VBoxContainer) -> void:
	_doors_box = box
	_sync_doors()


func _build_door_row(label: String, value: String, tint: Color) -> Control:
	var line := HBoxContainer.new()
	line.name = "Door:" + label
	line.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = label
	name_label.custom_minimum_size = Vector2(150.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", INK)
	line.add_child(name_label)

	var read := Label.new()
	read.name = "Door"
	read.text = value
	read.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	read.add_theme_font_size_override("font_size", 11)
	read.add_theme_color_override("font_color", tint)
	line.add_child(read)

	_door_labels[label] = read
	return line


static func _block_head(text: String) -> Label:
	var sep := Label.new()
	sep.name = "Head:" + text
	sep.text = text
	sep.add_theme_font_size_override("font_size", 11)
	return sep


## Repaint the ten rows from the loader. Cheap enough to run on every beat,
## and it is the only thing that can change on this panel.
func _sync_doors() -> void:
	if _doors_box == null:
		return
	for child in _doors_box.get_children():
		_doors_box.remove_child(child)
		child.queue_free()
	_door_labels.clear()

	var head_doors: Label = _block_head("— DOORS")
	head_doors.add_theme_color_override("font_color", MACHINE)
	_doors_box.add_child(head_doors)
	var map: Dictionary = _doors_map()
	if map.is_empty():
		_doors_box.add_child(_build_door_row("—", DOORS_EMPTY, DIM))
	else:
		var names: Array = map.keys()
		names.sort()
		for d in names:
			_doors_box.add_child(_build_door_row(String(d), String(map[d]), HUMAN))

	var head_writers: Label = _block_head("— WRITERS")
	head_writers.add_theme_color_override("font_color", MACHINE)
	_doors_box.add_child(head_writers)
	var writers: Dictionary = _writers_map()
	if writers.is_empty():
		_doors_box.add_child(_build_door_row("—", WRITERS_EMPTY, DIM))
	else:
		var topics: Array = writers.keys()
		topics.sort()
		for t in topics:
			_doors_box.add_child(_build_door_row(String(t),
				", ".join(PackedStringArray(writers[t] as Array)), HUMAN))


## DOOR -> HOLDER. The loader knows which doors exist (every add-on declares
## its own); the broker knows who is standing on one right this second, and
## it is the broker that is asked, so a door declared and never acquired
## reads "free" rather than lying about an owner.
func _doors_map() -> Dictionary:
	var out: Dictionary = {}
	if _addons == null or not _addons.has_method("doors"):
		return out
	for d in (_addons.call("doors") as Dictionary).keys():
		var door: String = String(d)
		var holder: String = ""
		if _broker != null and _broker.has_method("holder"):
			holder = String(_broker.call("holder", door))
		if holder == "":
			holder = String((_addons.call("doors") as Dictionary)[d])
		out[door] = holder if holder != "" else "free"
	return out


## TOPIC -> THE ADD-ONS WRITING ON IT, straight off the loader's manifest.
func _writers_map() -> Dictionary:
	if _addons == null or not _addons.has_method("topic_writers"):
		return {}
	return _addons.call("topic_writers") as Dictionary


## The loader whose doors this panel draws.
func set_addons(addons: Node) -> void:
	_addons = addons
	_sync_doors()


## THE DOORS PANEL AS ONE BLOCK OF TEXT, so a test may read what a person
## reads. One "line: door" per row, need lines first, circuits after.
func doors_text() -> String:
	_sync_doors()
	var out: PackedStringArray = PackedStringArray()
	out.append("— DOORS")
	var map: Dictionary = _doors_map()
	if map.is_empty():
		out.append("—: %s" % DOORS_EMPTY)
	else:
		var names: Array = map.keys()
		names.sort()
		for d in names:
			out.append("%s: %s" % [String(d), String(map[d])])
	out.append("— WRITERS")
	var writers: Dictionary = _writers_map()
	if writers.is_empty():
		out.append("—: %s" % WRITERS_EMPTY)
	else:
		var topics: Array = writers.keys()
		topics.sort()
		for t in topics:
			out.append("%s: %s" % [String(t),
				", ".join(PackedStringArray(writers[t] as Array))])
	return "
".join(out)


# -- wiring ------------------------------------------------------------------

## Everything this panel is allowed to know, handed over at once. Qwen is
## optional because the glass binds it separately; the bus arrives late.
func bind(store: Node, mnn: Node, wmn: Node, senses: Node, pressure: Node = null,
		qwen: Node = null) -> void:
	_store = store
	_mnn = mnn
	_wmn = wmn
	_senses = senses
	_qwen = qwen
	## THE FIFTH SLOT IS DEAD. It used to be the core object that turned a
	## line of the body when a person stood still; nothing on the glass may
	## hold a writer of organism state any more, so it is taken and dropped.
	var _dead: Node = pressure


func set_senses(senses: Node) -> void:
	_senses = senses


## THE COMPASS, handed down from the glass, duck-typed and optional exactly as
## it is up there. No compass is not an error: the dial falls back to the
## allocentric disc it drew before there was one.
func set_heading(h: Node) -> void:
	_heading = h


## LEND THIS PANEL THE ONE RADAR. Whoever owns it (the front) calls this
## before or while panel 6·FLY is shown, so the panel draws the SAME creature
## the front's own room shows rather than keeping a second one alive. Safe to
## call more than once with the same instance, and safe to call before the
## panel has ever been opened -- the swap happens right away either way, which
## is the only way "exactly one radar in the tree" can hold while this panel
## is merely built and not yet visible.
func borrow_radar(r: Control) -> void:
	if r == null:
		return
	_lender = r
	if not _using_borrowed:
		_swap_in_borrowed_radar()


## THE SWAP: the panel's own built radar is freed, the lent one takes its
## place in the row at the same slot, wired for a tap and shown loud.
func _swap_in_borrowed_radar() -> void:
	if _lender == null or _fly_row == null or radar == _lender:
		return
	_lent_from_parent = _lender.get_parent()
	_lent_from_index = _lender.get_index() if _lent_from_parent != null else -1
	var slot: int = 0
	if radar != null and radar.get_parent() == _fly_row:
		slot = radar.get_index()
		if radar.gui_input.is_connected(_on_radar_input):
			radar.gui_input.disconnect(_on_radar_input)
		_fly_row.remove_child(radar)
		radar.queue_free()
	if _lender.get_parent() != null:
		_lender.get_parent().remove_child(_lender)
	_fly_row.add_child(_lender)
	_fly_row.move_child(_lender, slot)
	_lender.radar_radius = 88.0
	_lender.ring_thickness = 18.0
	_lender.show_neuromodulators = false
	_lender.custom_minimum_size = Vector2(210.0, float(HEIGHTS["fly"]))
	_lender.mouse_filter = Control.MOUSE_FILTER_STOP
	if not _lender.gui_input.is_connected(_on_radar_input):
		_lender.gui_input.connect(_on_radar_input)
	_lender.set_quiet(false)
	radar = _lender
	_using_borrowed = true


## THE RADAR GOES HOME. Whoever lent it gets it back at the same seat it left,
## quiet again -- called when this panel stops showing it: the dashboard
## closing, or (should a future caller add one) the panel itself hiding.
func _return_borrowed_radar() -> void:
	if not _using_borrowed or radar == null:
		return
	if radar.gui_input.is_connected(_on_radar_input):
		radar.gui_input.disconnect(_on_radar_input)
	var cur_parent: Node = radar.get_parent()
	if cur_parent != null:
		cur_parent.remove_child(radar)
	radar.set_quiet(true)
	if _lent_from_parent != null:
		_lent_from_parent.add_child(radar)
		var at: int = mini(maxi(_lent_from_index, 0), _lent_from_parent.get_child_count() - 1)
		_lent_from_parent.move_child(radar, at)
	radar = null
	_using_borrowed = false


## A PEER THE FABRIC DROPPED LEAVES THIS DIAL TOO. The glass forwards Wmn's
## `peer_gone` to both radars, because a heading map that keeps a dead entry
## keeps drawing a blip for somebody who walked out.
func drop_peer(who: String) -> void:
	if radar != null:
		radar.drop_peer(who)


## A TAP ON A BLIP PICKS SOMEBODY TO WALK TOWARD; a second tap lets them go.
## One gesture in, the same gesture out -- the radar's own rule, and this file
## only routes it, byte for byte as `hud3.gd` does.
func _on_radar_input(event: InputEvent) -> void:
	if radar == null:
		return
	var at: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
			return
		at = mb.position
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if not st.pressed:
			return
		at = st.position
	else:
		return
	if at.distance_to(radar.disc_center()) > radar.field_radius():
		return
	radar.tap(at)
	radar.accept_event()


## THE ONE GAUGE, handed down from the app through the front. Read only.
func set_bus(topic: RefCounted, gauge: RefCounted) -> void:
	var _unused: RefCounted = topic
	_gauge = gauge
	_sync_gauge_row()


## The broker, for panel 10's holder column.
func set_broker(b: Node) -> void:
	_broker = b
	_sync_doors()


func set_host(host: Node) -> void:
	_host = host
	_sync_controls()


# -- opening and closing -----------------------------------------------------

func open() -> void:
	## FULL RECT BY ANCHOR, NEVER BY HAND. Writing `size` on a node whose
	## opposite anchors differ is overridden by the very next layout pass and
	## warns on the way past -- the fold's logcat was a wall of "Nodes with
	## non-equal opposite anchors will have their size overridden". Both this
	## overlay and its backdrop are already FULL_RECT from `_ready`; re-seating
	## the preset (offsets included) is the whole of what re-opening needs, and
	## it works whether the parent is a Control or a bare CanvasLayer.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if backdrop != null:
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = true
	move_to_front()
	_refresh()
	if _beat != null:
		_beat.start()


func close() -> void:
	visible = false
	if _beat != null:
		_beat.stop()
	_return_borrowed_radar()


func toggle() -> bool:
	if is_open():
		close()
	else:
		open()
	return is_open()


func is_open() -> bool:
	return visible


func _on_backdrop_input(event: InputEvent) -> void:
	if _is_release(event):
		close()
		accept_event()


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false


# -- what a test may ask for -------------------------------------------------

func panel(kind: String) -> PanelContainer:
	return _panels.get(kind, null) as PanelContainer


func geom(kind: String) -> Control:
	return _geoms.get(kind, null) as Control


## How many times each panel has painted itself. A zero here is a panel whose
## _draw never ran.
func draw_counts() -> Dictionary:
	var out: Dictionary = {}
	for kind in PANELS:
		var g: Geom = _geoms.get(kind, null) as Geom
		out[kind] = 0 if g == null else g.draws
	return out


## The sixty-four cells of the sense grid, machine row major.
func sense_grid() -> Array:
	return (_snap.get("grid", []) as Array)


## The three figures as the store holds them.
func figures() -> Dictionary:
	return (_snap.get("figures", {}) as Dictionary)


## The whole snapshot the panels paint from.
func snapshot() -> Dictionary:
	return _snap


static func build_id() -> String:
	if not ResourceLoader.exists(BUILD_PATH) and not FileAccess.file_exists(BUILD_PATH):
		return "dev"
	var f := FileAccess.open(BUILD_PATH, FileAccess.READ)
	if f == null:
		return "dev"
	var text: String = f.get_as_text().strip_edges()
	return text.substr(0, 12) if text != "" else "dev"


# -- the snapshot ------------------------------------------------------------

## ONE READ OF THE WHOLE APP, ten times a second. Every panel paints from this
## dictionary and asks nothing else, so a panel can never cost a second call
## into the core and the whole surface is consistent within one beat.
func _refresh() -> void:
	if not visible:
		return
	_fps.append(float(Engine.get_frames_per_second()))
	while _fps.size() > FPS_SAMPLES:
		_fps.remove_at(0)

	var snap: Dictionary = {}
	snap["fps"] = _fps
	snap["device"] = _read_device()
	snap["engine"] = _read_engine()
	snap["figures"] = _read_figures()
	snap["senses"] = _read_senses()
	snap["grid"] = snap["senses"].get("grid", [])
	snap["fires"] = _read_fires()
	snap["fly"] = _read_fly()
	snap["mesh"] = _read_mesh()
	_snap = snap

	_sync_doors()
	_sync_gauge_row()

	## THE BORROWED CASE FEEDS ITSELF. The front pushes the state, the peer
	## headings, the proximity and the compass into this same instance every
	## beat of its own; doing it again here would be a second, slower clock on
	## one radar rather than a compass push this panel has any business making.
	if radar != null and not _using_borrowed:
		var fs: Dictionary = snap["fly"].get("state", {}) as Dictionary
		if not fs.is_empty():
			radar.set_state(fs)
		if _wmn != null and _wmn.has_method("peer_headings"):
			radar.set_peer_headings(_wmn.peer_headings() as Dictionary)
		if _wmn != null and _wmn.has_method("peer_proximity"):
			radar.set_peer_proximity(_wmn.peer_proximity() as Dictionary)
		## AND THE COMPASS, the same seven facts the glass pushes into its own
		## dial. Without them this radar is allocentric and tap-to-guide has
		## nothing to turn against, which is not a radar a person can walk by.
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

	for kind in PANELS:
		var g: Control = _geoms.get(kind, null) as Control
		if g != null:
			g.queue_redraw()


func _read_device() -> Dictionary:
	var box: Vector2i = Vector2i(size)
	if box.x < 8 or box.y < 8:
		box = DisplayServer.window_get_size()
	var profile: Dictionary = DeviceProfile.resolve(-1, box, "")
	var ram: int = int(profile.get("resolved_ram_bytes", 0))
	var free: int = int(_mnn.free_storage_bytes()) if _mnn != null and _mnn.has_method("free_storage_bytes") else -1
	return {
		"who": _who(),
		"row": String(profile.get("id", "unknown")),
		"name": String(profile.get("name", "")),
		"layout": String(profile.get("layout", "tall_slab")),
		"lane": String(profile.get("chat_lane", "")),
		"viewport": box,
		"ram": ram,
		"free": free,
		"lamp": String(_mnn.tier_lamp_line()) if _mnn != null and _mnn.has_method("tier_lamp_line") else "no engine",
	}


func _read_engine() -> Dictionary:
	var tiers: Array = []
	if _mnn != null and _mnn.has_method("tiers"):
		tiers = _mnn.tiers()
	var organism: String = ""
	if _qwen != null:
		var fs: Dictionary = _fly_state()
		if not fs.is_empty() and _qwen.has_method("organism_line"):
			organism = String(_qwen.call("organism_line", fs))
		elif organism == "" and _qwen.has_method("prompt_now"):
			organism = String(_qwen.call("prompt_now", "")).split("\n")[0]
	var answer: String = String(_store.answer) if _store != null else ""
	var streamed: int = 0
	if _host != null:
		var s: Variant = _host.get("_stream")
		streamed = String(s).length() if s != null else 0
	## How hard the decode loop is leaning on the cube, and whether its warm
	## state is still the cube the body is standing on.
	var info: Dictionary = _mnn.info() if _mnn != null and _mnn.has_method("info") else {}
	return {
		"available": bool(_mnn.available()) if _mnn != null and _mnn.has_method("available") else false,
		"backend": String(_mnn.backend_name()) if _mnn != null and _mnn.has_method("backend_name") else "none",
		"tier": String(_mnn.tier()) if _mnn != null and _mnn.has_method("tier") else "",
		"tiers": tiers,
		"q6_prior_weight": float(info.get("q6_prior_weight", 0.0)),
		"q6_cast_version": int(info.get("q6_cast_version", 0)),
		"q6_prior_mismatches": int(info.get("q6_prior_mismatches", 0)),
		"answer_len": answer.length(),
		"organism": organism,
		"streamed": streamed,
	}


func _read_figures() -> Dictionary:
	if _store == null:
		return {}
	var out: Dictionary = {}
	for key in ["head", "body", "earth"]:
		var bits: int = 0
		match key:
			"head": bits = int(_store.head_bits()) & 63
			"body": bits = int(_store.body_bits()) & 63
			_: bits = int(_store.earth_bits()) & 63
		out[key] = {"bits": bits, "num": KingWen.number(bits), "zh": KingWen.zh(bits)}
	var flip: Dictionary = _store.last_flip as Dictionary
	out["flip"] = String(flip.get("reason", ""))
	out["flip_line"] = int(flip.get("line", 0))
	return out


func _read_senses() -> Dictionary:
	var out: Dictionary = {
		"grid": [], "machine": [], "human": [],
		"stillness": 0.0, "excitation": 0.0, "period": 0,
		"machine_margin": 0.0, "human_margin": 0.0,
		"elected_machine": -1, "elected_human": -1,
	}
	if _senses == null or not _senses.has_method("scores"):
		return out
	var rows: Dictionary = _senses.scores()
	var m: Array = rows.get("machine", []) as Array
	var h: Array = rows.get("human", []) as Array
	var grid: Array = []
	for r in range(8):
		for c in range(8):
			var mv: float = float(m[r]) if r < m.size() else 0.0
			var hv: float = float(h[c]) if c < h.size() else 0.0
			grid.append(mv * hv)
	out["grid"] = grid
	out["machine"] = m
	out["human"] = h
	var target: int = int(_senses.target_bits()) if _senses.has_method("target_bits") else 0
	out["elected_machine"] = target & 7
	out["elected_human"] = (target >> 3) & 7
	out["stillness"] = float(_senses.stillness()) if _senses.has_method("stillness") else 0.0
	out["excitation"] = float(_senses.excitation()) if _senses.has_method("excitation") else 0.0
	out["machine_margin"] = float(_senses.machine_margin()) if _senses.has_method("machine_margin") else 0.0
	out["human_margin"] = float(_senses.human_margin()) if _senses.has_method("human_margin") else 0.0
	out["period"] = int(_senses.period_ms)
	return out


## PANEL 5, OFF THE GAUGE AND THE SIXTEEN. The pressure standing on the six
## lines is the gauge's own `line_lean`, which is exactly what the reading
## layer adds to each fill before it thresholds it -- the same number the old
## core object called a mark, now held in one file a person can correct.
func _read_fires() -> Dictionary:
	var still: float = float(_senses.stillness()) if _senses != null and _senses.has_method("stillness") else 0.0
	var lean: Array = []
	var need: float = 2.5
	if _gauge != null:
		lean = (_gauge.call("get_field", "line_lean", []) as Array)
		need = maxf(0.001, float(_gauge.call("get_field", "civil_fire_s", 2.5)))
	return {
		"dwell_s": still, "dwell_needed_s": need,
		"refractory_s": 0.0, "refractory_needed_s": 3.5,
		"last_reason": _lean_reason(lean), "flex": false,
		"line_lean": lean,
	}


## THE SIX LEANS, SAID ONCE. "—" when the gauge is standing at zero, which is
## an honest "nothing is leaning" rather than a row of zeroes.
static func _lean_reason(lean: Array) -> String:
	if lean.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var any: bool = false
	for i in range(lean.size()):
		var v: float = float(lean[i])
		if not is_zero_approx(v):
			any = true
		parts.append("L%d %+.2f" % [i + 1, v])
	return ("lean " + " ".join(parts)) if any else "no line is leaning"


func _fly_state() -> Dictionary:
	if _store == null or not _store.has_method("get_character"):
		return {}
	var ch: Variant = _store.get_character()
	if ch == null or not ch.has_method("get_fly_state"):
		return {}
	return ch.get_fly_state() as Dictionary


func _read_fly() -> Dictionary:
	return {"state": _fly_state()}


func _read_mesh() -> Dictionary:
	if _wmn == null:
		return {"fabric": "off", "id": "", "peers": [], "count": 0, "offset": 0, "drifting": []}
	var peers: Array = _wmn.peers() if _wmn.has_method("peers") else []
	return {
		"fabric": "lan" if bool(_wmn.force_lan) else "nearby",
		"id": String(_wmn.fabric_id()).substr(0, 8) if _wmn.has_method("fabric_id") else "",
		"name": String(_wmn.display_name()) if _wmn.has_method("display_name") else "",
		"peers": peers,
		"count": int(_wmn.peer_count()) if _wmn.has_method("peer_count") else peers.size(),
		"offset": int(_wmn.offset_ms()) if _wmn.has_method("offset_ms") else 0,
		"drifting": _wmn.drifting() if _wmn.has_method("drifting") else [],
		"headings": _wmn.peer_headings() if _wmn.has_method("peer_headings") else {},
	}


func _who() -> String:
	if _host != null and _host.has_method("who"):
		return String(_host.call("who"))
	return "hexy"


# -- the seven panels --------------------------------------------------------

func _paint_identity(g: Control) -> void:
	var d: Dictionary = _snap.get("device", {}) as Dictionary
	if d.is_empty():
		return
	var w: float = g.size.x
	_line(g, Vector2(0.0, 12.0), "%s · %s" % [String(d["who"]).to_upper(), String(d["row"])], INK, 13)
	_line(g, Vector2(0.0, 28.0), "layout %s · lane %s · %dx%d" % [
		d["layout"], d["lane"], (d["viewport"] as Vector2i).x, (d["viewport"] as Vector2i).y], DIM, 11)

	var ram: float = float(d["ram"])
	_bar(g, Rect2(0.0, 40.0, w, 20.0), ram / RAM_FULL, MACHINE, "RAM %s" % _gb(int(ram)),
		[float(ModelStore.CHAT_35_MIN_RAM) / RAM_FULL, float(ModelStore.CHAT_BIG_MIN_RAM) / RAM_FULL])

	var free: int = int(d["free"])
	var frac: float = 0.0 if free < 0 else float(free) / STORAGE_FULL
	_bar(g, Rect2(0.0, 68.0, w, 20.0), frac, HUMAN,
		"FREE %s" % ("unknown" if free < 0 else _gb(free)), [])

	_line(g, Vector2(0.0, 104.0), String(d["lamp"]).substr(0, 96), DIM, 10)

	## The frame rate, sixty beats of it, with the 16.7 ms budget across it.
	var box := Rect2(0.0, 112.0, w, g.size.y - 116.0)
	_spark(g, box, _snap.get("fps", PackedFloat32Array()) as PackedFloat32Array)


func _paint_engine(g: Control) -> void:
	var e: Dictionary = _snap.get("engine", {}) as Dictionary
	if e.is_empty():
		return
	var live: bool = bool(e["available"])
	g.draw_circle(Vector2(8.0, 12.0), 6.0, GOOD if live else BAD)
	_line(g, Vector2(20.0, 16.0), "%s · backend %s · tier %s" % [
		"live" if live else "mock", e["backend"], String(e["tier"]) if String(e["tier"]) != "" else "none"], INK, 13)

	var tiers: Array = e.get("tiers", []) as Array
	var x: float = 4.0
	for row in tiers:
		var ok: bool = bool((row as Dictionary).get("allowed", false))
		var id: String = String((row as Dictionary).get("id", "?"))
		g.draw_rect(Rect2(x, 30.0, 14.0, 14.0), GOOD if ok else BAD, true)
		g.draw_rect(Rect2(x, 30.0, 14.0, 14.0), WIRE, false, 1.0)
		_line(g, Vector2(x, 60.0), id, DIM, 10)
		x += 62.0

	_line(g, Vector2(0.0, 84.0), "answer %d chars · streamed %d" % [
		int(e["answer_len"]), int(e["streamed"])], DIM, 11)
	var org: String = String(e.get("organism", ""))
	if org != "":
		_line(g, Vector2(0.0, 100.0), org.substr(0, 78), MACHINE, 10)
		if org.length() > 78:
			_line(g, Vector2(0.0, 114.0), org.substr(78, 78), MACHINE, 10)


func _paint_figures(g: Control) -> void:
	var f: Dictionary = _snap.get("figures", {}) as Dictionary
	if f.is_empty():
		return
	var keys: Array[String] = (["head", "body", "earth"] as Array[String])
	var cell: float = g.size.x / 3.0
	for i in range(3):
		var one: Dictionary = f.get(keys[i], {}) as Dictionary
		var bits: int = int(one.get("bits", 0))
		var cx: float = cell * (float(i) + 0.5)
		_hexagram(g, Vector2(cx, 16.0), bits, minf(cell * 0.5, 70.0))
		_centred(g, Vector2(cx, 116.0), "#%d %s" % [int(one.get("num", 0)), String(one.get("zh", ""))], INK, 12)
		_centred(g, Vector2(cx, 132.0), keys[i].to_upper(), DIM, 10)
	var reason: String = String(f.get("flip", ""))
	if reason != "":
		_line(g, Vector2(0.0, 152.0), reason.substr(0, 84), FIRE, 10)

	## WHETHER THE CUBE UNDER THE FIGURES IS STILL THE FIGURES' OWN. The cast
	## version counts the casts the decode loop has been told about; a mismatch
	## is a tick where the warm state and the standing figure disagreed, and a
	## number that climbs here is the one bug this panel exists to catch.
	var e: Dictionary = _snap.get("engine", {}) as Dictionary
	var bad: int = int(e.get("q6_prior_mismatches", 0))
	_line(g, Vector2(0.0, 168.0), "cast v%d · prior %.3f · mismatches %d" % [
		int(e.get("q6_cast_version", 0)), float(e.get("q6_prior_weight", 0.0)), bad],
		BAD if bad > 0 else DIM, 10)


func _paint_senses(g: Control) -> void:
	var s: Dictionary = _snap.get("senses", {}) as Dictionary
	var grid: Array = s.get("grid", []) as Array
	var side: float = minf(g.size.x - 120.0, 210.0)
	var cell: float = maxf(6.0, side / 8.0)
	var top: float = 6.0
	var em: int = int(s.get("elected_machine", -1))
	var eh: int = int(s.get("elected_human", -1))
	for r in range(8):
		for c in range(8):
			var v: float = float(grid[r * 8 + c]) if grid.size() == 64 else 0.0
			var shade := Color(MACHINE.r, MACHINE.g, MACHINE.b, clampf(0.08 + v, 0.0, 1.0))
			g.draw_rect(Rect2(c * cell, top + r * cell, cell - 1.0, cell - 1.0), shade, true)
	if em >= 0:
		g.draw_rect(Rect2(0.0, top + em * cell, cell * 8.0, cell), MACHINE, false, 2.0)
	if eh >= 0:
		g.draw_rect(Rect2(eh * cell, top, cell, cell * 8.0), HUMAN, false, 2.0)
	_line(g, Vector2(cell * 8.0 + 8.0, 16.0), "rows machine", MACHINE, 10)
	_line(g, Vector2(cell * 8.0 + 8.0, 30.0), "cols human", HUMAN, 10)
	_line(g, Vector2(cell * 8.0 + 8.0, 48.0), "elected %d/%d" % [em, eh], INK, 11)
	_line(g, Vector2(cell * 8.0 + 8.0, 64.0), "period %d ms" % int(s.get("period", 0)), DIM, 10)
	_line(g, Vector2(cell * 8.0 + 8.0, 78.0), "m margin %.2f" % float(s.get("machine_margin", 0.0)), DIM, 10)
	_line(g, Vector2(cell * 8.0 + 8.0, 92.0), "h margin %.2f" % float(s.get("human_margin", 0.0)), DIM, 10)

	var base: float = top + cell * 8.0 + 46.0
	_quarter(g, Vector2(46.0, base), 38.0, clampf(float(s.get("stillness", 0.0)) / 3.0, 0.0, 1.0),
		MACHINE, "STILL %.2f" % float(s.get("stillness", 0.0)))
	_quarter(g, Vector2(170.0, base), 38.0, clampf(float(s.get("excitation", 0.0)), 0.0, 1.0),
		FIRE, "EXCITE %.2f" % float(s.get("excitation", 0.0)))


func _paint_fires(g: Control) -> void:
	var f: Dictionary = _snap.get("fires", {}) as Dictionary
	if f.is_empty():
		return
	var need: float = maxf(0.001, float(f.get("dwell_needed_s", 2.5)))
	var dwell: float = clampf(float(f.get("dwell_s", 0.0)) / need, 0.0, 1.0)
	_arc(g, Vector2(58.0, 66.0), 44.0, dwell, MACHINE,
		"CIVIL", "%.1f/%.1fs" % [float(f.get("dwell_s", 0.0)), need])

	var rneed: float = maxf(0.001, float(f.get("refractory_needed_s", 3.5)))
	var left: float = float(f.get("refractory_s", 0.0))
	_arc(g, Vector2(178.0, 66.0), 44.0, clampf(left / rneed, 0.0, 1.0), FIRE,
		"MARTIAL", "armed" if left <= 0.0 else "%.1fs" % left)

	_line(g, Vector2(250.0, 24.0), "flex breath" if bool(f.get("flex", false)) else "slab breath", DIM, 11)
	var reason: String = String(f.get("last_reason", ""))
	_line(g, Vector2(0.0, 140.0), (reason if reason != "" else "no line has turned yet").substr(0, 84), INK, 10)


func _paint_fly(g: Control) -> void:
	var fs: Dictionary = (_snap.get("fly", {}) as Dictionary).get("state", {}) as Dictionary
	if fs.is_empty():
		_line(g, Vector2(0.0, 16.0), "no organism attached", DIM, 11)
		return
	var names: Array[String] = (["dopamine", "serotonin", "octopamine", "gaba", "acetylcholine", "coherence"] as Array[String])
	var short: Array[String] = (["DA", "5HT", "OA", "GABA", "ACh", "COH"] as Array[String])
	var w: float = maxf(10.0, (g.size.x - 8.0) / 6.0)
	for i in range(6):
		var v: float = clampf(float(fs.get(names[i], 0.0)), 0.0, 1.0)
		var x: float = float(i) * w
		g.draw_rect(Rect2(x, 14.0 + (70.0 - 70.0 * v), w - 6.0, 70.0 * v), MACHINE, true)
		g.draw_rect(Rect2(x, 14.0, w - 6.0, 70.0), WIRE, false, 1.0)
		_line(g, Vector2(x, 98.0), short[i], DIM, 9)

	## The six habits, diverging from the middle: right of centre is a pull
	## toward that line, left of it a push away.
	var bias: Array = fs.get("habit_bias", []) as Array
	var mid: float = g.size.x * 0.5
	for i in range(6):
		var b: float = clampf(float(bias[i]) if i < bias.size() else 0.0, -1.0, 1.0)
		var y: float = 112.0 + float(i) * 11.0
		g.draw_line(Vector2(mid, y), Vector2(mid, y + 8.0), WIRE, 1.0)
		var span: float = (g.size.x * 0.45) * b
		g.draw_rect(Rect2(minf(mid, mid + span), y, absf(span) + 1.0, 8.0),
			HUMAN if b >= 0.0 else BAD, true)

	_line(g, Vector2(0.0, 190.0), "phase %s · startle %.2f · KC %d%s" % [
		String(fs.get("phase", "?")), float(fs.get("startle", 0.0)), int(fs.get("kc_count", 0)),
		" · STARTLED" if bool(fs.get("is_startled", false)) else ""], INK, 10)
	_line(g, Vector2(0.0, 204.0), "heading %.2f rad · trigram %d · align %.2f" % [
		float(fs.get("heading_rad", 0.0)), int(fs.get("dominant_trigram", 0)),
		float(fs.get("target_alignment", 0.0))], DIM, 10)


func _paint_mesh(g: Control) -> void:
	var m: Dictionary = _snap.get("mesh", {}) as Dictionary
	if m.is_empty():
		return
	_line(g, Vector2(0.0, 14.0), "%s · %s · %d peers · offset %d ms" % [
		String(m["fabric"]).to_upper(), String(m["id"]), int(m["count"]), int(m["offset"])], INK, 12)

	## The ring: every peer a dot at its own heading, drift ones hollow.
	var centre := Vector2(66.0, 130.0)
	var radius: float = 52.0
	g.draw_arc(centre, radius, 0.0, TAU, 48, WIRE, 1.5)
	g.draw_circle(centre, 4.0, MACHINE)
	var headings: Dictionary = m.get("headings", {}) as Dictionary
	var drift: Array = m.get("drifting", []) as Array
	var peers: Array = m.get("peers", []) as Array
	for i in range(peers.size()):
		var who: String = String((peers[i] as Dictionary).get("who", ""))
		var ang: float = float(headings.get(who, float(i) * TAU / maxf(1.0, float(peers.size()))))
		var at: Vector2 = centre + Vector2(cos(ang), sin(ang)) * radius
		if who in drift:
			g.draw_arc(at, 5.0, 0.0, TAU, 12, HUMAN, 1.5)
		else:
			g.draw_circle(at, 5.0, HUMAN)

	var y: float = 34.0
	if peers.is_empty():
		_line(g, Vector2(136.0, y), "solo · no peer heard", DIM, 11)
	for i in range(mini(6, peers.size())):
		var p: Dictionary = peers[i] as Dictionary
		var short := IdentityScript.short_name(String(p.get("who", "")))
		var cls := String(p.get("cls", ""))
		_line(g, Vector2(136.0, y), "%s  %s  %s  %s  %d ms" % [
			short, String(p.get("band", "")), cls if cls != "" else "?",
			_trigram_of(p.get("heading_rad", null)),
			int(p.get("last_seen_ms", 0))], DIM, 10)
		y += 15.0


## A peer's heading, as the trigram glyph of the radar wedge it falls in.
## `null` (no bio pulse heard yet) draws no glyph rather than guessing a
## direction nobody sent.
func _trigram_of(heading_rad: Variant) -> String:
	if heading_rad == null:
		return "·"
	return KingWen.heading_glyph(float(heading_rad))


# -- the geometry primitives -------------------------------------------------

## A horizontal bar with a caption and any number of threshold ticks.
func _bar(g: Control, box: Rect2, value: float, tint: Color, caption: String, ticks: Array) -> void:
	g.draw_rect(box, Color(tint.r, tint.g, tint.b, 0.12), true)
	var v: float = clampf(value, 0.0, 1.0)
	g.draw_rect(Rect2(box.position, Vector2(box.size.x * v, box.size.y)), tint, true)
	g.draw_rect(box, WIRE, false, 1.0)
	for t in ticks:
		var x: float = box.position.x + box.size.x * clampf(float(t), 0.0, 1.0)
		g.draw_line(Vector2(x, box.position.y - 3.0), Vector2(x, box.end.y + 3.0), INK, 1.0)
	_line(g, Vector2(box.position.x + 6.0, box.position.y + box.size.y - 6.0), caption, INK, 11)


## A ring of samples, newest on the right, with the frame budget across it.
func _spark(g: Control, box: Rect2, samples: PackedFloat32Array) -> void:
	g.draw_rect(box, Color(MACHINE.r, MACHINE.g, MACHINE.b, 0.06), true)
	var budget_y: float = box.end.y - box.size.y * clampf(BUDGET_FPS / 90.0, 0.0, 1.0)
	g.draw_line(Vector2(box.position.x, budget_y), Vector2(box.end.x, budget_y), HUMAN, 1.0)
	_line(g, Vector2(box.position.x + 4.0, budget_y - 3.0), "16.7 ms", HUMAN, 9)
	if samples.size() < 2:
		return
	var step: float = box.size.x / float(FPS_SAMPLES - 1)
	var prev := Vector2.ZERO
	for i in range(samples.size()):
		var f: float = clampf(samples[i] / 90.0, 0.0, 1.0)
		var p := Vector2(box.position.x + float(i) * step, box.end.y - box.size.y * f)
		if i > 0:
			g.draw_line(prev, p, MACHINE, 1.5)
		prev = p
	_line(g, Vector2(box.end.x - 58.0, box.position.y + 12.0), "%d FPS" % int(samples[samples.size() - 1]), INK, 11)


## One figure, six lines, bottom line first, yang solid and yin broken.
func _hexagram(g: Control, top_centre: Vector2, bits: int, half: float) -> void:
	var thick: float = 8.0
	var gap: float = 14.0
	for i in range(6):
		var y: float = top_centre.y + float(5 - i) * gap
		var yang: bool = ((bits >> i) & 1) == 1
		if yang:
			g.draw_rect(Rect2(top_centre.x - half, y, half * 2.0, thick), INK, true)
		else:
			g.draw_rect(Rect2(top_centre.x - half, y, half * 0.8, thick), INK, true)
			g.draw_rect(Rect2(top_centre.x + half * 0.2, y, half * 0.8, thick), INK, true)


## A quarter gauge: a 90 degree sweep with a needle and a caption.
func _quarter(g: Control, centre: Vector2, radius: float, value: float, tint: Color, caption: String) -> void:
	var from: float = PI
	var span: float = PI * 0.5
	g.draw_arc(centre, radius, from, from + span, 24, WIRE, 3.0)
	g.draw_arc(centre, radius, from, from + span * clampf(value, 0.0, 1.0), 24, tint, 5.0)
	var ang: float = from + span * clampf(value, 0.0, 1.0)
	g.draw_line(centre, centre + Vector2(cos(ang), sin(ang)) * radius, tint, 2.0)
	_line(g, Vector2(centre.x - radius, centre.y + 16.0), caption, INK, 10)


## A full ring filled clockwise from the top, with two captions in the middle.
func _arc(g: Control, centre: Vector2, radius: float, value: float, tint: Color,
		title: String, caption: String) -> void:
	g.draw_arc(centre, radius, 0.0, TAU, 40, WIRE, 3.0)
	var v: float = clampf(value, 0.0, 1.0)
	if v > 0.0:
		g.draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * v, 40, tint, 6.0)
	_centred(g, Vector2(centre.x, centre.y - 2.0), title, INK, 11)
	_centred(g, Vector2(centre.x, centre.y + 14.0), caption, DIM, 10)


func _line(g: Control, at: Vector2, text: String, tint: Color, size_px: int) -> void:
	var font: Font = g.get_theme_default_font()
	if font == null:
		return
	g.draw_string(font, at + Vector2(0.0, float(size_px)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, tint)


func _centred(g: Control, at: Vector2, text: String, tint: Color, size_px: int) -> void:
	var font: Font = g.get_theme_default_font()
	if font == null:
		return
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px).x
	g.draw_string(font, at - Vector2(w * 0.5, 0.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, tint)


static func _gb(bytes: int) -> String:
	return "%.1f GB" % (float(bytes) / 1073741824.0)


## ---------------------------------------------------- panel 8's gauge ----

## THE THREE NUMBERS THE GAUGE IS STANDING ON: the hours it has shifted this
## person's day by, how sure it is of that, and the chapter its own rules put
## the store's walk in. Recomputed on every beat; it is three reads and a
## format, and it is the only place on this panel the gauge is named.
func _sync_gauge_row() -> void:
	if _gauge_label != null:
		_gauge_label.text = gauge_text()


## The same line as text, for a test or a tool.
func gauge_text() -> String:
	if _gauge == null:
		return "gauge —"
	## THE STAGE IS THE ORGANISM'S OWN, pushed in on the phase snapshot off
	## "/body". Nothing here reads the store's walk any more.
	var stage: int = _stage
	var word: String = _stage_word if _stage_word != "" else "ordinary"
	return "gauge  offset %+.2fh  conf %.2f  stage %d %s (%s)" % [
		float(_gauge.call("get_field", "clock_offset_h", 0.0)),
		float(_gauge.call("get_field", "confidence", 0.0)),
		stage, String(_gauge.call("stage_name", stage)), word]


## A CORRECTION FROM THE GLASS, refused unless the gauge itself allows it.
## `field` is a dotted key in [method HexyGauge.clamps]; anything else is a
## no-op. This is the ONLY write the dashboard is allowed to make, and it
## writes interpretation, never state.
func correct_gauge(field: String, value: Variant) -> bool:
	if _gauge == null:
		return false
	var ok: bool = bool(_gauge.call("correct", field, value))
	_sync_gauge_row()
	return ok
