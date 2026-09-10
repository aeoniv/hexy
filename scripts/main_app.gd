extends Node

const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")
const MobileHUD = preload("res://scripts/mobile_hud.gd")
const SensorMandala3D = preload("res://scripts/sensor_mandala_3d.gd")

@onready var creature: Node3D = $SubViewportContainer/SubViewport/HexyCreature3D
@onready var hud: Control = $HUD/MobileHUD
var mandala_3d: SensorMandala3D

func _ready() -> void:
	print("HEXY_A22: Launching Cybernetic Creature, 3D Sensor Mandala & Mobile HUD...")
	mandala_3d = SensorMandala3D.new()
	mandala_3d.name = "SensorMandala3D"
	mandala_3d.position = creature.position
	$SubViewportContainer/SubViewport.add_child(mandala_3d)
	
	if hud and creature:
		hud.setup_creature(creature, mandala_3d)
