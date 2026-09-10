extends Node

const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")
const MobileHUD = preload("res://scripts/mobile_hud.gd")

@onready var creature: Node3D = $SubViewportContainer/SubViewport/HexyCreature3D
@onready var hud: Control = $HUD/MobileHUD

func _ready() -> void:
	print("HEXY_A22: Launching Cybernetic Creature & Mobile HUD...")
	if hud and creature:
		hud.setup_creature(creature)
