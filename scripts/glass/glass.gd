class_name Glass
extends Control

## THE WHOLE SURFACE, AND NOTHING BEHIND IT.
##
## One portrait Control: the figure at the top, the creature in the middle
## inside a ring of sixteen seats, the becoming and the answer under it, a
## composer pill at the foot, and one sheet behind the plus that holds
## everything the glass could not afford to show at once.
##
## TAP ONLY. There is no drag, no long press, no swipe and no hidden gesture on
## this glass. Every act a person can perform is a visible thing they touch
## once, which is why a hit map is built at layout time: the sixteen seats and
## the field under them are laid out so that exactly ONE target can answer any
## given point. A surface where two things might both be right is a surface
## that will eventually be wrong.
##
## IT OWNS NO STATE. The store is the only truth; the glass reads it and writes
## back through its setters. The preview lines (a neighbour figure, the
## sentence of a seat) are deliberately NOT written to the store: a person
## looking at something is not the same as the app having decided it, and a few
## seconds later the glass shows the truth again with nothing to undo.
##
## ASCII, except the figures. Hexagram and trigram glyphs are the two things a
## font must carry; every other character on this surface is plain ASCII so it
## renders identically on a phone with nothing installed.

const FLASH_MS: int = 4000
const PREVIEW_MS: int = 3000

## Human seat names by trigram code, matching the Ba-Gua stations the old dual
## mandala used. ASCII, because a label is not a glyph.
const HUMAN_LABELS: Array[String] = [
	"Sleep Rest", "Steps", "Hydration", "Grip",
	"Deep Focus", "Active Gaze", "Breath", "Posture",
]

var _store: Node = null
var _qwen: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
var _creature: Node = null

var _top: Button = null
## The side of the creature's stage, in viewport pixels. It is square and it
## does not change; only the scale it is drawn at does.
const STAGE_PX: int = 640

## The sheet's ground: the project's own default clear colour, so the one dark
## in this app is the one dark on the sheet.
const SHEET_DARK: Color = Color(0.09, 0.1, 0.13, 1.0)
const SHEET_ALPHA: float = 0.96

## What holds the judgement and the two sentences apart on the answer line. A
## space let three sentences run together into one long unreadable ribbon.
const JOIN: String = " | "

var _center: Control = null
var _svc: SubViewportContainer = null
var _view: SubViewport = null
var _field_tap: Control = null
var _ring: Control = null
var _seats: Array[Button] = ([] as Array[Button])

var _becomes: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _wheel_btn: Button = null
var _answer: Label = null

var _plus: Button = null
var _text: LineEdit = null
var _mic: Button = null
var _send: Button = null

var _sheet: Control = null
var _scrim: Control = null
var _sheet_rows: Array[Control] = ([] as Array[Control])
var _tier_pick: OptionButton = null
var _name_field: LineEdit = null
var _period_field: SpinBox = null
var _room_box: VBoxContainer = null
var _room_line: Label = null

var _use_body_wheel: bool = false
var _preview_bits: int = -1
var _flash_until: int = 0
var _preview_until: int = 0
var _stream: String = ""
var _who: String = "hexy"


# -- building ----------------------------------------------------------------

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_top()
	_refresh_bottom()
	set_process(true)


func _build() -> void:
	var page := VBoxContainer.new()
	page.name = "Page"
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	page.offset_left = 12.0
	page.offset_top = 12.0
	page.offset_right = -12.0
	page.offset_bottom = -12.0
	add_child(page)

	_top = Button.new()
	_top.name = "Top"
	_top.flat = true
	_top.custom_minimum_size = Vector2(0.0, 76.0)
	_top.add_theme_font_size_override("font_size", 28)
	_top.pressed.connect(tap_cast)
	page.add_child(_top)

	_center = Control.new()
	_center.name = "Center"
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.custom_minimum_size = Vector2(0.0, 420.0)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.resized.connect(_layout_center)
	page.add_child(_center)
	_build_center()

	page.add_child(_build_bottom())
	page.add_child(_build_pill())

	_build_sheet()


func _build_center() -> void:
	_svc = SubViewportContainer.new()
	_svc.name = "Stage"
	_svc.stretch = true
	_svc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_svc.size = Vector2(float(STAGE_PX), float(STAGE_PX))
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(_svc)

	_view = SubViewport.new()
	_view.name = "Stagelet"
	_view.size = Vector2i(STAGE_PX, STAGE_PX)
	_view.transparent_bg = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_svc.add_child(_view)

	_field_tap = Control.new()
	_field_tap.name = "Field"
	_field_tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field_tap.mouse_filter = Control.MOUSE_FILTER_STOP
	_field_tap.gui_input.connect(_on_field_input)
	_center.add_child(_field_tap)

	_ring = Control.new()
	_ring.name = "Ring"
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(_ring)

	for family in range(2):
		for slot in range(8):
			var station: Dictionary = BodyDial2D.MACHINE_STATIONS[slot]
			var seat := Seat.new()
			seat.family = family
			seat.trigram = int(station.get("trigram", 0))
			seat.angle = float(station.get("angle", 0.0))
			seat.caption = _seat_label(family, seat.trigram)
			seat.glyph = KingWen.trigram_glyph(seat.trigram)
			seat.flat = true
			seat.focus_mode = Control.FOCUS_NONE
			seat.pressed.connect(_on_seat_pressed.bind(family, seat.trigram))
			_ring.add_child(seat)
			_seats.append(seat)


func _build_bottom() -> Control:
	var box := VBoxContainer.new()
	box.name = "Bottom"
	box.add_theme_constant_override("separation", 6)

	var row := HBoxContainer.new()
	row.name = "Wheel"
	_prev_btn = Button.new()
	_prev_btn.text = "<"
	_prev_btn.custom_minimum_size = Vector2(64.0, 48.0)
	_prev_btn.pressed.connect(_on_prev)
	row.add_child(_prev_btn)

	_becomes = Label.new()
	_becomes.name = "Becomes"
	_becomes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_becomes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_becomes.text = "holds"
	row.add_child(_becomes)

	_next_btn = Button.new()
	_next_btn.text = ">"
	_next_btn.custom_minimum_size = Vector2(64.0, 48.0)
	_next_btn.pressed.connect(_on_next)
	row.add_child(_next_btn)

	_wheel_btn = Button.new()
	_wheel_btn.text = "body"
	_wheel_btn.custom_minimum_size = Vector2(72.0, 48.0)
	_wheel_btn.pressed.connect(_on_wheel_toggle)
	row.add_child(_wheel_btn)
	box.add_child(row)

	_answer = Label.new()
	_answer.name = "Answer"
	_answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_answer.custom_minimum_size = Vector2(0.0, 84.0)
	_answer.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(_answer)
	return box


func _build_pill() -> Control:
	var row := HBoxContainer.new()
	row.name = "Pill"
	row.add_theme_constant_override("separation", 6)

	_plus = Button.new()
	_plus.text = "+"
	_plus.custom_minimum_size = Vector2(56.0, 52.0)
	_plus.pressed.connect(open_sheet)
	row.add_child(_plus)

	_text = LineEdit.new()
	_text.name = "Text"
	_text.placeholder_text = "ask"
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.text_submitted.connect(func(t: String) -> void: send_text(t))
	row.add_child(_text)

	_mic = Button.new()
	_mic.text = "mic"
	_mic.disabled = true
	_mic.custom_minimum_size = Vector2(64.0, 52.0)
	row.add_child(_mic)

	_send = Button.new()
	_send.text = "send"
	_send.custom_minimum_size = Vector2(80.0, 52.0)
	_send.pressed.connect(_on_send_pressed)
	row.add_child(_send)
	return row


func _build_sheet() -> void:
	_scrim = Control.new()
	_scrim.name = "Scrim"
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	_scrim.visible = false
	add_child(_scrim)

	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left = 16.0
	_sheet.offset_top = 64.0
	_sheet.offset_right = -16.0
	_sheet.offset_bottom = -16.0
	_sheet.visible = false
	# THE SHEET IS NOT A WINDOW. A PanelContainer with the default theme is
	# see-through enough that the creature swims behind the sixteen rows and
	# the text becomes unreadable on a phone. The ground is the project's own
	# clear colour at alpha 0.96 -- not 1.0, so the sheet still reads as glass
	# laid ON the app rather than a second app.
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(SHEET_DARK.r, SHEET_DARK.g, SHEET_DARK.b, SHEET_ALPHA)
	skin.corner_radius_top_left = 12
	skin.corner_radius_top_right = 12
	skin.corner_radius_bottom_left = 12
	skin.corner_radius_bottom_right = 12
	skin.content_margin_left = 12.0
	skin.content_margin_right = 12.0
	skin.content_margin_top = 12.0
	skin.content_margin_bottom = 12.0
	_sheet.add_theme_stylebox_override("panel", skin)
	add_child(_sheet)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	_sheet.add_child(scroll)
	var col := VBoxContainer.new()
	col.name = "Groups"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	col.add_child(_heading("MACHINE"))
	for i in range(8):
		var row_m: Control = _sheet_row(0, i)
		_sheet_rows.append(row_m)
		col.add_child(row_m)

	col.add_child(_heading("HUMAN"))
	for i in range(8):
		var row_h: Control = _sheet_row(1, i)
		_sheet_rows.append(row_h)
		col.add_child(row_h)

	col.add_child(_heading("ROOM"))
	_room_box = VBoxContainer.new()
	_room_box.name = "Peers"
	col.add_child(_room_box)
	_room_line = Label.new()
	_room_line.name = "RoomFigure"
	_room_line.text = "room: nobody yet"
	col.add_child(_room_line)

	col.add_child(_heading("SETTINGS"))
	_tier_pick = OptionButton.new()
	_tier_pick.name = "Tier"
	_tier_pick.item_selected.connect(_on_tier_chosen)
	col.add_child(_tier_pick)

	_name_field = LineEdit.new()
	_name_field.name = "Name"
	_name_field.placeholder_text = "name"
	_name_field.text = _who
	_name_field.text_submitted.connect(_on_name_submitted)
	col.add_child(_name_field)

	_period_field = SpinBox.new()
	_period_field.name = "Period"
	_period_field.min_value = 500.0
	_period_field.max_value = 60000.0
	_period_field.step = 500.0
	_period_field.value = 3500.0
	_period_field.value_changed.connect(_on_period_changed)
	col.add_child(_period_field)

	var close := Button.new()
	close.name = "Close"
	close.text = "close"
	close.pressed.connect(close_sheet)
	col.add_child(close)


static func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 22)
	return l


func _sheet_row(family: int, index: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row%d_%d" % [family, index]
	row.set_meta("family", family)
	row.set_meta("index", index)

	var label := Label.new()
	label.name = "Label"
	label.custom_minimum_size = Vector2(160.0, 0.0)
	label.text = _seat_label(family, index)
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(90.0, 18.0)
	row.add_child(bar)

	var say := Label.new()
	say.name = "Sentence"
	say.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	say.clip_text = true
	say.text = "not sensed"
	row.add_child(say)
	return row


# -- wiring ------------------------------------------------------------------

## The four doors the glass is allowed through. Nothing else reaches it.
func bind(store: Node, qwen: Node, mnn: Node, wmn: Node) -> void:
	_store = store
	_qwen = qwen
	_mnn = mnn
	_wmn = wmn
	if _store != null:
		if not _store.hexagram_changed.is_connected(_on_hexagram_changed):
			_store.hexagram_changed.connect(_on_hexagram_changed)
		if not _store.answer_changed.is_connected(_on_answer_changed):
			_store.answer_changed.connect(_on_answer_changed)
		if not _store.machine_changed.is_connected(_on_family_changed):
			_store.machine_changed.connect(_on_family_changed)
		if not _store.human_changed.is_connected(_on_family_changed):
			_store.human_changed.connect(_on_family_changed)
	if _mnn != null and not _mnn.token.is_connected(_on_token):
		_mnn.token.connect(_on_token)
	_fill_tiers()
	_refresh_top()
	_refresh_bottom()
	_refresh_seats()


func set_senses(senses: Node) -> void:
	_senses = senses
	if _senses != null and _period_field != null:
		_period_field.value = float(_senses.period_ms)
	_relabel()
	_refresh_seats()


func set_creature(creature: Node) -> void:
	_creature = creature
	if creature == null:
		return
	if creature.get_parent() != null:
		creature.get_parent().remove_child(creature)
	_view.add_child(creature)
	if not creature.throw_requested.is_connected(_on_throw_requested):
		creature.throw_requested.connect(_on_throw_requested)


func set_who(who_name: String) -> void:
	var clean: String = who_name.strip_edges()
	if clean != "":
		_who = clean
	if _name_field != null:
		_name_field.text = _who


func who() -> String:
	return _who


# -- the acts ----------------------------------------------------------------

## Three coins, six times, seeded by this instant and this person. The one act
## on the glass that is allowed to overrule the sixteen.
func tap_cast() -> Dictionary:
	var now: int = _now_ms()
	var cast: Dictionary = Cast.tap_cast(Cast.seed_of(now, _who, 0))
	if _store != null:
		_store.set_hexagram({
			"bits": int(cast.get("bits", 0)),
			"moving": int(cast.get("moving", 0)),
			"throws": cast.get("throws", []),
			"when": now,
			"who": _who,
			"source": "tap",
			"sig": "",
		})
	return cast


func send_text(text: String) -> bool:
	var q: String = text.strip_edges()
	if q == "" or _qwen == null:
		return false
	_stream = ""
	if _text != null:
		_text.text = ""
	_qwen.ask(q)
	return true


func open_sheet() -> void:
	_refresh_sheet()
	_scrim.visible = true
	_sheet.visible = true


func close_sheet() -> void:
	_scrim.visible = false
	_sheet.visible = false


func sheet_open() -> bool:
	return _sheet != null and _sheet.visible


func sheet_row_count() -> int:
	return _sheet_rows.size()


func top_text() -> String:
	return _top.text


func becomes_text() -> String:
	return _becomes.text


func answer_text() -> String:
	return _answer.text


func top_button() -> Button:
	return _top


func plus_button() -> Button:
	return _plus


# -- events ------------------------------------------------------------------

func _on_send_pressed() -> void:
	send_text(_text.text)


func _on_name_submitted(t: String) -> void:
	set_who(t)


func _on_field_input(event: InputEvent) -> void:
	if not _is_release(event) or _creature == null:
		return
	_field_tap.accept_event()
	_creature.tap(_to_stage(event.position))


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false


## A point on the glass, in the pixels of the stage viewport.
##
## The stage is a SQUARE and the panel usually is not, so the mapping is a
## letterbox: one scale for both axes, taken from the shorter side, with the
## leftover split evenly as a margin. Scaling x and y apart would put the
## creature's answer somewhere the finger did not point.
func _to_stage(p: Vector2) -> Vector2:
	var box: Vector2 = _center.size
	var side: float = minf(box.x, box.y)
	if side <= 0.0:
		return p
	var v := Vector2(_view.size)
	var off: Vector2 = (box - Vector2(side, side)) * 0.5
	var q: Vector2 = (p - off) / side
	return Vector2(clampf(q.x, 0.0, 1.0) * v.x, clampf(q.y, 0.0, 1.0) * v.y)


func _on_seat_pressed(family: int, trigram: int) -> void:
	_flash(_sentence_of(family, trigram))


func _on_throw_requested(_trigram: int) -> void:
	tap_cast()


func _on_prev() -> void:
	_step_wheel(-1)


func _on_next() -> void:
	_step_wheel(1)


func _step_wheel(delta: int) -> void:
	var bits: int = _bits()
	var next: int = bits
	if _use_body_wheel:
		next = KingWen.body_next(bits) if delta > 0 else KingWen.body_prev(bits)
	else:
		next = KingWen.head_next(bits) if delta > 0 else KingWen.head_prev(bits)
	_preview_bits = next
	_preview_until = Time.get_ticks_msec() + PREVIEW_MS
	_refresh_bottom()


func _on_wheel_toggle() -> void:
	_use_body_wheel = not _use_body_wheel
	_wheel_btn.text = "head" if _use_body_wheel else "body"


func _on_scrim_input(event: InputEvent) -> void:
	if _is_release(event):
		close_sheet()


func _on_hexagram_changed(_h: Dictionary) -> void:
	_preview_bits = -1
	_preview_until = 0
	_refresh_top()
	_refresh_bottom()


func _on_family_changed(_f: Dictionary) -> void:
	_refresh_seats()
	if sheet_open():
		_refresh_sheet()


func _on_answer_changed(a: String) -> void:
	_stream = ""
	if Time.get_ticks_msec() >= _flash_until:
		_answer.text = _joined(a)


func _on_token(t: String) -> void:
	_stream += t
	if Time.get_ticks_msec() >= _flash_until:
		_answer.text = _joined(_stream)


func _on_tier_chosen(index: int) -> void:
	if _mnn == null or index < 0:
		return
	_mnn.load_tier(String(_tier_pick.get_item_metadata(index)))


func _on_period_changed(v: float) -> void:
	if _senses != null:
		_senses.period_ms = int(v)


# -- refreshing --------------------------------------------------------------

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if _flash_until > 0 and now >= _flash_until:
		_flash_until = 0
		_answer.text = _joined(String(_store.answer)) if _store != null else ""
	if _preview_until > 0 and now >= _preview_until:
		_preview_until = 0
		_preview_bits = -1
		_refresh_bottom()


func _bits() -> int:
	return (int(_store.primary()) if _store != null else 0) & 63


func _moving() -> int:
	return (int(_store.hexagram.get("moving", 0)) if _store != null else 0) & 63


func _refresh_top() -> void:
	if _top == null:
		return
	var b: int = _bits()
	_top.text = "now - %d %s %s  %s" % [
		KingWen.number(b), KingWen.pinyin(b), KingWen.name(b), KingWen.glyph(b)]


func _refresh_bottom() -> void:
	if _becomes == null:
		return
	if _preview_bits >= 0:
		var p: int = _preview_bits & 63
		_becomes.text = "wheel %d %s %s  %s" % [
			KingWen.number(p), KingWen.pinyin(p), KingWen.name(p), KingWen.glyph(p)]
		return
	var b: int = _bits()
	var m: int = _moving()
	if m == 0:
		_becomes.text = "holds"
		return
	var t: int = Cast.transform(b, m)
	_becomes.text = "becomes %d %s %s  %s" % [
		KingWen.number(t), KingWen.pinyin(t), KingWen.name(t), KingWen.glyph(t)]


func _refresh_seats() -> void:
	var rows: Dictionary = _score_rows()
	var m_win: int = int(_store.machine.get("trigram", 0)) if _store != null else -1
	var h_win: int = int(_store.human.get("trigram", 0)) if _store != null else -1
	for node in _seats:
		var seat := node as Seat
		var row: Array = rows.get("machine" if seat.family == 0 else "human", [])
		seat.score = float(row[seat.trigram]) if seat.trigram < row.size() else 0.0
		seat.winner = seat.trigram == (m_win if seat.family == 0 else h_win)
		seat.queue_redraw()


## The hit map. Two concentric rings of eight; a seat is 2 * pad across and the
## two radii are further apart than that, so no point on the glass can land
## inside two seats and the field beneath only ever sees what neither answered.
func _layout_center() -> void:
	if _center == null or _view == null:
		return
	var box: Vector2 = _center.size
	if box.x < 8.0 or box.y < 8.0:
		return
	# The stage stays a fixed square of STAGE_PX pixels -- `stretch` would
	# otherwise hand the viewport the panel's own oblong size and render the
	# creature squashed. The container keeps that square and is SCALED into the
	# centred square of the panel instead, so one number scales both axes.
	var side: float = minf(box.x, box.y)
	var k: float = side / float(STAGE_PX)
	_svc.size = Vector2(float(STAGE_PX), float(STAGE_PX))
	_svc.scale = Vector2(k, k)
	_svc.position = (box - Vector2(side, side)) * 0.5
	var mid: Vector2 = box * 0.5
	var r: float = minf(box.x, box.y) * 0.5
	var pad: float = minf(34.0, r * 0.14)
	for node in _seats:
		var seat := node as Seat
		var radius: float = r * (0.58 if seat.family == 0 else 0.92) - pad
		var c: Vector2 = mid + Vector2(cos(seat.angle), sin(seat.angle)) * radius
		seat.position = c - Vector2(pad, pad)
		seat.size = Vector2(pad * 2.0, pad * 2.0)


func _refresh_sheet() -> void:
	for row in _sheet_rows:
		var family: int = int(row.get_meta("family", 0))
		var index: int = int(row.get_meta("index", 0))
		var bar := row.get_node("Bar") as ProgressBar
		var say := row.get_node("Sentence") as Label
		var label := row.get_node("Label") as Label
		label.text = _seat_label(family, index)
		bar.value = _score_of(family, index)
		say.text = _sentence_of(family, index)
	_refresh_room()


func _refresh_room() -> void:
	if _room_box == null:
		return
	for child in _room_box.get_children():
		_room_box.remove_child(child)
		child.queue_free()
	var peers: Array = []
	if _wmn != null and _wmn.has_method("peers"):
		peers = _wmn.peers()
	for p in peers:
		var d: Dictionary = p as Dictionary
		var bits: int = int(d.get("bits", 0)) & 63
		var l := Label.new()
		l.text = "%s  %s  %s" % [String(d.get("who", "")), KingWen.glyph(bits), String(d.get("band", ""))]
		_room_box.add_child(l)
	if peers.is_empty():
		var none := Label.new()
		none.text = "nobody yet"
		_room_box.add_child(none)
	var rb: int = (int(_store.room.get("bits", 0)) if _store != null else 0) & 63
	var count: int = int(_store.room.get("peers", 0)) if _store != null else 0
	_room_line.text = "room %d %s %s  %s  peers %d" % [
		KingWen.number(rb), KingWen.pinyin(rb), KingWen.name(rb), KingWen.glyph(rb), count]


func _fill_tiers() -> void:
	if _tier_pick == null or _mnn == null:
		return
	_tier_pick.clear()
	var i: int = 0
	for row in _mnn.tiers():
		var d: Dictionary = row as Dictionary
		_tier_pick.add_item("%s %s" % [String(d.get("tier", "")), String(d.get("params", ""))])
		_tier_pick.set_item_metadata(i, String(d.get("id", "")))
		i += 1


func _relabel() -> void:
	for node in _seats:
		var seat := node as Seat
		seat.caption = _seat_label(seat.family, seat.trigram)
		seat.queue_redraw()


# -- reading the sixteen -----------------------------------------------------

func _score_rows() -> Dictionary:
	if _creature != null and _creature.has_method("scores"):
		return _creature.scores()
	if _senses != null and _senses.has_method("scores"):
		return _senses.scores()
	return {"machine": [], "human": []}


func _score_of(family: int, index: int) -> float:
	var row: Array = _score_rows().get("machine" if family == 0 else "human", [])
	return float(row[index]) if index < row.size() else 0.0


func _sentence_of(family: int, index: int) -> String:
	if _senses != null and _senses.has_method("sense"):
		return String(_senses.sense(family, index).sentence())
	if _store == null:
		return "not sensed"
	var f: Dictionary = _store.machine if family == 0 else _store.human
	if int(f.get("trigram", -1)) == index:
		return String(f.get("sentence", "not sensed"))
	return "not sensed"


## The answer, its machine sentence and its human sentence, held apart.
##
## The model is handed the two sentences and hands them back glued to the
## judgement with spaces, which on a phone is one ribbon of prose with three
## unrelated thoughts in it. Rather than reach into the model's prompt, the
## two sentences are recognised where they are -- at the tail, in order -- and
## the seams between them are widened to [constant JOIN]. An answer that never
## carried them is returned untouched.
func _joined(text: String) -> String:
	var line: String = text.strip_edges()
	if line == "":
		return line
	var tail: Array[String] = ([] as Array[String])
	for family in [1, 0]:
		var said: String = _family_sentence(family)
		if said == "" or not line.ends_with(said):
			continue
		var cut: String = line.substr(0, line.length() - said.length())
		if cut.strip_edges() == "":
			continue
		line = cut.strip_edges()
		tail.push_front(said)
	if tail.is_empty():
		return line
	return line + JOIN + JOIN.join(tail)


## The sentence the store is currently showing for one family, "" when none.
func _family_sentence(family: int) -> String:
	if _store == null:
		return ""
	var f: Dictionary = _store.machine if family == 0 else _store.human
	return String(f.get("sentence", "")).strip_edges()


func _seat_label(family: int, index: int) -> String:
	if _senses != null and _senses.has_method("sense"):
		var l: String = String(_senses.sense(family, index).label())
		if l != "":
			return l
	if family == 1:
		return HUMAN_LABELS[clampi(index, 0, 7)]
	for station in BodyDial2D.MACHINE_STATIONS:
		if int((station as Dictionary).get("trigram", -1)) == index:
			return String((station as Dictionary).get("name", ""))
	return Sense.TRIGRAMS[clampi(index, 0, 7)]


func _flash(text: String) -> void:
	_answer.text = text
	_flash_until = Time.get_ticks_msec() + FLASH_MS


func _now_ms() -> int:
	if _wmn != null and _wmn.has_method("now_ms"):
		return int(_wmn.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


# -- one seat ----------------------------------------------------------------

## A single target on the ring: a trigram glyph, the name of its sense, and how
## loudly that sense is speaking, drawn as an arc filling from the top.
class Seat extends Button:
	var family: int = 0
	var trigram: int = 0
	var angle: float = 0.0
	var caption: String = ""
	var glyph: String = ""
	var score: float = 0.0
	var winner: bool = false

	func _draw() -> void:
		var mid: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.42
		if r <= 1.0:
			return
		var dim := Color(0.45, 0.5, 0.6, 0.55)
		var lit := Color(1.0, 0.78, 0.22, 0.95) if family == 0 else Color(0.35, 0.85, 1.0, 0.95)
		draw_arc(mid, r, 0.0, TAU, 28, dim, 1.5, true)
		if score > 0.0:
			var a: float = -PI * 0.5
			draw_arc(mid, r, a, a + TAU * clampf(score, 0.0, 1.0), 28, lit, 3.0, true)
		if winner:
			draw_arc(mid, r * 1.22, 0.0, TAU, 28, lit, 2.0, true)
		var font: Font = get_theme_default_font()
		if font == null:
			return
		var gs: int = int(maxf(12.0, r))
		var gw: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, gs).x
		draw_string(font, mid + Vector2(-gw * 0.5, r * 0.35), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, gs, lit if winner else dim)
		var cw: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
		draw_string(font, mid + Vector2(-cw * 0.5, r + 13.0), caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, dim)
