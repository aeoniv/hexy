extends Node

@onready var creature: Node3D = $SubViewportContainer/SubViewport/HexyCreature3D
@onready var hud: Control = $HUD/MobileHUD

func _ready() -> void:
	print("MNN_QWEN_ICHING: Starting experiment...")
	if hud and creature:
		hud.setup_creature(creature)
