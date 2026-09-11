class_name CreatureBall3D
extends Node3D

## Tensegrity Cybernetics Visualizer:
## 1. Icosahedron: Exact canonical 6-strut 24-cord tensegrity from commit 3215119
## 2. Rhombic Dodecahedron: 3 coordinate struts, 8 trigram hubs, 24 cords
## 3. Rhombic Triacontahedron: 30 golden rhombus translucent facets, 32 vertices, 60 sexagenary cords

enum GeometryMode {
	ICOSAHEDRON = 0,
	RHOMBIC_DODECAHEDRON = 1,
	RHOMBIC_TRIACONTAHEDRON = 2
}

@export var geometry_mode: GeometryMode = GeometryMode.ICOSAHEDRON
@export var hexagram_bits: int = 0b111111 # 6-bit hexagram (0..63)
@export var moving_line: int = -1 # 0..5 or -1 if none
@export var fold_factor: float = 0.0
@export var extension: float = 0.15
@export var sensor_mode_enabled: bool = false
@export var is_thinking: bool = false

func set_thinking(val: bool) -> void:
	is_thinking = val
var gravity_strain: Vector3 = Vector3.ZERO

const PHI: float = 1.61803398875 # Golden Ratio
# Scaled down from 0.85 to 0.58 so all geometries fit within the screen without touching UI
const SCALE: float = 0.44

# --- 1. EXACT CANONICAL TENSEGRITY ICOSAHEDRON (Commit 3215119) ---
const STRUT_PAIRS: Array = [
	[0, 1],   # Strut 0: Line 1 (bottom)
	[2, 3],   # Strut 1: Line 2
	[4, 5],   # Strut 2: Line 3
	[6, 7],   # Strut 3: Line 4
	[8, 9],   # Strut 4: Line 5
	[10, 11]  # Strut 5: Line 6 (top)
]

const CORDS_24: Array = [
	[0, 5], [0, 7], [0, 10], [0, 11],
	[1, 5], [1, 7], [1, 8], [1, 9],
	[2, 4], [2, 6], [2, 10], [2, 11],
	[3, 4], [3, 6], [3, 8], [3, 9],
	[4, 9], [4, 11], [5, 9], [5, 11],
	[6, 8], [6, 10], [7, 8], [7, 10]
]

# --- 2. RHOMBIC DODECAHEDRON (14 vertices, 3 coordinate struts, 8 trigram hubs, 24 cords) ---
const RD_VERTICES: Array[Vector3] = [
	Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0),
	Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0),
	Vector3(0.55, 0.55, 0.55),   Vector3(-0.55, 0.55, 0.55),
	Vector3(0.55, -0.55, 0.55),  Vector3(-0.55, -0.55, 0.55),
	Vector3(0.55, 0.55, -0.55),  Vector3(-0.55, 0.55, -0.55),
	Vector3(0.55, -0.55, -0.55), Vector3(-0.55, -0.55, -0.55)
]

const RD_STRUTS: Array = [
	[0, 1], [2, 3], [4, 5]
]

const RD_CORDS: Array = [
	[0, 6], [0, 8], [0, 10], [0, 12],
	[1, 7], [1, 9], [1, 11], [1, 13],
	[2, 6], [2, 7], [2, 10], [2, 11],
	[3, 8], [3, 9], [3, 12], [3, 13],
	[4, 6], [4, 7], [4, 8], [4, 9],
	[5, 10], [5, 11], [5, 12], [5, 13]
]

# --- 3. RHOMBIC TRIACONTAHEDRON (32 vertices, 30 golden rhombus faces, 60 cords, 6 6D-axes) ---
const RT_VERTICES: Array[Vector3] = [
	Vector3(0.0, -0.52573, -0.85065),
	Vector3(-0.52573, -0.85065, 0.0),
	Vector3(-0.85065, 0.0, -0.52573),
	Vector3(0.0, -0.52573, 0.85065),
	Vector3(-0.52573, 0.85065, 0.0),
	Vector3(-0.85065, 0.0, 0.52573),
	Vector3(0.0, 0.52573, -0.85065),
	Vector3(0.52573, -0.85065, 0.0),
	Vector3(0.85065, 0.0, -0.52573),
	Vector3(0.0, 0.52573, 0.85065),
	Vector3(0.52573, 0.85065, 0.0),
	Vector3(0.85065, 0.0, 0.52573),
	Vector3(-0.53934, -0.53934, -0.53934),
	Vector3(-0.53934, -0.53934, 0.53934),
	Vector3(-0.53934, 0.53934, -0.53934),
	Vector3(-0.53934, 0.53934, 0.53934),
	Vector3(0.53934, -0.53934, -0.53934),
	Vector3(0.53934, -0.53934, 0.53934),
	Vector3(0.53934, 0.53934, -0.53934),
	Vector3(0.53934, 0.53934, 0.53934),
	Vector3(0.0, -0.33333, -0.87268),
	Vector3(-0.33333, -0.87268, 0.0),
	Vector3(-0.87268, 0.0, -0.33333),
	Vector3(0.0, -0.33333, 0.87268),
	Vector3(-0.33333, 0.87268, 0.0),
	Vector3(-0.87268, 0.0, 0.33333),
	Vector3(0.0, 0.33333, -0.87268),
	Vector3(0.33333, -0.87268, 0.0),
	Vector3(0.87268, 0.0, -0.33333),
	Vector3(0.0, 0.33333, 0.87268),
	Vector3(0.33333, 0.87268, 0.0),
	Vector3(0.87268, 0.0, 0.33333)
]
const RT_STRUTS: Array = [
	[0, 9],
	[1, 10],
	[2, 11],
	[3, 6],
	[4, 7],
	[5, 8]
]
const RT_CORDS: Array = [
	[0, 20],
	[0, 12],
	[0, 16],
	[0, 26],
	[0, 21],
	[1, 21],
	[1, 12],
	[1, 13],
	[1, 27],
	[1, 22],
	[2, 22],
	[2, 12],
	[2, 14],
	[2, 25],
	[2, 20],
	[3, 23],
	[3, 13],
	[3, 17],
	[3, 29],
	[3, 21],
	[4, 24],
	[4, 14],
	[4, 15],
	[4, 30],
	[4, 22],
	[5, 25],
	[5, 13],
	[5, 15],
	[5, 22],
	[5, 23],
	[6, 26],
	[6, 14],
	[6, 18],
	[6, 20],
	[6, 24],
	[7, 27],
	[7, 16],
	[7, 17],
	[7, 21],
	[7, 28],
	[8, 28],
	[8, 16],
	[8, 18],
	[8, 31],
	[8, 20],
	[9, 29],
	[9, 15],
	[9, 19],
	[9, 23],
	[9, 24],
	[10, 30],
	[10, 18],
	[10, 19],
	[10, 24],
	[10, 28],
	[11, 31],
	[11, 17],
	[11, 19],
	[11, 28],
	[11, 23]
]
const RT_FACES: Array = [
	[0, 12, 1, 21],
	[0, 12, 2, 20],
	[0, 20, 6, 26],
	[0, 16, 7, 21],
	[0, 16, 8, 20],
	[1, 12, 2, 22],
	[1, 13, 3, 21],
	[1, 13, 5, 22],
	[1, 21, 7, 27],
	[2, 14, 4, 22],
	[2, 22, 5, 25],
	[2, 14, 6, 20],
	[3, 13, 5, 23],
	[3, 17, 7, 21],
	[3, 23, 9, 29],
	[3, 17, 11, 23],
	[4, 15, 5, 22],
	[4, 14, 6, 24],
	[4, 15, 9, 24],
	[4, 24, 10, 30],
	[5, 15, 9, 23],
	[6, 18, 8, 20],
	[6, 18, 10, 24],
	[7, 16, 8, 28],
	[7, 17, 11, 28],
	[8, 18, 10, 28],
	[8, 28, 11, 31],
	[9, 19, 10, 24],
	[9, 19, 11, 23],
	[10, 19, 11, 28]
]

var strut_nodes: Array[MeshInstance3D] = []
var tip_nodes: Array[MeshInstance3D] = []
var cord_mesh_instance: MeshInstance3D
var cord_immediate_mesh: ImmediateMesh
var cord_material: StandardMaterial3D
var face_mesh_instance: MeshInstance3D
var face_immediate_mesh: ImmediateMesh

var is_dragging: bool = false
var drag_last_pos: Vector2 = Vector2.ZERO
var rot_velocity: Vector2 = Vector2(0.006, 0.003)
var current_rot: Vector2 = Vector2(-0.25, 0.5)

func _ready() -> void:
	_init_materials()
	_rebuild_node_pool()
	_update_geometry(0.0)

func set_geometry_mode(mode: GeometryMode) -> void:
	if geometry_mode != mode:
		geometry_mode = mode
		_rebuild_node_pool()
		_update_geometry(0.0)

func cycle_geometry_mode() -> int:
	var next_mode: int = (int(geometry_mode) + 1) % 3
	set_geometry_mode(next_mode as GeometryMode)
	return next_mode

func get_current_geometry_name() -> String:
	match geometry_mode:
		GeometryMode.ICOSAHEDRON:
			return "Icosahedron"
		GeometryMode.RHOMBIC_DODECAHEDRON:
			return "Rhombic Dodeca"
		GeometryMode.RHOMBIC_TRIACONTAHEDRON:
			return "Triacontahedron"
	return "Icosahedron"

func set_hexagram(bits: int, moving: int = -1) -> void:
	hexagram_bits = bits & 0x3F
	moving_line = moving
	_update_geometry(Time.get_ticks_msec() * 0.001)

func _init_materials() -> void:
	cord_material = StandardMaterial3D.new()
	cord_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	cord_material.vertex_color_use_as_albedo = true
	cord_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	cord_mesh_instance = MeshInstance3D.new()
	cord_immediate_mesh = ImmediateMesh.new()
	cord_mesh_instance.mesh = cord_immediate_mesh
	cord_mesh_instance.material_override = cord_material
	add_child(cord_mesh_instance)
	
	face_mesh_instance = MeshInstance3D.new()
	face_immediate_mesh = ImmediateMesh.new()
	face_mesh_instance.mesh = face_immediate_mesh
	var face_mat: StandardMaterial3D = StandardMaterial3D.new()
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_mat.vertex_color_use_as_albedo = true
	face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh_instance.material_override = face_mat
	add_child(face_mesh_instance)

func _rebuild_node_pool() -> void:
	var target_tip_count: int = 12
	var target_strut_count: int = 6
	
	if geometry_mode == GeometryMode.RHOMBIC_DODECAHEDRON:
		target_tip_count = 14
		target_strut_count = 3
	elif geometry_mode == GeometryMode.RHOMBIC_TRIACONTAHEDRON:
		target_tip_count = 32
		target_strut_count = 6
		
	# Tip Nodes
	while tip_nodes.size() < target_tip_count:
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.034
		sp.height = 0.068
		sp.radial_segments = 12
		sp.rings = 6
		mi.mesh = sp
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 0.9, 1.0)
		mi.material_override = mat
		
		add_child(mi)
		tip_nodes.append(mi)
		
	while tip_nodes.size() > target_tip_count:
		var mi: MeshInstance3D = tip_nodes.pop_back()
		mi.queue_free()
		
	# Strut Nodes
	while strut_nodes.size() < target_strut_count:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.024
		cyl.bottom_radius = 0.024
		cyl.height = 1.0
		cyl.radial_segments = 16
		mi.mesh = cyl
		
		var s_mat := StandardMaterial3D.new()
		s_mat.roughness = 0.25
		s_mat.metallic = 0.85
		s_mat.emission_enabled = true
		mi.material_override = s_mat
		
		add_child(mi)
		strut_nodes.append(mi)
		
	while strut_nodes.size() > target_strut_count:
		var mi: MeshInstance3D = strut_nodes.pop_back()
		mi.queue_free()

	# Appearance per mode
	for i in range(tip_nodes.size()):
		var sp: SphereMesh = tip_nodes[i].mesh as SphereMesh
		var mat: StandardMaterial3D = tip_nodes[i].material_override as StandardMaterial3D
		if geometry_mode == GeometryMode.RHOMBIC_DODECAHEDRON:
			if i < 6:
				sp.radius = 0.044
				sp.height = 0.088
				mat.albedo_color = Color(0.2, 0.85, 1.0)
			else:
				sp.radius = 0.028
				sp.height = 0.056
				mat.albedo_color = Color(0.95, 0.72, 0.2)
		elif geometry_mode == GeometryMode.RHOMBIC_TRIACONTAHEDRON:
			if i < 12:
				sp.radius = 0.028
				sp.height = 0.056
				mat.albedo_color = Color(0.98, 0.85, 0.3)
			else:
				sp.radius = 0.018
				sp.height = 0.036
				mat.albedo_color = Color(0.2, 0.9, 1.0)
		else:
			# EXACT 3215119 Icosahedron
			sp.radius = 0.034
			sp.height = 0.068
			mat.albedo_color = Color(0.2, 0.9, 1.0)

	for s in range(strut_nodes.size()):
		var cyl: CylinderMesh = strut_nodes[s].mesh as CylinderMesh
		if geometry_mode == GeometryMode.RHOMBIC_TRIACONTAHEDRON:
			cyl.top_radius = 0.011
			cyl.bottom_radius = 0.011
		elif geometry_mode == GeometryMode.RHOMBIC_DODECAHEDRON:
			cyl.top_radius = 0.026
			cyl.bottom_radius = 0.026
		else:
			# EXACT 3215119 Icosahedron
			cyl.top_radius = 0.024
			cyl.bottom_radius = 0.024

func _compute_base_vertices(bits: int, ext: float, fold: float) -> Array[Vector3]:
	var tips: Array[Vector3] = []
	
	if geometry_mode == GeometryMode.ICOSAHEDRON:
		# EXACT 3215119 CANONICAL FORMULA
		var raw: Array[Vector3] = [
			Vector3(-0.5,  PHI * 0.5, 0.0), Vector3( 0.5,  PHI * 0.5, 0.0), # Strut 0
			Vector3(-0.5, -PHI * 0.5, 0.0), Vector3( 0.5, -PHI * 0.5, 0.0), # Strut 1
			Vector3(0.0, -0.5,  PHI * 0.5), Vector3(0.0,  0.5,  PHI * 0.5), # Strut 2
			Vector3(0.0, -0.5, -PHI * 0.5), Vector3(0.0,  0.5, -PHI * 0.5), # Strut 3
			Vector3( PHI * 0.5, 0.0, -0.5), Vector3( PHI * 0.5, 0.0,  0.5), # Strut 4
			Vector3(-PHI * 0.5, 0.0, -0.5), Vector3(-PHI * 0.5, 0.0,  0.5)  # Strut 5
		]
		tips.resize(12)
		for s in range(6):
			var idx1: int = STRUT_PAIRS[s][0]
			var idx2: int = STRUT_PAIRS[s][1]
			var v1: Vector3 = raw[idx1]
			var v2: Vector3 = raw[idx2]
			var center: Vector3 = (v1 + v2) * 0.5
			var dir: Vector3 = (v2 - v1).normalized()
			var base_len: float = v1.distance_to(v2)
			
			var is_yang: bool = ((bits >> s) & 1) == 1
			var delta_len: float = ext if is_yang else -ext
			var final_len: float = (base_len + delta_len) * SCALE
			
			var norm_center: Vector3 = center.normalized() if center.length_squared() > 0.001 else Vector3.UP
			var rot_dir: Vector3 = dir.rotated(norm_center, fold * PI * 0.25)
			tips[idx1] = (center * SCALE) - rot_dir * (final_len * 0.5)
			tips[idx2] = (center * SCALE) + rot_dir * (final_len * 0.5)
			
	elif geometry_mode == GeometryMode.RHOMBIC_DODECAHEDRON:
		tips.resize(14)
		for s in range(3):
			var idx1: int = RD_STRUTS[s][0]
			var idx2: int = RD_STRUTS[s][1]
			var v1: Vector3 = RD_VERTICES[idx1]
			var v2: Vector3 = RD_VERTICES[idx2]
			var center: Vector3 = (v1 + v2) * 0.5
			var dir: Vector3 = (v2 - v1).normalized()
			var base_len: float = v1.distance_to(v2)
			
			var bit_a: int = (bits >> (s * 2)) & 1
			var bit_b: int = (bits >> (s * 2 + 1)) & 1
			var delta_len: float = (ext if (bit_a + bit_b > 1) else (-ext if (bit_a + bit_b == 0) else 0.0))
			var final_len: float = (base_len + delta_len) * (SCALE * 0.95)
			
			tips[idx1] = (center * SCALE) - dir * (final_len * 0.5)
			tips[idx2] = (center * SCALE) + dir * (final_len * 0.5)
			
		for c in range(8):
			tips[6 + c] = RD_VERTICES[6 + c] * (SCALE * 0.95)
			
	elif geometry_mode == GeometryMode.RHOMBIC_TRIACONTAHEDRON:
		tips.resize(32)
		var r_scale: float = SCALE * 0.95
		for i in range(32):
			var base_v: Vector3 = RT_VERTICES[i]
			var pulse: float = 0.0
			for s in range(6):
				var is_yang: bool = ((bits >> s) & 1) == 1
				var p1: Vector3 = RT_VERTICES[RT_STRUTS[s][0]]
				var alignment: float = abs(base_v.dot(p1))
				pulse += alignment * (ext * 0.15 if is_yang else -ext * 0.15)
			tips[i] = base_v * (r_scale + pulse)
			
	return tips

func _update_geometry(anim_time: float) -> void:
	var breath: float = sin(anim_time * 2.5) * 0.035
	var current_ext: float = extension + breath
	var current_fold: float = fold_factor + sin(anim_time * 1.5) * 0.02
	
	var tips: Array[Vector3] = _compute_base_vertices(hexagram_bits, current_ext, current_fold)
	
	# Organic gravity strain deformation (symmetric elastic squash and bulge)
	if gravity_strain.length_squared() > 0.00001:
		var g_dir := gravity_strain.normalized()
		var g_mag := gravity_strain.length()
		for i in range(tips.size()):
			var proj: float = tips[i].dot(g_dir)
			var squash: Vector3 = -g_dir * (proj * g_mag * 0.25)
			var bulge: Vector3 = (tips[i] - g_dir * proj) * (g_mag * 0.12)
			tips[i] += squash + bulge

	# Exact Mass Center Centering: guarantee centroid is identically (0, 0, 0)
	var centroid: Vector3 = Vector3.ZERO
	for pt in tips:
		centroid += pt
	if tips.size() > 0:
		centroid /= float(tips.size())
		for i in range(tips.size()):
			tips[i] -= centroid
			
	# Update Tip nodes
	for i in range(tip_nodes.size()):
		if i < tips.size():
			tip_nodes[i].position = tips[i]
	
	# Update Strut nodes
	var active_struts: Array = STRUT_PAIRS
	if geometry_mode == GeometryMode.RHOMBIC_DODECAHEDRON:
		active_struts = RD_STRUTS
	elif geometry_mode == GeometryMode.RHOMBIC_TRIACONTAHEDRON:
		active_struts = RT_STRUTS
		
	for s in range(strut_nodes.size()):
		if s >= active_struts.size():
			break
		var idx1: int = active_struts[s][0]
		var idx2: int = active_struts[s][1]
		var p1: Vector3 = tips[idx1]
		var p2: Vector3 = tips[idx2]
		var mid: Vector3 = (p1 + p2) * 0.5
		var strut_len: float = p1.distance_to(p2)
		var dir: Vector3 = (p2 - p1).normalized()
		
		var node: MeshInstance3D = strut_nodes[s]
		node.position = mid
		
		# Align cylinder Y-axis to strut direction, then scale local height to exact strut length
		if abs(dir.y) < 0.999:
			node.basis = Basis().looking_at(dir.cross(Vector3.UP).normalized(), dir)
		else:
			node.basis = Basis().looking_at(Vector3.RIGHT, dir)
		node.scale = Vector3(1.0, strut_len, 1.0)
			
		# Colors & Moving Line Pulse
		var line_idx: int = s if geometry_mode != GeometryMode.RHOMBIC_DODECAHEDRON else s * 2
		var is_yang: bool = ((hexagram_bits >> line_idx) & 1) == 1
		var is_moving: bool = (line_idx == moving_line or (geometry_mode == GeometryMode.RHOMBIC_DODECAHEDRON and line_idx + 1 == moving_line))
		var pulse: float = (sin(anim_time * 8.0) * 0.5 + 0.5) if is_moving else 0.0
		if is_thinking:
			pulse = max(pulse, sin(anim_time * 5.0) * 0.5 + 0.5)
		
		var mat: StandardMaterial3D = node.material_override
		if is_moving:
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

	# Update Cords (Strings)
	var active_cords: Array = CORDS_24
	var rest_cord_len: float = 1.0 * SCALE
	if geometry_mode == GeometryMode.RHOMBIC_DODECAHEDRON:
		active_cords = RD_CORDS
		rest_cord_len = 0.866 * (SCALE * 0.95)
	elif geometry_mode == GeometryMode.RHOMBIC_TRIACONTAHEDRON:
		active_cords = RT_CORDS
		rest_cord_len = 0.60 * (SCALE * 0.95)

	cord_immediate_mesh.clear_surfaces()
	cord_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for cord in active_cords:
		var a: int = cord[0]
		var b: int = cord[1]
		if a >= tips.size() or b >= tips.size():
			continue
		var p1: Vector3 = tips[a]
		var p2: Vector3 = tips[b]
		var dist: float = p1.distance_to(p2)
		var strain: float = clamp((dist - rest_cord_len) / (0.25 * SCALE), -1.0, 1.0)
		
		var base_col: Color = Color(0.2, 0.85, 1.0, 0.7) if geometry_mode != GeometryMode.RHOMBIC_TRIACONTAHEDRON else Color(0.3, 0.75, 1.0, 0.4)
		var cord_col: Color = base_col.lerp(Color(1.0, 0.2, 0.7, 0.95), clamp(strain, 0.0, 1.0))
		
		if moving_line >= 0 and geometry_mode == GeometryMode.ICOSAHEDRON:
			var m_p1: int = STRUT_PAIRS[moving_line][0]
			var m_p2: int = STRUT_PAIRS[moving_line][1]
			if a == m_p1 or a == m_p2 or b == m_p1 or b == m_p2:
				cord_col = cord_col.lerp(Color(1.0, 0.9, 0.3, 0.95), 0.5)
		
		cord_immediate_mesh.surface_set_color(cord_col)
		cord_immediate_mesh.surface_add_vertex(p1)
		cord_immediate_mesh.surface_set_color(cord_col)
		cord_immediate_mesh.surface_add_vertex(p2)
		
	cord_immediate_mesh.surface_end()

	# Render Translucent Rhombic Facets (for Rhombic Triacontahedron)
	if face_immediate_mesh:
		face_immediate_mesh.clear_surfaces()
		if geometry_mode == GeometryMode.RHOMBIC_TRIACONTAHEDRON and tips.size() >= 32:
			face_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			
			var active_face_idx: int = (hexagram_bits % 30)
			
			for f_idx in range(RT_FACES.size()):
				var f: Array = RT_FACES[f_idx]
				var p0: Vector3 = tips[f[0]]
				var p1: Vector3 = tips[f[1]]
				var p2: Vector3 = tips[f[2]]
				var p3: Vector3 = tips[f[3]]
				
				var is_active: bool = (f_idx == active_face_idx)
				var face_col: Color
				if is_active:
					var f_pulse: float = sin(anim_time * 6.0) * 0.5 + 0.5
					face_col = Color(1.0, 0.85, 0.2, 0.55).lerp(Color(1.0, 0.3, 0.7, 0.7), f_pulse)
				else:
					face_col = Color(0.15, 0.35, 0.65, 0.18)
					
				# Triangle 1: p0, p1, p2
				face_immediate_mesh.surface_set_color(face_col)
				face_immediate_mesh.surface_add_vertex(p0)
				face_immediate_mesh.surface_set_color(face_col)
				face_immediate_mesh.surface_add_vertex(p1)
				face_immediate_mesh.surface_set_color(face_col)
				face_immediate_mesh.surface_add_vertex(p2)
				
				# Triangle 2: p0, p2, p3
				face_immediate_mesh.surface_set_color(face_col)
				face_immediate_mesh.surface_add_vertex(p0)
				face_immediate_mesh.surface_set_color(face_col)
				face_immediate_mesh.surface_add_vertex(p2)
				face_immediate_mesh.surface_set_color(face_col)
				face_immediate_mesh.surface_add_vertex(p3)
				
			face_immediate_mesh.surface_end()

func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	
	if sensor_mode_enabled:
		var gyro: Vector3 = Input.get_gyroscope()
		if gyro.length_squared() > 0.002:
			current_rot.x += gyro.y * delta * 1.8
			current_rot.y += gyro.x * delta * 1.8
		else:
			current_rot += rot_velocity
			rot_velocity = rot_velocity.lerp(Vector2(0.004, 0.002), delta * 1.5)
			
		var raw_grav: Vector3 = Input.get_gravity()
		if raw_grav.length_squared() > 1.0:
			var g_local: Vector3 = transform.basis.inverse() * raw_grav.normalized()
			var target_strain: Vector3 = g_local * 0.20
			gravity_strain = gravity_strain.lerp(target_strain, delta * 6.0)
		else:
			gravity_strain = gravity_strain.lerp(Vector3.ZERO, delta * 3.0)
	else:
		if not is_dragging:
			current_rot += rot_velocity
			rot_velocity = rot_velocity.lerp(Vector2(0.006, 0.003), delta * 2.0)
		gravity_strain = gravity_strain.lerp(Vector3.ZERO, delta * 3.0)
	
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
