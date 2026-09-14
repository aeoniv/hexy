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
## IT KNOWS NOTHING IT WAS NOT HANDED. Store, mnn, wmn, senses, alchemy and
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
}

const HEIGHTS: Dictionary = {
	"identity": 210.0,
	"engine": 150.0,
	"figures": 168.0,
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

var _store: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
var _alchemy: Node = null
var _qwen: Node = null
## The glass that owns this panel, read only for the words it already holds
## (the node name, the token stream). Never written to.
var _host: Node = null

var _panels: Dictionary = {}
var _geoms: Dictionary = {}
var _beat: Timer = null
var _fps: PackedFloat32Array = PackedFloat32Array()
var _snap: Dictionary = {}


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

	if kind == "fly":
		## The fly panel carries the creature's own radar beside its bars: the
		## one drawing on this surface that is allowed its own clock.
		var row := HBoxContainer.new()
		row.name = "Row"
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		radar = FlyCalciumRadar2D.new()
		radar.name = "DashRadar"
		radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radar.radar_radius = 72.0
		radar.ring_thickness = 16.0
		radar.show_neuromodulators = false
		radar.custom_minimum_size = Vector2(180.0, float(HEIGHTS["fly"]))
		row.add_child(radar)
		row.add_child(geom)
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


# -- wiring ------------------------------------------------------------------

## Everything this panel is allowed to know, handed over at once. Qwen is
## optional because the glass binds it separately; alchemy arrives late.
func bind(store: Node, mnn: Node, wmn: Node, senses: Node, alchemy: Node, qwen: Node = null) -> void:
	_store = store
	_mnn = mnn
	_wmn = wmn
	_senses = senses
	_alchemy = alchemy
	_qwen = qwen


func set_senses(senses: Node) -> void:
	_senses = senses


func set_alchemy(alchemy: Node) -> void:
	_alchemy = alchemy


func set_host(host: Node) -> void:
	_host = host


# -- opening and closing -----------------------------------------------------

func open() -> void:
	visible = true
	move_to_front()
	_refresh()
	if _beat != null:
		_beat.start()


func close() -> void:
	visible = false
	if _beat != null:
		_beat.stop()


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

	if radar != null:
		var fs: Dictionary = snap["fly"].get("state", {}) as Dictionary
		if not fs.is_empty():
			radar.set_state(fs)
		if _wmn != null and _wmn.has_method("peer_headings"):
			radar.set_peer_headings(_wmn.peer_headings() as Dictionary)

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
	return {
		"available": bool(_mnn.available()) if _mnn != null and _mnn.has_method("available") else false,
		"backend": String(_mnn.backend_name()) if _mnn != null and _mnn.has_method("backend_name") else "none",
		"tier": String(_mnn.tier()) if _mnn != null and _mnn.has_method("tier") else "",
		"tiers": tiers,
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


func _read_fires() -> Dictionary:
	if _alchemy != null and _alchemy.has_method("state"):
		return _alchemy.call("state") as Dictionary
	var still: float = float(_senses.stillness()) if _senses != null and _senses.has_method("stillness") else 0.0
	return {
		"dwell_s": still, "dwell_needed_s": 2.5,
		"refractory_s": 0.0, "refractory_needed_s": 3.5,
		"last_reason": "", "flex": false,
	}


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
		_line(g, Vector2(136.0, y), "%s  %s  %d ms" % [
			String(p.get("who", "?")).substr(0, 12), String(p.get("band", "")),
			int(p.get("last_seen_ms", 0))], DIM, 10)
		y += 15.0


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
