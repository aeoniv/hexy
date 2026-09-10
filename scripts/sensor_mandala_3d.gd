class_name SensorMandala3D
extends Node3D

## Cybernetic 3D Sensor Mandala Visualizer
## Surrounds the Hexy tensegrity geometry with a sacred cybernetic HUD:
## 1. Celestial Outer Ring with 64 Hexagram Graduation Ticks & Compass North Pointer
## 2. 8 Ba-Gua Trigram Station Hubs with rendered solid/broken lines & dual-color highlights
## 3. Real-Time 3D Gravity Vector Needle projecting physical tilt
## 4. Gyroscopic Whirlpool Orbit Arcs driven by live angular velocity
## 5. Dwell Hysteresis Circular Charge Arc (Schmitt-trigger lock-in)
## 6. Kinetic Shake-to-Cast Energy Reservoir Arc
## 7. MNN Neural Resonance Breathing Rays during asynchronous token streaming

@export var enabled: bool = true
@export var radius: float = 1.25
@export var is_thinking: bool = false
@export var thought_pulse: float = 0.0

var mandala_mesh: ImmediateMesh
var mesh_instance: MeshInstance3D
var material: StandardMaterial3D

# Afferent Telemetry Cache
var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
var gyro: Vector3 = Vector3.ZERO
var heading_deg: float = 0.0
var jerk: float = 0.0
var shake_progress: float = 0.0
var dwell_progress: float = 0.0
var lower_tri: int = 7 # Heaven
var upper_tri: int = 7 # Heaven
var candidate_tri: int = 7

var gyro_orbit_angle: float = 0.0
var celestial_rot: float = 0.0

# Trigram definitions: 3 bits (0=broken Yin, 1=solid Yang)
# 0: Earth (0b000), 1: Thunder (0b001), 2: Water (0b010), 3: Lake (0b011),
# 4: Mountain (0b100), 5: Fire (0b101), 6: Wind (0b110), 7: Heaven (0b111)
const TRIGRAM_BITS: Array[int] = [0b000, 0b001, 0b010, 0b011, 0b100, 0b101, 0b110, 0b111]

# Spatial Ba-Gua Station Angles around the Mandala (Physical Cardinal layout)
const BAGUA_STATIONS: Array[Dictionary] = [
	{"trigram": 7, "angle": -PI * 0.5, "name": "Heaven"},
	{"trigram": 3, "angle": -PI * 0.25, "name": "Lake"},
	{"trigram": 5, "angle": 0.0, "name": "Fire"},
	{"trigram": 1, "angle": PI * 0.25, "name": "Thunder"},
	{"trigram": 0, "angle": PI * 0.5, "name": "Earth"},
	{"trigram": 4, "angle": PI * 0.75, "name": "Mountain"},
	{"trigram": 2, "angle": PI, "name": "Water"},
	{"trigram": 6, "angle": -PI * 0.75, "name": "Wind"}
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
	if data.has("shake_progress"): shake_progress = data["shake_progress"]
	if data.has("dwell_progress"): dwell_progress = data["dwell_progress"]
	if data.has("lower_trigram"): lower_tri = data["lower_trigram"]
	if data.has("upper_trigram"): upper_tri = data["upper_trigram"]
	if data.has("candidate_trigram"): candidate_tri = data["candidate_trigram"]

func set_thinking(state: bool) -> void:
	is_thinking = state

func _process(delta: float) -> void:
	if not enabled or not mandala_mesh:
		return
		
	var now: float = Time.get_ticks_msec() * 0.001
	
	# Gyro Orbit Integration
	var gyro_speed: float = gyro.length()
	gyro_orbit_angle += (1.2 + gyro_speed * 2.5) * delta
	celestial_rot += 0.04 * delta
	
	# MNN Neural Breathing
	if is_thinking:
		thought_pulse = sin(now * 8.0) * 0.5 + 0.5
	else:
		thought_pulse = move_toward(thought_pulse, 0.0, delta * 3.0)
		
	_render_mandala(now)

func _render_mandala(t: float) -> void:
	mandala_mesh.clear_surfaces()
	mandala_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# -------------------------------------------------------------
	# 1. CELESTIAL OUTER RING & 64 HEXAGRAM GRADUATION TICKS
	# -------------------------------------------------------------
	var r_outer: float = radius
	var segments: int = 64
	var base_ring_col: Color = Color(0.2, 0.5, 0.85, 0.32)
	if is_thinking:
		base_ring_col = base_ring_col.lerp(Color(0.4, 0.9, 1.0, 0.8), thought_pulse)
		
	for i in range(segments):
		var th1: float = (float(i) / segments) * TAU
		var th2: float = (float(i + 1) / segments) * TAU
		
		var p1 := Vector3(cos(th1) * r_outer, sin(th1) * r_outer, 0.0)
		var p2 := Vector3(cos(th2) * r_outer, sin(th2) * r_outer, 0.0)
		
		mandala_mesh.surface_set_color(base_ring_col)
		mandala_mesh.surface_add_vertex(p1)
		mandala_mesh.surface_set_color(base_ring_col)
		mandala_mesh.surface_add_vertex(p2)
		
		# 64 Radial Hexagram Ticks
		var is_major_tick: bool = (i % 8 == 0)
		var tick_len: float = 0.045 if is_major_tick else 0.02
		var tick_col: Color = Color(0.35, 0.8, 1.0, 0.7) if is_major_tick else Color(0.15, 0.45, 0.7, 0.25)
		
		var p_tick_in := Vector3(cos(th1) * (r_outer - tick_len), sin(th1) * (r_outer - tick_len), 0.0)
		mandala_mesh.surface_set_color(tick_col)
		mandala_mesh.surface_add_vertex(p1)
		mandala_mesh.surface_set_color(tick_col)
		mandala_mesh.surface_add_vertex(p_tick_in)
		
	# Compass North Pointer on Outer Ring
	var north_rad: float = deg_to_rad(heading_deg - 90.0)
	var north_tip := Vector3(cos(north_rad) * (r_outer + 0.08), sin(north_rad) * (r_outer + 0.08), 0.0)
	var north_left := Vector3(cos(north_rad - 0.08) * (r_outer - 0.02), sin(north_rad - 0.08) * (r_outer - 0.02), 0.0)
	var north_right := Vector3(cos(north_rad + 0.08) * (r_outer - 0.02), sin(north_rad + 0.08) * (r_outer - 0.02), 0.0)
	var north_col := Color(0.2, 1.0, 0.8, 0.95)
	
	mandala_mesh.surface_set_color(north_col)
	mandala_mesh.surface_add_vertex(north_left)
	mandala_mesh.surface_set_color(north_col)
	mandala_mesh.surface_add_vertex(north_tip)
	mandala_mesh.surface_set_color(north_col)
	mandala_mesh.surface_add_vertex(north_tip)
	mandala_mesh.surface_set_color(north_col)
	mandala_mesh.surface_add_vertex(north_right)

	# -------------------------------------------------------------
	# 2. BA-GUA 8 TRIGRAM STATION HUBS (Renders 3-Line Trigram Glyphs)
	# -------------------------------------------------------------
	var r_bagua: float = radius * 0.88
	
	for station in BAGUA_STATIONS:
		var tri_id: int = station["trigram"]
		var ang: float = station["angle"]
		var center := Vector3(cos(ang) * r_bagua, sin(ang) * r_bagua, 0.0)
		
		var is_lower: bool = (tri_id == lower_tri) # Gravity classified
		var is_upper: bool = (tri_id == upper_tri) # Heading classified
		var is_cand: bool = (tri_id == candidate_tri)
		
		var hub_col: Color
		if is_lower and is_upper:
			hub_col = Color(1.0, 0.85, 0.3, 0.95).lerp(Color(0.2, 0.95, 1.0, 0.95), sin(t * 6.0) * 0.5 + 0.5)
		elif is_lower:
			hub_col = Color(1.0, 0.72, 0.15, 0.95) # Amber/Gold for Earth/Gravity
		elif is_upper:
			hub_col = Color(0.25, 0.9, 1.0, 0.95)  # Cyan for Heaven/Azimuth
		else:
			hub_col = Color(0.25, 0.5, 0.75, 0.3)
			
		# Hub Anchor Diamond
		var d_sz: float = 0.025 if (is_lower or is_upper) else 0.015
		var d_top := center + Vector3(0.0, d_sz, 0.0)
		var d_bot := center - Vector3(0.0, d_sz, 0.0)
		var d_left := center - Vector3(d_sz, 0.0, 0.0)
		var d_right := center + Vector3(d_sz, 0.0, 0.0)
		
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_top)
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_right)
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_right)
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_bot)
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_bot)
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_left)
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_left)
		mandala_mesh.surface_set_color(hub_col)
		mandala_mesh.surface_add_vertex(d_top)
		
		# Radial Spoke to Center
		var spoke_col := hub_col * Color(1.0, 1.0, 1.0, 0.4 if (is_lower or is_upper) else 0.08)
		mandala_mesh.surface_set_color(spoke_col)
		mandala_mesh.surface_add_vertex(center * 0.45)
		mandala_mesh.surface_set_color(spoke_col)
		mandala_mesh.surface_add_vertex(center - center.normalized() * (d_sz * 1.5))
		
		# Render the 3 Trigram Lines (Bottom to Top)
		var tri_bits: int = TRIGRAM_BITS[tri_id]
		var glyph_w: float = 0.045
		var line_spacing: float = 0.014
		var glyph_offset_rad: float = (r_bagua - 0.065)
		var glyph_center := Vector3(cos(ang) * glyph_offset_rad, sin(ang) * glyph_offset_rad, 0.0)
		
		# Tangent and Normal vectors for aligning lines radially
		var v_rad: Vector3 = center.normalized()
		var v_tan: Vector3 = Vector3(-v_rad.y, v_rad.x, 0.0)
		
		for l_idx in range(3):
			var is_yang: bool = bool((tri_bits >> l_idx) & 1)
			var l_center: Vector3 = glyph_center + v_rad * (float(l_idx - 1) * line_spacing)
			
			if is_yang:
				# Solid Yang Line: continuous
				var p_a: Vector3 = l_center - v_tan * glyph_w
				var p_b: Vector3 = l_center + v_tan * glyph_w
				mandala_mesh.surface_set_color(hub_col)
				mandala_mesh.surface_add_vertex(p_a)
				mandala_mesh.surface_set_color(hub_col)
				mandala_mesh.surface_add_vertex(p_b)
			else:
				# Broken Yin Line: two segments with central gap
				var gap_w: float = glyph_w * 0.28
				var p_a1: Vector3 = l_center - v_tan * glyph_w
				var p_b1: Vector3 = l_center - v_tan * gap_w
				var p_a2: Vector3 = l_center + v_tan * gap_w
				var p_b2: Vector3 = l_center + v_tan * glyph_w
				mandala_mesh.surface_set_color(hub_col)
				mandala_mesh.surface_add_vertex(p_a1)
				mandala_mesh.surface_set_color(hub_col)
				mandala_mesh.surface_add_vertex(p_b1)
				mandala_mesh.surface_set_color(hub_col)
				mandala_mesh.surface_add_vertex(p_a2)
				mandala_mesh.surface_set_color(hub_col)
				mandala_mesh.surface_add_vertex(p_b2)
				
		# -------------------------------------------------------------
		# 5. DWELL HYSTERESIS CHARGING RING (Schmitt Trigger Lock-in)
		# -------------------------------------------------------------
		if is_cand and dwell_progress > 0.01:
			var dwell_r: float = 0.065
			var dwell_segs: int = int(round(dwell_progress * 16.0))
			var dwell_col: Color = Color(1.0, 0.9, 0.3, 0.9).lerp(Color(1.0, 1.0, 1.0, 1.0), dwell_progress)
			for d_i in range(dwell_segs):
				var d_th1: float = (float(d_i) / 16.0) * TAU
				var d_th2: float = (float(d_i + 1) / 16.0) * TAU
				var dp1: Vector3 = center + Vector3(cos(d_th1) * dwell_r, sin(d_th1) * dwell_r, 0.0)
				var dp2: Vector3 = center + Vector3(cos(d_th2) * dwell_r, sin(d_th2) * dwell_r, 0.0)
				mandala_mesh.surface_set_color(dwell_col)
				mandala_mesh.surface_add_vertex(dp1)
				mandala_mesh.surface_set_color(dwell_col)
				mandala_mesh.surface_add_vertex(dp2)

	# -------------------------------------------------------------
	# 3. LIVE 3D GRAVITY VECTOR NEEDLE
	# -------------------------------------------------------------
	var g_len: float = gravity.length()
	if g_len > 0.5:
		var g_norm: Vector3 = gravity / g_len
		var g_needle_dir := Vector3(-g_norm.x, -g_norm.y, g_norm.z * 0.4).normalized()
		var needle_len: float = clamp(g_len / 9.8, 0.2, 1.1) * (radius * 0.75)
		var needle_tip: Vector3 = g_needle_dir * needle_len
		var needle_col := Color(0.2, 1.0, 0.5, 0.95).lerp(Color(1.0, 0.4, 0.1, 0.95), clamp(abs(g_norm.x) + abs(g_norm.z), 0.0, 1.0))
		
		# Draw Needle Line
		mandala_mesh.surface_set_color(needle_col * Color(1, 1, 1, 0.2))
		mandala_mesh.surface_add_vertex(Vector3.ZERO)
		mandala_mesh.surface_set_color(needle_col)
		mandala_mesh.surface_add_vertex(needle_tip)
		
		# Arrowhead Diamond
		var perp := Vector3(-needle_tip.y, needle_tip.x, 0.0).normalized() * 0.03
		mandala_mesh.surface_set_color(needle_col)
		mandala_mesh.surface_add_vertex(needle_tip)
		mandala_mesh.surface_set_color(needle_col)
		mandala_mesh.surface_add_vertex(needle_tip - needle_tip.normalized() * 0.06 + perp)
		mandala_mesh.surface_set_color(needle_col)
		mandala_mesh.surface_add_vertex(needle_tip)
		mandala_mesh.surface_set_color(needle_col)
		mandala_mesh.surface_add_vertex(needle_tip - needle_tip.normalized() * 0.06 - perp)

	# -------------------------------------------------------------
	# 4. GYROSCOPIC WHIRLPOOL ORBIT ARCS
	# -------------------------------------------------------------
	var g_speed: float = gyro.length()
	var gyro_col := Color(0.2, 0.7, 1.0, 0.45).lerp(Color(1.0, 0.3, 0.8, 0.85), clamp(g_speed / 4.0, 0.0, 1.0))
	var arc_r: float = radius * 0.52
	for arc_idx in range(3):
		var arc_base_ang: float = gyro_orbit_angle + float(arc_idx) * (TAU / 3.0)
		for a_i in range(8):
			var a1: float = arc_base_ang + (float(a_i) / 16.0) * TAU * 0.3
			var a2: float = arc_base_ang + (float(a_i + 1) / 16.0) * TAU * 0.3
			var ap1 := Vector3(cos(a1) * arc_r, sin(a1) * arc_r, sin(a1 * 2.0) * 0.08)
			var ap2 := Vector3(cos(a2) * arc_r, sin(a2) * arc_r, sin(a2 * 2.0) * 0.08)
			var alpha_trail: float = float(a_i) / 8.0
			var c := gyro_col * Color(1, 1, 1, alpha_trail)
			mandala_mesh.surface_set_color(c)
			mandala_mesh.surface_add_vertex(ap1)
			mandala_mesh.surface_set_color(c)
			mandala_mesh.surface_add_vertex(ap2)

	# -------------------------------------------------------------
	# 6. KINETIC SHAKE-TO-CAST ENERGY RESERVOIR ARC
	# -------------------------------------------------------------
	if shake_progress > 0.01:
		var shake_r: float = radius * 1.05
		var shake_sweep: float = PI * 0.65 * shake_progress
		var shake_start: float = PI * 0.5 - shake_sweep * 0.5
		var s_segs: int = int(round(shake_progress * 24.0)) + 2
		var shake_col: Color = Color(1.0, 0.2, 0.6, 0.95).lerp(Color(1.0, 0.9, 0.2, 1.0), shake_progress)
		
		for s_i in range(s_segs):
			var sa1: float = shake_start + (float(s_i) / s_segs) * shake_sweep
			var sa2: float = shake_start + (float(s_i + 1) / s_segs) * shake_sweep
			var sp1 := Vector3(cos(sa1) * shake_r, sin(sa1) * shake_r, 0.0)
			var sp2 := Vector3(cos(sa2) * shake_r, sin(sa2) * shake_r, 0.0)
			mandala_mesh.surface_set_color(shake_col)
			mandala_mesh.surface_add_vertex(sp1)
			mandala_mesh.surface_set_color(shake_col)
			mandala_mesh.surface_add_vertex(sp2)

	# -------------------------------------------------------------
	# 7. MNN NEURAL RESONANCE BREATHING RAYS
	# -------------------------------------------------------------
	if thought_pulse > 0.05:
		var ray_count: int = 16
		var ray_col := Color(0.3, 0.95, 1.0, 0.6 * thought_pulse)
		for r_i in range(ray_count):
			var r_th: float = (float(r_i) / ray_count) * TAU + celestial_rot
			var ray_outer := Vector3(cos(r_th) * radius, sin(r_th) * radius, 0.0)
			var ray_inner := Vector3(cos(r_th) * (radius * 0.4), sin(r_th) * (radius * 0.4), 0.0)
			mandala_mesh.surface_set_color(ray_col)
			mandala_mesh.surface_add_vertex(ray_outer)
			mandala_mesh.surface_set_color(Color(ray_col.r, ray_col.g, ray_col.b, 0.0))
			mandala_mesh.surface_add_vertex(ray_inner)

	mandala_mesh.surface_end()
