class_name MobileHudStore
extends Control

## THE OWNER'S MOBILE HUD, DRIVEN BY THE NEW CORE.
##
## This is scripts/mobile_hud.gd with one thing swapped out and nothing else
## moved: SAME node names, SAME layout, SAME styles, SAME two dials, SAME top
## card and thought bubble. What changed is where the numbers come from. The
## old HUD built a SensorOracle of its own and a MnnRuntime of its own and read
## them directly; this one is handed the store, Qwen, Mnn and Wmn in bind() and
## reads nothing it was not given.
##
## WHAT WAS REMOVED, AND WHY:
##   - the four persona tabs (Hexy / Oracle / Brain / Telemetry). They were four
##     names for one surface, and everything they hid -- the sixteen, the room,
##     the model tier -- now lives in the sheet behind the plus, where it can be
##     read in one place instead of found in four.
##   - SensorOracle. The sixteen elect the two trigrams now, and the store says
##     which won. Nothing here shakes, and nothing here casts by accident.
##   - the two hard-coded prompt strings. Qwen owns the prompt; ASK asks it.
##
## WHAT WAS FIXED:
##   - the old `_update_telemetry_view` formatted a King Wen line through
##     `"0b%06s"` against `String.num_int64(...)`, which is a zero-padded
##     STRING conversion and throws at runtime on the telemetry tab. There is
##     no such line here: the figure is printed by KingWen, which returns a
##     number and a name and never a format hole.
##
## TAP ONLY. Both dials are the tap-only subclasses; no drag survives on this
## surface. Every act is a visible target touched once.

## What holds the judgement and the two sentences apart on the answer line.
const JOIN: String = " | "
const FLASH_MS: int = 4000
const PREVIEW_MS: int = 3000
const SHEET_DARK: Color = Color(0.09, 0.1, 0.13, 1.0)
const SHEET_ALPHA: float = 0.96

## Human seat names by trigram code, used when the sixteen are not attached.
const HUMAN_LABELS: Array[String] = [
	"Sleep Rest", "Steps", "Hydration", "Grip",
	"Deep Focus", "Active Gaze", "Breath", "Posture",
]

@onready var top_bar: PanelContainer = $TopBar
@onready var lbl_title: Label = $TopBar/Margin/HBox/Title
@onready var btn_geo_toggle: Button = $TopBar/Margin/HBox/BtnGeoToggle
@onready var btn_cast_mode: Button = $TopBar/Margin/HBox/BtnCastMode
@onready var btn_mode_toggle: Button = $TopBar/Margin/HBox/BtnModeToggle
@onready var lbl_fps: Label = $TopBar/Margin/HBox/FPS

@onready var hex_card: PanelContainer = $HexCard
@onready var lbl_hex_char: Label = $HexCard/Margin/VBox/HBox/HexChar
@onready var lbl_hex_title: Label = $HexCard/Margin/VBox/HBox/VBox/HexTitle
@onready var lbl_hex_subtitle: Label = $HexCard/Margin/VBox/HBox/VBox/HexSubtitle
@onready var lbl_moving_line: Label = $HexCard/Margin/VBox/MovingLine

@onready var thought_bubble: PanelContainer = $ThoughtBubble
@onready var lbl_thought: Label = $ThoughtBubble/Margin/ThoughtLabel

@onready var body_dial_container: Control = $BodyMandalaContainer
@onready var body_dial: BodyDialTap = $BodyMandalaContainer/BodyDial
@onready var mandala_container: Control = $MandalaContainer
@onready var mandala_dial: MandalaDialTap = $MandalaContainer/Dial

@onready var btn_prev: Button = $Controls/HBox/BtnPrev
@onready var btn_cast: Button = $Controls/HBox/BtnCast
@onready var btn_ask: Button = $Controls/HBox/BtnAsk
@onready var btn_next: Button = $Controls/HBox/BtnNext

@onready var composer: PanelContainer = $Composer
@onready var btn_plus: Button = $Composer/HBox/BtnPlus
@onready var text_field: LineEdit = $Composer/HBox/Text
@onready var btn_mic: Button = $Composer/HBox/BtnMic
@onready var btn_send: Button = $Composer/HBox/BtnSend

var _store: Node = null
var _qwen: Node = null
var _mnn: Node = null
var _wmn: Node = null
var _senses: Node = null
var _creature: Node = null

var _sheet: PanelContainer = null
var _scrim: Control = null
var _sheet_rows: Array[Control] = ([] as Array[Control])
var _tier_pick: OptionButton = null
var _name_field: LineEdit = null
var _period_field: SpinBox = null
var _room_box: VBoxContainer = null
var _room_line: Label = null

var _use_body_wheel: bool = false
var _is_enhanced_mode: bool = true
var _preview_bits: int = -1
var _preview_until: int = 0
var _flash_until: int = 0
var _stream: String = ""
var _who: String = "hexy"


# -- building ----------------------------------------------------------------

func _ready() -> void:
	_build_sheet()
	body_dial.machine_station_clicked.connect(_on_machine_station_clicked)
	mandala_dial.human_station_clicked.connect(_on_human_station_clicked)
	mandala_dial.center_hub_clicked.connect(_on_center_hub_clicked)
	btn_geo_toggle.pressed.connect(_on_geo_toggle_pressed)
	btn_cast_mode.pressed.connect(_on_wheel_toggle_pressed)
	btn_mode_toggle.pressed.connect(_on_mode_toggle_pressed)
	btn_prev.pressed.connect(_on_prev_pressed)
	btn_next.pressed.connect(_on_next_pressed)
	btn_cast.pressed.connect(_on_cast_pressed)
	btn_ask.pressed.connect(_on_ask_pressed)
	btn_plus.pressed.connect(open_sheet)
	btn_send.pressed.connect(_on_send_pressed)
	text_field.text_submitted.connect(func(t: String) -> void: send_text(t))
	_refresh_card()
	_refresh_dials()
	set_process(true)


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
	# The sheet is laid ON the app, not beside it: the same dark the project
	# clears to, at alpha 0.96 so the creature is felt and not read through.
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
	_name_field.text_submitted.connect(func(t: String) -> void: set_who(t))
	col.add_child(_name_field)

	_period_field = SpinBox.new()
	_period_field.name = "Period"
	_period_field.min_value = 500.0
	_period_field.max_value = 60000.0
	_period_field.step = 500.0
	_period_field.value = 3500.0
	_period_field.value_changed.connect(_on_period_chosen)
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

## The four doors. Nothing else reaches this HUD.
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
		if not _store.room_changed.is_connected(_on_room_changed):
			_store.room_changed.connect(_on_room_changed)
	if _mnn != null and not _mnn.token.is_connected(_on_token):
		_mnn.token.connect(_on_token)
	_fill_tiers()
	_refresh_card()
	_refresh_dials()


## Optional: the sixteen, for the score arcs on both dials and the sheet rows.
func set_senses(senses: Node) -> void:
	_senses = senses
	if _senses != null and _period_field != null:
		_period_field.value = float(_senses.period_ms)
	_refresh_dials()


func set_creature(creature: Node) -> void:
	_creature = creature
	if _creature != null and _creature.has_method("geometry_name"):
		btn_geo_toggle.text = String(_creature.geometry_name()).to_upper()


func set_who(who_name: String) -> void:
	var clean: String = who_name.strip_edges()
	if clean != "":
		_who = clean
	if _name_field != null:
		_name_field.text = _who


func who() -> String:
	return _who


# -- the acts ----------------------------------------------------------------

## Three coins, six times, seeded by this instant and this person.
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
	text_field.text = ""
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


## The figure line on the owner's HexCard: number, pinyin, name, glyph.
func top_text() -> String:
	return lbl_hex_title.text


## The line under it: what the figure becomes, or the wheel's preview.
func becomes_text() -> String:
	return lbl_moving_line.text


## The thought bubble, which is where an answer lands.
func answer_text() -> String:
	return lbl_thought.text


func stage_visible() -> bool:
	return _is_enhanced_mode


# -- events ------------------------------------------------------------------

func _on_center_hub_clicked() -> void:
	tap_cast()


func _on_machine_station_clicked(trigram: int) -> void:
	_flash(_sentence_of(0, trigram))


func _on_human_station_clicked(trigram: int) -> void:
	_flash(_sentence_of(1, trigram))


func _on_cast_pressed() -> void:
	tap_cast()


func _on_ask_pressed() -> void:
	if _qwen == null:
		return
	_stream = ""
	_qwen.ask(Qwen.THOUGHT_QUESTION)


func _on_prev_pressed() -> void:
	_step_wheel(-1)


func _on_next_pressed() -> void:
	_step_wheel(1)


## The head wheel, one figure at a time, as a PREVIEW. Nothing is written to
## the store by looking: three seconds later the glass shows the truth again.
func _step_wheel(delta: int) -> void:
	var bits: int = _bits()
	var next: int = bits
	if _use_body_wheel:
		next = KingWen.body_next(bits) if delta > 0 else KingWen.body_prev(bits)
	else:
		next = KingWen.head_next(bits) if delta > 0 else KingWen.head_prev(bits)
	_preview_bits = next
	_preview_until = Time.get_ticks_msec() + PREVIEW_MS
	_refresh_card()


func _on_wheel_toggle_pressed() -> void:
	_use_body_wheel = not _use_body_wheel
	btn_cast_mode.text = "BODY WHEEL" if _use_body_wheel else "HEAD WHEEL"


func _on_geo_toggle_pressed() -> void:
	if _creature == null or _creature.ball == null:
		return
	_creature.ball.cycle_geometry_mode()
	btn_geo_toggle.text = String(_creature.geometry_name()).to_upper()


func _on_mode_toggle_pressed() -> void:
	_is_enhanced_mode = not _is_enhanced_mode
	btn_mode_toggle.text = "ENHANCED" if _is_enhanced_mode else "PURE"
	stage_visibility_changed.emit(_is_enhanced_mode)


## The bridge owns the stage; the HUD only says whether it should be lit.
signal stage_visibility_changed(on: bool)


func _on_send_pressed() -> void:
	send_text(text_field.text)


func _on_scrim_input(event: InputEvent) -> void:
	if _is_release(event):
		close_sheet()


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	return false


func _on_hexagram_changed(_h: Dictionary) -> void:
	_preview_bits = -1
	_preview_until = 0
	_refresh_card()


func _on_family_changed(_f: Dictionary) -> void:
	_refresh_card()
	_refresh_dials()
	if sheet_open():
		_refresh_sheet()


func _on_room_changed(_r: Dictionary) -> void:
	if sheet_open():
		_refresh_room()


func _on_answer_changed(a: String) -> void:
	_stream = ""
	if Time.get_ticks_msec() >= _flash_until:
		lbl_thought.text = _joined(a)


func _on_token(t: String) -> void:
	_stream += t
	if Time.get_ticks_msec() >= _flash_until:
		lbl_thought.text = _joined(_stream)


func _on_tier_chosen(index: int) -> void:
	if _mnn == null or index < 0:
		return
	_mnn.load_tier(String(_tier_pick.get_item_metadata(index)))


func _on_period_chosen(v: float) -> void:
	if _senses != null:
		_senses.period_ms = int(v)


# -- refreshing --------------------------------------------------------------

func _process(_delta: float) -> void:
	lbl_fps.text = "%d FPS" % Engine.get_frames_per_second()
	var now: int = Time.get_ticks_msec()
	if _flash_until > 0 and now >= _flash_until:
		_flash_until = 0
		lbl_thought.text = _joined(String(_store.answer)) if _store != null else ""
	if _preview_until > 0 and now >= _preview_until:
		_preview_until = 0
		_preview_bits = -1
		_refresh_card()


func _bits() -> int:
	return (int(_store.primary()) if _store != null else 0) & 63


func _moving() -> int:
	return (int(_store.hexagram.get("moving", 0)) if _store != null else 0) & 63


func _refresh_card() -> void:
	if lbl_hex_title == null:
		return
	var b: int = _bits()
	lbl_hex_char.text = KingWen.zh(b)
	lbl_hex_title.text = "now - %d %s %s  %s" % [
		KingWen.number(b), KingWen.pinyin(b), KingWen.name(b), KingWen.glyph(b)]
	var m_tri: int = int(_store.machine.get("trigram", 0)) if _store != null else 0
	var h_tri: int = int(_store.human.get("trigram", 0)) if _store != null else 0
	lbl_hex_subtitle.text = "machine %s %s | human %s %s" % [
		KingWen.trigram_glyph(m_tri), KingWen.trigram_name(m_tri),
		KingWen.trigram_glyph(h_tri), KingWen.trigram_name(h_tri)]
	if _preview_bits >= 0:
		var p: int = _preview_bits & 63
		lbl_moving_line.text = "wheel %d %s %s  %s" % [
			KingWen.number(p), KingWen.pinyin(p), KingWen.name(p), KingWen.glyph(p)]
		return
	var mv: int = _moving()
	if mv == 0:
		lbl_moving_line.text = "holds"
		return
	var t: int = Cast.transform(b, mv)
	lbl_moving_line.text = "becomes %d %s %s  %s" % [
		KingWen.number(t), KingWen.pinyin(t), KingWen.name(t), KingWen.glyph(t)]


## Both rings, every tick: the eight scores of each family, and the seat the
## store says won.
func _refresh_dials() -> void:
	if body_dial == null or mandala_dial == null:
		return
	var rows: Dictionary = _score_rows()
	body_dial.set_scores(rows.get("machine", []))
	mandala_dial.set_scores(rows.get("human", []))
	if _store == null:
		return
	body_dial.set_active_machine_trigram(int(_store.machine.get("trigram", 0)))
	mandala_dial.active_human_trigram = int(_store.human.get("trigram", 0))
	mandala_dial.queue_redraw()


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
	return KingWen.trigram_name(index)


## The answer, its machine sentence and its human sentence, held apart. The
## model hands the three back glued with spaces; the seams are widened here.
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


func _family_sentence(family: int) -> String:
	if _store == null:
		return ""
	var f: Dictionary = _store.machine if family == 0 else _store.human
	return String(f.get("sentence", "")).strip_edges()


func _flash(text: String) -> void:
	lbl_thought.text = text
	_flash_until = Time.get_ticks_msec() + FLASH_MS


func _now_ms() -> int:
	if _wmn != null and _wmn.has_method("now_ms"):
		return int(_wmn.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
