extends Node

const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")
const MobileHUD = preload("res://scripts/mobile_hud.gd")
const SensorMandala3D = preload("res://scripts/sensor_mandala_3d.gd")
const MeshFabric = preload("res://scripts/net/mesh_fabric.gd")
const IdentityScript = preload("res://scripts/social/identity.gd")

@onready var creature: Node3D = $SubViewportContainer/SubViewport/HexyCreature3D
@onready var hud: Control = $HUD/MobileHUD
var mandala_3d: SensorMandala3D
var mesh: MeshFabric

func _ready() -> void:
	print("HEXY_A22: Launching Cybernetic Creature, 3D Sensor Mandala & Mobile HUD...")
	mandala_3d = SensorMandala3D.new()
	mandala_3d.name = "SensorMandala3D"
	mandala_3d.position = creature.position
	$SubViewportContainer/SubViewport.add_child(mandala_3d)
	
	# Start Wireless Mesh Network Engine
	mesh = MeshFabric.new()
	mesh.name = "MeshFabric"
	mesh.fabric_id = IdentityScript.stable_fabric_id()
	# Primary Transport: IxMesh Nearby on Android, LanMesh on Desktop
	mesh.add_transport()
	# Secondary Transport on Android: LAN Mesh for Wi-Fi local network bridging
	if OS.get_name() == "Android":
		var t_lan := mesh.add_transport()
		t_lan.force_lan = true
	add_child(mesh)
	var err := mesh.start("hexy")
	print("HEXY_MESH: Started WMN engine -> backend=", mesh.backend_name(), " fabric_id=", mesh.fabric_id, " err=", err)
	
	if hud and creature:
		hud.setup_creature(creature, mandala_3d)
		if hud.has_method("setup_mesh"):
			hud.setup_mesh(mesh)
