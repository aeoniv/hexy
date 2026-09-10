class_name CreatureBall3D
extends Node3D

# Tensegrity Icosahedron Constants
const BALL_U: float = 0.5
const BALL_H: float = 1.0
const BALL_CORD: float = 1.0

# 6 Struts: Each has [center_dir, orientation_dir]
const STRUT_DEFS: Array = [
	[Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(0, -1, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, 0, -1), Vector3(1, 0, 0)]
]

@export var hexagram_bits: int = 0b111111 # 6-bit hexagram (0..63)
@export var moving_line: int = -1 # 0..5 or -1 if none
@export var fold_factor: float = 0.0
@export var extension: float = 0.15

var strut_nodes: Array[MeshInstance3D] = []
var tip_nodes: Array[MeshInstance3D] = []
var cord_mesh_instance: MeshInstance3D
var cord_immediate_mesh: ImmediateMesh
var cord_material: StandardMaterial3D

var cached_cords: Array = []
var is_dragging: bool = false
var drag_last_pos: Vector2 = Vector2.ZERO
var rot_velocity: Vector2 = Vector2(0.005, 0.0) # ambient rotation
var current_rot: Vector2 = Vector2(-0.25, 0.5)

func _ready() -> void:
	_init_materials()
	_compute_cord_topology()
	_build_strut_meshes()
	_build_tip_meshes()
	_build_cord_mesh()
	_update_geometry(0.0)

func _init_materials() -> void:
	cord_material = StandardMaterial3D.new()
	cord_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	cord_material.vertex_color_use_as_albedo = true
	cord_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _compute_cord_topology() -> void:
	# Compute rest tips to find the 24 cords (< BALL_CORD + epsilon)
	var rest_tips: Array[Vector3] = _compute_tips(0b111111, 0.0, 0.0)
	cached_cords.clear()
	for a in range(12):
		for b in range(a + 1, 12):
			# Skip tips belonging to the same strut
			if int(a / 2) == int(b / 2):
				continue
			var d: float = rest_tips[a].distance_to(rest_tips[b])
			if abs(d - BALL_CORD) < 0.15:
				cached_cords.append([a, b])

func _build_strut_meshes() -> void:
	for i in range(6):
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.038
		cyl.bottom_radius = 0.038
		cyl.height = 1.0
		cyl.radial_segments = 16
		mi.mesh = cyl
		
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.25
		mat.metallic = 0.85
		mat.emission_enabled = true
		mi.material_override = mat
		
		add_child(mi)
		strut_nodes.append(mi)

func _build_tip_meshes() -> void:
	for i in range(12):
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.055
		sp.height = 0.11
		sp.radial_segments = 12
		sp.rings = 6
		mi.mesh = sp
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 0.9, 1.0)
		mi.material_override = mat
		
		add_child(mi)
		tip_nodes.append(mi)

func _build_cord_mesh() -> void:
	cord_mesh_instance = MeshInstance3D.new()
	cord_immediate_mesh = ImmediateMesh.new()
	cord_mesh_instance.mesh = cord_immediate_mesh
	cord_mesh_instance.material_override = cord_material
	add_child(cord_mesh_instance)

func _compute_tips(bits: int, ext: float, fold: float) -> Array[Vector3]:
	var tips: Array[Vector3] = []
	tips.resize(12)
	for i in range(6):
		var p: Vector3 = STRUT_DEFS[i][0]
		var d: Vector3 = STRUT_DEFS[i][1]
		var center: Vector3 = p * BALL_U
		
		# Rotate direction by fold angle around p axis
		var rot_dir: Vector3 = d.rotated(p.normalized(), fold * PI * 0.5)
		var is_yang: bool = ((bits >> i) & 1) == 1
		var half_len: float = (BALL_H + (ext if is_yang else -ext)) * 0.5
		
		tips[2 * i] = center + rot_dir * half_len
		tips[2 * i + 1] = center - rot_dir * half_len
	return tips

func _update_geometry(anim_time: float) -> void:
	# Idle breathing oscillation
	var breath: float = sin(anim_time * 2.5) * 0.04
	var current_ext: float = extension + breath
	var current_fold: float = fold_factor + sin(anim_time * 1.5) * 0.02
	
	var tips: Array[Vector3] = _compute_tips(hexagram_bits, current_ext, current_fold)
	
	# Update Tip node positions
	for i in range(12):
		if i < tip_nodes.size():
			tip_nodes[i].position = tips[i]
	
	# Update Strut nodes
	for i in range(6):
		var p1: Vector3 = tips[2 * i]
		var p2: Vector3 = tips[2 * i + 1]
		var mid: Vector3 = (p1 + p2) * 0.5
		var strut_len: float = p1.distance_to(p2)
		var dir: Vector3 = (p1 - p2).normalized()
		
		var node: MeshInstance3D = strut_nodes[i]
		node.position = mid
		node.scale = Vector3(1.0, strut_len, 1.0)
		
		# Align cylinder Y-axis to strut direction
		if abs(dir.y) < 0.999:
			node.basis = Basis().looking_at(dir.cross(Vector3.UP).normalized(), dir)
		else:
			node.basis = Basis().looking_at(Vector3.RIGHT, dir)
			
		# Colors & Moving Line Pulse
		var is_yang: bool = ((hexagram_bits >> i) & 1) == 1
		var is_moving: bool = (i == moving_line)
		var pulse: float = (sin(anim_time * 8.0) * 0.5 + 0.5) if is_moving else 0.0
		
		var mat: StandardMaterial3D = node.material_override
		if is_yang:
			var base_gold := Color(0.95, 0.72, 0.2)
			mat.albedo_color = base_gold.lerp(Color.WHITE, pulse * 0.5)
			mat.emission = Color(0.8, 0.55, 0.1) * (1.2 + pulse * 1.5)
		else:
			var base_blue := Color(0.2, 0.65, 0.95)
			mat.albedo_color = base_blue.lerp(Color.CYAN, pulse * 0.5)
			mat.emission = Color(0.1, 0.45, 0.8) * (1.0 + pulse * 1.5)

	# Update Elastic Cords
	cord_immediate_mesh.clear_surfaces()
	cord_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for cord in cached_cords:
		var a: int = cord[0]
		var b: int = cord[1]
		var p1: Vector3 = tips[a]
		var p2: Vector3 = tips[b]
		var dist: float = p1.distance_to(p2)
		var strain: float = clamp((dist - BALL_CORD) / 0.3, -1.0, 1.0)
		
		# Color based on strain: cyan for balanced, magenta for tension
		var cord_col: Color = Color(0.1, 0.8, 0.9, 0.7).lerp(Color(1.0, 0.2, 0.6, 0.85), clamp(strain, 0.0, 1.0))
		cord_immediate_mesh.surface_set_color(cord_col)
		cord_immediate_mesh.surface_add_vertex(p1)
		cord_immediate_mesh.surface_set_color(cord_col)
		cord_immediate_mesh.surface_add_vertex(p2)
	cord_immediate_mesh.surface_end()

func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	
	# Inertia / Drag rotation
	if not is_dragging:
		current_rot += rot_velocity * delta * 60.0
		rot_velocity = rot_velocity.lerp(Vector2(0.004, 0.0), delta * 2.0)
		
	# Tilt subtly to phone gravity if available
	var grav: Vector3 = Input.get_gravity()
	var tilt_x: float = 0.0
	var tilt_z: float = 0.0
	if grav.length_squared() > 1.0:
		tilt_z = clamp(-grav.x * 0.04, -0.4, 0.4)
		tilt_x = clamp((grav.y - 9.8) * 0.04, -0.4, 0.4)
		
	transform.basis = Basis.from_euler(Vector3(current_rot.x + tilt_x, current_rot.y, tilt_z))
	_update_geometry(t)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = true
			drag_last_pos = event.position
		else:
			is_dragging = false
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			drag_last_pos = event.position
	elif event is InputEventScreenDrag:
		if is_dragging:
			var delta_pos: Vector2 = event.position - drag_last_pos
			drag_last_pos = event.position
			current_rot.y += delta_pos.x * 0.008
			current_rot.x += delta_pos.y * 0.008
			rot_velocity = Vector2(delta_pos.y * 0.004, delta_pos.x * 0.004)
	elif event is InputEventMouseMotion:
		if is_dragging:
			var delta_pos: Vector2 = event.position - drag_last_pos
			drag_last_pos = event.position
			current_rot.y += delta_pos.x * 0.008
			current_rot.x += delta_pos.y * 0.008
			rot_velocity = Vector2(delta_pos.y * 0.004, delta_pos.x * 0.004)

func set_hexagram(bits: int, moving: int = -1) -> void:
	hexagram_bits = bits & 0x3F
	moving_line = moving
