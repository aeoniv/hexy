class_name HudBridge
extends Node

## THE OWNER'S INTERFACE, PLUGGED INTO THE NEW CORE.
##
## The bridge owns two things and no opinions: the STAGE (a square subviewport
## with the creature in it, behind everything) and the HUD (scenes/hud.tscn,
## the owner's own layout, on a CanvasLayer above it). Every act a finger can
## perform belongs to one of those two; the bridge only decides which of them
## a touch belongs to, and hands the four core objects to the HUD once.
##
## WHY A SEPARATE STAGE. The HUD is a flat Control tree and the creature is a
## Node3D. Putting the solid in a fixed 640-square viewport and SCALING that
## square into the centre of the screen means one number scales both axes: a
## phone that is not square does not get a squashed creature, and a tap landing
## on the field maps back to the point the finger actually pointed at.
##
## TAP ONLY, AND ONE ANSWER PER POINT. The HUD sits on CanvasLayer 1, so it is
## asked first: its two rings, its buttons and its composer take what is
## theirs. Only a touch that no HUD target wanted reaches the field below, and
## that touch goes to the creature -- a machine node if it hit one, otherwise
## the solid turns to its next geometry. No point on the glass has two owners.

const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")

## The side of the creature's stage, in viewport pixels. Square, and fixed.
const STAGE_PX: int = 640

var hud: MobileHudStore = null
var layer: CanvasLayer = null
var stage: SubViewportContainer = null
var view: SubViewport = null
var field: Control = null

var _creature: Node = null


func _ready() -> void:
	field = Control.new()
	field.name = "Field"
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	field.mouse_filter = Control.MOUSE_FILTER_STOP
	field.gui_input.connect(_on_field_input)
	field.resized.connect(_layout_stage)
	add_child(field)

	stage = SubViewportContainer.new()
	stage.name = "Stage"
	stage.stretch = true
	stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stage.size = Vector2(float(STAGE_PX), float(STAGE_PX))
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(stage)

	view = SubViewport.new()
	view.name = "Stagelet"
	view.size = Vector2i(STAGE_PX, STAGE_PX)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(view)

	layer = CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 1
	add_child(layer)

	hud = HUD_SCENE.instantiate()
	hud.name = "MobileHUD"
	layer.add_child(hud)
	hud.stage_visibility_changed.connect(_on_stage_visibility_changed)
	_layout_stage()
	_layout_stage.call_deferred()


# -- wiring ------------------------------------------------------------------

func bind(store: Node, qwen: Node, mnn: Node, wmn: Node) -> void:
	hud.bind(store, qwen, mnn, wmn)


func set_senses(senses: Node) -> void:
	hud.set_senses(senses)


## The creature is re-parented into the stage, exactly as the old app parented
## it into its own SubViewport, and its two answers are listened to.
func set_creature(creature: Node) -> void:
	_creature = creature
	if creature == null:
		return
	if creature.get_parent() != null:
		creature.get_parent().remove_child(creature)
	view.add_child(creature)
	if not creature.throw_requested.is_connected(_on_throw_requested):
		creature.throw_requested.connect(_on_throw_requested)
	if not creature.geometry_changed.is_connected(_on_geometry_changed):
		creature.geometry_changed.connect(_on_geometry_changed)
	hud.set_creature(creature)


func set_who(who_name: String) -> void:
	hud.set_who(who_name)


func who() -> String:
	return hud.who()


# -- what the glass is asked for ---------------------------------------------

func top_text() -> String:
	return hud.top_text()


func becomes_text() -> String:
	return hud.becomes_text()


func answer_text() -> String:
	return hud.answer_text()


func send_text(text: String) -> bool:
	return hud.send_text(text)


func tap_cast() -> Dictionary:
	return hud.tap_cast()


func open_sheet() -> void:
	hud.open_sheet()


func close_sheet() -> void:
	hud.close_sheet()


func sheet_open() -> bool:
	return hud.sheet_open()


func sheet_row_count() -> int:
	return hud.sheet_row_count()


## The hub at the middle of the human ring: the one target that casts.
func hub_button() -> Node:
	return hud.mandala_dial


func plus_button() -> Button:
	return hud.btn_plus


func cast_button() -> Button:
	return hud.btn_cast


func body_dial() -> Node:
	return hud.body_dial


func mandala_dial() -> Node:
	return hud.mandala_dial


func sheet() -> Node:
	return hud.get_node("Sheet")


# -- the field ---------------------------------------------------------------

func _on_field_input(event: InputEvent) -> void:
	if not MobileHudStore._is_release(event) or _creature == null:
		return
	field.accept_event()
	_creature.tap(_to_stage(event.position))


func _on_throw_requested(_trigram: int) -> void:
	hud.tap_cast()


func _on_geometry_changed(_mode: int) -> void:
	hud.set_creature(_creature)


func _on_stage_visibility_changed(on: bool) -> void:
	stage.visible = on


## The square stage, centred in the field and scaled by one number.
func _layout_stage() -> void:
	if field == null or stage == null:
		return
	var box: Vector2 = field.size
	if box.x < 8.0 or box.y < 8.0:
		return
	var side: float = minf(box.x, box.y)
	var k: float = side / float(STAGE_PX)
	stage.size = Vector2(float(STAGE_PX), float(STAGE_PX))
	stage.scale = Vector2(k, k)
	stage.position = (box - Vector2(side, side)) * 0.5


## A point on the glass, in the pixels of the stage viewport. A letterbox: one
## scale for both axes, the leftover split evenly.
func _to_stage(p: Vector2) -> Vector2:
	var box: Vector2 = field.size
	var side: float = minf(box.x, box.y)
	if side <= 0.0:
		return p
	var v := Vector2(view.size)
	var off: Vector2 = (box - Vector2(side, side)) * 0.5
	var q: Vector2 = (p - off) / side
	return Vector2(clampf(q.x, 0.0, 1.0) * v.x, clampf(q.y, 0.0, 1.0) * v.y)
