class_name CreatureBall3D
extends Node3D

## 6-Strut Tensegrity Icosahedron with 24 Canonical Elastic Strings (Cords)
## Coordinates based on three orthogonal golden ratio (phi) rectangles.

const PHI: float = 1.61803398875 # Golden Ratio
const SCALE: float = 0.85 # Overall visual scale

# 6 Strut Indices: each defines two vertex endpoints of a rigid compression strut
const STRUT_PAIRS: Array = [
	[0, 1],   # Strut 0: Line 1 (bottom)
	[2, 3],   # Strut 1: Line 2
	[4, 5],   # Strut 2: Line 3
	[6, 7],   # Strut 3: Line 4
	[8, 9],   # Strut 4: Line 5
	[10, 11]  # Strut 5: Line 6 (top)
]

# Canonical 24 Elastic Cords of the 6-Strut Tensegrity Icosahedron
# Connects the 12 vertices forming the triangular facets of the icosahedron.
const CORDS_24: Array = [
	[0, 5], [0, 7], [0, 10], [0, 11],
	[1, 5], [1, 7], [1, 8], [1, 9],
	[2, 4], [2, 6], [2, 10], [2, 11],
	[3, 4], [3, 6], [3, 8], [3, 9],
	[4, 9], [4, 11], [5, 9], [5, 11],
	[6, 8], [6, 10], [7, 8], [7, 10]
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

var is_dragging: bool = false
var drag_last_pos: Vector2 = Vector2.ZERO
var rot_velocity: Vector2 = Vector2(0.006, 0.003) # ambient 3D tumbling rotation
var current_rot: Vector2 = Vector2(-0.25, 0.5)

func _ready() -> void:
	_init_materials()
	_build_strut_meshes()
	_build_tip_meshes()
	_build_cord_mesh()
	_update_geometry(0.0)

func _init_materials() -> void:
	cord_material = StandardMaterial3D.new()
	cord_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	cord_material.vertex_color_use_as_albedo = true
	cord_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _build_strut_meshes() -> void:
	for i in range(6):
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.032
		cyl.bottom_radius = 0.032
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
		sp.radius = 0.048
		sp.height = 0.096
		sp.radial_segments = 12
		sp.rings = 6
		mi.mesh = sp
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 0.9, 1.0)
		mi.material_override = mat
		
		add_child(mi)
		tip_nodes.append(mi)

func _build_cord_mesh() -> void:
	cord_mesh_instance = MeshInstance3D.new()
	cord_immediate_mesh = ImmediateMesh.new()
	cord_mesh_instance.mesh = cord_immediate_mesh
	cord_mesh_instance.material_override = cord_material
	add_child(cord_mesh_instance)

func _compute_base_vertices(bits: int, ext: float, fold: float) -> Array[Vector3]:
	# Canonical 3 golden ratio rectangles:
	# Rectangle 1: XY plane: (±0.5, ±phi/2, 0)
	# Rectangle 2: YZ plane: (0, ±0.5, ±phi/2)
	# Rectangle 3: ZX plane: (±phi/2, 0, ±0.5)
	var raw: Array[Vector3] = [
		Vector3(-0.5,  PHI * 0.5, 0.0), Vector3( 0.5,  PHI * 0.5, 0.0), # Strut 0
		Vector3(-0.5, -PHI * 0.5, 0.0), Vector3( 0.5, -PHI * 0.5, 0.0), # Strut 1
		Vector3(0.0, -0.5,  PHI * 0.5), Vector3(0.0,  0.5,  PHI * 0.5), # Strut 2
		Vector3(0.0, -0.5, -PHI * 0.5), Vector3(0.0,  0.5, -PHI * 0.5), # Strut 3
		Vector3( PHI * 0.5, 0.0, -0.5), Vector3( PHI * 0.5, 0.0,  0.5), # Strut 4
		Vector3(-PHI * 0.5, 0.0, -0.5), Vector3(-PHI * 0.5, 0.0,  0.5)  # Strut 5
	]
	
	var tips: Array[Vector3] = []
	tips.resize(12)
	
	for s in range(6):
		var idx1: int = STRUT_PAIRS[s][0]
		var idx2: int = STRUT_PAIRS[s][1]
		var v1: Vector3 = raw[idx1]
		var v2: Vector3 = raw[idx2]
		var center: Vector3 = (v1 + v2) * 0.5
		var dir: Vector3 = (v2 - v1).normalized()
		var base_len: float = v1.distance_to(v2)
		
		# Modulate strut length based on Yang (extended) vs Yin (contracted)
		var is_yang: bool = ((bits >> s) & 1) == 1
		var delta_len: float = ext if is_yang else -ext
		var final_len: float = (base_len + delta_len) * SCALE
		
		# Optional torsional twist (folding kinematics)
		var norm_center: Vector3 = center.normalized() if center.length_squared() > 0.001 else Vector3.UP
		var rot_dir: Vector3 = dir.rotated(norm_center, fold * PI * 0.25)
		
		tips[idx1] = (center * SCALE) - rot_dir * (final_len * 0.5)
		tips[idx2] = (center * SCALE) + rot_dir * (final_len * 0.5)
		
	return tips

func _update_geometry(anim_time: float) -> void:
	# Idle breathing oscillation
	var breath: float = sin(anim_time * 2.5) * 0.035
	var current_ext: float = extension + breath
	var current_fold: float = fold_factor + sin(anim_time * 1.5) * 0.02
	
	var tips: Array[Vector3] = _compute_base_vertices(hexagram_bits, current_ext, current_fold)
	
	# Update Tip nodes
	for i in range(12):
		if i < tip_nodes.size():
			tip_nodes[i].position = tips[i]
	
	# Update Strut nodes
	for s in range(6):
		var p1: Vector3 = tips[STRUT_PAIRS[s][0]]
		var p2: Vector3 = tips[STRUT_PAIRS[s][1]]
		var mid: Vector3 = (p1 + p2) * 0.5
		var strut_len: float = p1.distance_to(p2)
		var dir: Vector3 = (p2 - p1).normalized()
		
		var node: MeshInstance3D = strut_nodes[s]
		node.position = mid
		node.scale = Vector3(1.0, strut_len, 1.0)
		
		# Align cylinder Y-axis to strut direction
		if abs(dir.y) < 0.999:
			node.basis = Basis().looking_at(dir.cross(Vector3.UP).normalized(), dir)
		else:
			node.basis = Basis().looking_at(Vector3.RIGHT, dir)
			
		# Colors & Moving Line Pulse
		var is_yang: bool = ((hexagram_bits >> s) & 1) == 1
		var is_moving: bool = (s == moving_line)
		var pulse: float = (sin(anim_time * 8.0) * 0.5 + 0.5) if is_moving else 0.0
		
		var mat: StandardMaterial3D = node.material_override
		if is_moving:
			# Radiant pulsing yellow for mutating line
			mat.albedo_color = Color(1.0, 0.9, 0.2).lerp(Color.WHITE, pulse * 0.6)
			mat.emission = Color(1.0, 0.8, 0.1) * (1.8 + pulse * 2.5)
		elif is_yang:
			var base_gold := Color(0.95, 0.72, 0.2)
			mat.albedo_color = base_gold
			mat.emission = Color(0.8, 0.55, 0.1) * 1.2
		else:
			var base_blue := Color(0.2, 0.65, 0.95)
			mat.albedo_color = base_blue
			mat.emission = Color(0.1, 0.45, 0.8) * 1.0

	# Update All 24 Elastic Cords (Strings)
	cord_immediate_mesh.clear_surfaces()
	cord_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var rest_cord_len: float = 1.0 * SCALE
	for cord in CORDS_24:
		var a: int = cord[0]
		var b: int = cord[1]
		var p1: Vector3 = tips[a]
		var p2: Vector3 = tips[b]
		var dist: float = p1.distance_to(p2)
		var strain: float = clamp((dist - rest_cord_len) / (0.25 * SCALE), -1.0, 1.0)
		
		# Strain color: cyan for balanced tension (strain <= 0), glowing magenta under stretch (strain > 0)
		var cord_col: Color = Color(0.2, 0.85, 1.0, 0.7).lerp(Color(1.0, 0.2, 0.7, 0.95), clamp(strain, 0.0, 1.0))
		
		# If connected to the active mutating strut, add energy highlight
		if moving_line >= 0:
			var m_p1: int = STRUT_PAIRS[moving_line][0]
			var m_p2: int = STRUT_PAIRS[moving_line][1]
			if a == m_p1 or a == m_p2 or b == m_p1 or b == m_p2:
				cord_col = cord_col.lerp(Color(1.0, 0.9, 0.3, 0.95), 0.5)
		
		cord_immediate_mesh.surface_set_color(cord_col)
		cord_immediate_mesh.surface_add_vertex(p1)
		cord_immediate_mesh.surface_set_color(cord_col)
		cord_immediate_mesh.surface_add_vertex(p2)
		
	cord_immediate_mesh.surface_end()

func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	
	# Inertial rotation tumble
	if not is_dragging:
		current_rot += rot_velocity
		rot_velocity = rot_velocity.lerp(Vector2(0.006, 0.003), delta * 2.0)
	
	# Apply rotation transform
	transform.basis = Basis()
	rotate_y(current_rot.x)
	rotate_x(current_rot.y)
	
	_update_geometry(t)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = true
			drag_last_pos = event.position
		else:
			is_dragging = false
	elif event is InputEventScreenDrag and is_dragging:
		var delta_pos: Vector2 = event.position - drag_last_pos
		drag_last_pos = event.position
		rot_velocity = delta_pos * 0.008
		current_rot.x += rot_velocity.x
		current_rot.y += rot_velocity.y

func set_hexagram(bits: int, moving: int = -1) -> void:
	hexagram_bits = bits & 0x3F
	moving_line = moving
