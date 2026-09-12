class_name SensorMandala3D
extends Node3D

## Cybernetic 3D Dual-Orbit Sensor Mandala Visualizer (8 Machine x 8 Human)
##
## Dual Concentric Sacred Mandala:
## 1. INNER CELESTIAL ORBIT (Radius ~0.37): 8 Machine Environmental Substrates (Cyan/Teal)
## 2. OUTER CELESTIAL ORBIT (Radius ~0.55): 8 Human Activity & Habit Disciplines (Amber/Gold)
## 3. HARMONIC RESONANCE ARC: Connects active Machine Substrate to active Human Action
## 4. 8 BA-GUA TRIGRAM STATIONS: Dynamic Solid/Broken line glyphs with active highlighting

@export var enabled: bool = true
@export var radius: float = 0.54
@export var is_thinking: bool = false
@export var thought_pulse: float = 0.0

var mandala_mesh: ImmediateMesh
var mesh_instance: MeshInstance3D
var material: StandardMaterial3D

# Multi-Modal Afferent Telemetry Cache
var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
var gyro: Vector3 = Vector3.ZERO
var heading_deg: float = 0.0
var jerk: float = 0.0
var lux: float = 250.0
var proximity: float = 5.0
var battery: float = 100.0
var solar_hour: float = 12.0
var kinetic_excitation: float = 0.0
var line_strains: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var shake_progress: float = 0.0
var dwell_progress: float = 0.0

# 8x8 Trigram States
var lower_tri: int = 7 # Machine (Default: Heaven)
var upper_tri: int = 7 # Human   (Default: Heaven)
var body_hex_index: int = 0
var body_hex_id: int = 1

func set_body_hexagram(wen_id: int, hex_index: int = -1) -> void:
	body_hex_id = wen_id
	if hex_index >= 0:
		body_hex_index = hex_index
	else:
		body_hex_index = HuohoutuData.find_body_index_by_id(wen_id)

var gyro_orbit_angle: float = 0.0
var celestial_rot: float = 0.0

# Trigram definitions: 3 bits (0=broken Yin, 1=solid Yang)
const TRIGRAM_BITS: Array[int] = [0b000, 0b001, 0b010, 0b011, 0b100, 0b101, 0b110, 0b111]

# Spatial Ba-Gua Station Angles around the Mandala (Physical Cardinal layout)
const BAGUA_STATIONS: Array[Dictionary] = [
	{"trigram": 7, "angle": -PI * 0.5, "name": "Heaven", "human": "Posture", "machine": "Solar Noon"},
	{"trigram": 3, "angle": -PI * 0.25, "name": "Lake", "human": "Grip", "machine": "Atmosphere"},
	{"trigram": 5, "angle": 0.0, "name": "Fire", "human": "Active Gaze", "machine": "Photosphere"},
	{"trigram": 1, "angle": PI * 0.25, "name": "Thunder", "human": "Steps", "machine": "Power Surge"},
	{"trigram": 0, "angle": PI * 0.5, "name": "Earth", "human": "Sleep Rest", "machine": "Sanctuary"},
	{"trigram": 4, "angle": PI * 0.75, "name": "Mountain", "human": "Deep Focus", "machine": "Desk Rest"},
	{"trigram": 2, "angle": PI, "name": "Water", "human": "Hydration", "machine": "Battery Chi"},
	{"trigram": 6, "angle": -PI * 0.75, "name": "Wind", "human": "Breath Equanimity", "machine": "Magnetic Flux"}
]


func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	mandala_mesh = ImmediateMesh.new()
	mesh_instance.mesh = mandala_mesh
	
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	
	add_child(mesh_instance)


func update_telemetry(data: Dictionary) -> void:
	if data.has("gravity"): gravity = data["gravity"]
	if data.has("gyro"): gyro = data["gyro"]
	if data.has("heading"): heading_deg = data["heading"]
	if data.has("jerk"): jerk = data["jerk"]
	if data.has("lux"): lux = data["lux"]
	if data.has("proximity"): proximity = data["proximity"]
	if data.has("battery"): battery = data["battery"]
	if data.has("solar_hour"): solar_hour = data["solar_hour"]
	if data.has("kinetic_excitation"): kinetic_excitation = data["kinetic_excitation"]
	if data.has("line_strains"): line_strains = data["line_strains"]
	if data.has("shake_progress"): shake_progress = data["shake_progress"]
	if data.has("dwell_progress"): dwell_progress = data["dwell_progress"]
	if data.has("lower_trigram"): lower_tri = data["lower_trigram"]
	if data.has("upper_trigram"): upper_tri = data["upper_trigram"]


func set_thinking(state: bool) -> void:
	is_thinking = state


func _process(delta: float) -> void:
	if not enabled or not mandala_mesh:
		return
		
	var now: float = Time.get_ticks_msec() * 0.001
	var gyro_speed: float = gyro.length()
	gyro_orbit_angle += (1.2 + gyro_speed * 2.5) * delta
	celestial_rot += 0.03 * delta
	
	if is_thinking:
		thought_pulse = sin(now * 8.0) * 0.5 + 0.5
	else:
		thought_pulse = move_toward(thought_pulse, 0.0, delta * 3.0)
		
	_render_mandala(now)


func _add_line(p1: Vector3, p2: Vector3, col: Color) -> void:
	mandala_mesh.surface_set_color(col)
	mandala_mesh.surface_add_vertex(p1)
	mandala_mesh.surface_set_color(col)
	mandala_mesh.surface_add_vertex(p2)


func _add_circle(center: Vector3, r: float, segs: int, col: Color) -> void:
	for i in range(segs):
		var a1: float = (float(i) / float(segs)) * TAU
		var a2: float = (float(i + 1) / float(segs)) * TAU
		var p1 := center + Vector3(cos(a1) * r, sin(a1) * r, 0.0)
		var p2 := center + Vector3(cos(a2) * r, sin(a2) * r, 0.0)
		_add_line(p1, p2, col)


func _add_arc(center: Vector3, r: float, start_a: float, end_a: float, segs: int, col: Color) -> void:
	var span: float = end_a - start_a
	for i in range(segs):
		var a1: float = start_a + (float(i) / float(segs)) * span
		var a2: float = start_a + (float(i + 1) / float(segs)) * span
		var p1 := center + Vector3(cos(a1) * r, sin(a1) * r, 0.0)
		var p2 := center + Vector3(cos(a2) * r, sin(a2) * r, 0.0)
		_add_line(p1, p2, col)


func _render_mandala(t: float) -> void:
	mandala_mesh.clear_surfaces()
	mandala_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var r_outer: float = radius
	var r_machine: float = radius * 0.70  # Inner Orbit (~0.38)
	var r_human: float = radius * 1.02    # Outer Orbit (~0.55)
	
	# -------------------------------------------------------------
	# 1. 3D INTERNAL AURA (Big Dial rendered in crisp 2D on HUD)
	# -------------------------------------------------------------
	# Subtle inner energy orbit framing tensegrity core
	var machine_ring_col := Color(0.15, 0.85, 0.95, 0.20)
	_add_circle(Vector3.ZERO, r_machine, 36, machine_ring_col)

	# -------------------------------------------------------------
	# 2. 8 INNER MACHINE SUBSTRATE NODES & 8 OUTER HUMAN NODES
	# -------------------------------------------------------------
	var active_machine_pt := Vector3.ZERO
	var active_human_pt := Vector3.ZERO
	
	for station in BAGUA_STATIONS:
		var tri_id: int = station["trigram"]
		var ang: float = station["angle"]
		var is_active_machine: bool = (tri_id == lower_tri)
		var is_active_human: bool = (tri_id == upper_tri)
		
		# Position on Inner (Machine) Orbit
		var p_m := Vector3(cos(ang) * r_machine, sin(ang) * r_machine, 0.0)
		# Position on Outer (Human) Orbit
		var p_h := Vector3(cos(ang) * r_human, sin(ang) * r_human, 0.0)
		
		if is_active_machine:
			active_machine_pt = p_m
		if is_active_human:
			active_human_pt = p_h
			
		# Connect Machine to Human station along radial spokes
		var spoke_col := Color(0.2, 0.5, 0.7, 0.18)
		if is_active_machine or is_active_human:
			spoke_col = Color(0.3, 0.9, 1.0, 0.6)
		_add_line(p_m, p_h, spoke_col)

		# Inner Machine Node Drawing (Diamond / Cyan)
		var m_col := Color(0.15, 0.85, 1.0, 0.95) if is_active_machine else Color(0.15, 0.6, 0.8, 0.35)
		var m_sz: float = 0.014 if is_active_machine else 0.008
		_add_line(p_m + Vector3(0.0, m_sz, 0.0), p_m + Vector3(m_sz, 0.0, 0.0), m_col)
		_add_line(p_m + Vector3(m_sz, 0.0, 0.0), p_m - Vector3(0.0, m_sz, 0.0), m_col)
		_add_line(p_m - Vector3(0.0, m_sz, 0.0), p_m - Vector3(m_sz, 0.0, 0.0), m_col)
		_add_line(p_m - Vector3(m_sz, 0.0, 0.0), p_m + Vector3(0.0, m_sz, 0.0), m_col)
		if is_active_machine:
			_add_circle(p_m, 0.022 + sin(t * 6.0) * 0.005, 12, m_col * Color(1,1,1,0.5))

		# Outer Human Node Drawing (Hex / Gold)
		var h_col := Color(1.0, 0.8, 0.2, 0.95) if is_active_human else Color(0.8, 0.6, 0.2, 0.35)
		var h_sz: float = 0.018 if is_active_human else 0.010
		_add_circle(p_h, h_sz, 6, h_col)
		if is_active_human:
			_add_circle(p_h, 0.026 + sin(t * 7.0 + 1.0) * 0.006, 16, h_col * Color(1,1,1,0.6))
			
		# Trigram Lines on Outer Station
		var tri_bits: int = TRIGRAM_BITS[tri_id]
		var glyph_w: float = 0.022
		var line_spacing: float = 0.007
		var glyph_center := p_h + p_h.normalized() * 0.028
		var v_rad: Vector3 = p_h.normalized()
		var v_tan: Vector3 = Vector3(-v_rad.y, v_rad.x, 0.0)
		var tri_col := Color(1.0, 0.85, 0.35, 0.9) if is_active_human else Color(0.3, 0.6, 0.8, 0.3)
		
		for l_idx in range(3):
			var is_yang: bool = bool((tri_bits >> l_idx) & 1)
			var l_center: Vector3 = glyph_center + v_rad * (float(l_idx - 1) * line_spacing)
			if is_yang:
				_add_line(l_center - v_tan * glyph_w, l_center + v_tan * glyph_w, tri_col)
			else:
				var gap_w: float = glyph_w * 0.28
				_add_line(l_center - v_tan * glyph_w, l_center - v_tan * gap_w, tri_col)
				_add_line(l_center + v_tan * gap_w, l_center + v_tan * glyph_w, tri_col)

	# -------------------------------------------------------------
	# 3. HARMONIC RESONANCE ARC (Active Machine x Active Human Synergy)
	# -------------------------------------------------------------
	if active_machine_pt.length_squared() > 0.01 and active_human_pt.length_squared() > 0.01:
		var mid_pt: Vector3 = (active_machine_pt + active_human_pt) * 0.5
		# Bow outward towards viewer
		mid_pt += Vector3(0.0, 0.0, 0.04)
		var arc_col := Color(0.4, 0.95, 1.0, 0.85).lerp(Color(1.0, 0.85, 0.3, 0.85), sin(t * 5.0) * 0.5 + 0.5)
		
		# Quadratic bezier resonance spline
		var spline_segs := 16
		var p_prev := active_machine_pt
		for s in range(1, spline_segs + 1):
			var u: float = float(s) / float(spline_segs)
			var p_curr: Vector3 = (1.0 - u) * (1.0 - u) * active_machine_pt + 2.0 * (1.0 - u) * u * mid_pt + u * u * active_human_pt
			_add_line(p_prev, p_curr, arc_col)
			p_prev = p_curr

	# -------------------------------------------------------------
	# 4. CENTRAL GRAVITY VECTOR & GYRO ROTATIONAL ARCS
	# -------------------------------------------------------------
	var g_norm := gravity.normalized()
	var g_proj := Vector3(g_norm.x, g_norm.y, 0.0)
	var g_len: float = clamp(g_proj.length(), 0.0, 1.0) * (radius * 0.28)
	if g_len > 0.02:
		var g_tip := g_proj.normalized() * g_len
		var g_col := Color(0.3, 1.0, 0.5, 0.75)
		_add_line(Vector3.ZERO, g_tip, g_col)
		_add_line(g_tip, g_tip + Vector3(-g_tip.y, g_tip.x, 0.0).normalized() * 0.025, g_col)
		_add_line(g_tip, g_tip - Vector3(-g_tip.y, g_tip.x, 0.0).normalized() * 0.025, g_col)

	var gyro_speed: float = gyro.length()
	var arc_len: float = clamp(0.3 + gyro_speed * 0.8, 0.3, PI * 1.5)
	var r_gyro: float = radius * 0.20
	var gyro_col := Color(0.1, 0.75, 1.0, 0.60)
	_add_arc(Vector3.ZERO, r_gyro, gyro_orbit_angle, gyro_orbit_angle + arc_len, 24, gyro_col)

	# -------------------------------------------------------------
	# 5. MNN NEURAL RESONANCE BREATHING RAYS
	# -------------------------------------------------------------
	if thought_pulse > 0.02:
		var ray_count: int = 16
		var r_wave: float = radius * (0.35 + thought_pulse * 0.65)
		var ray_col := Color(0.35, 0.9, 1.0, thought_pulse * 0.45)
		for i in range(ray_count):
			var a: float = (float(i) / float(ray_count)) * TAU + celestial_rot
			var r_start: float = radius * 0.25
			var pt1 := Vector3(cos(a) * r_start, sin(a) * r_start, 0.0)
			var pt2 := Vector3(cos(a) * r_wave, sin(a) * r_wave, 0.0)
			_add_line(pt1, pt2, ray_col)
			
	mandala_mesh.surface_end()
