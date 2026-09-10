class_name SensorMandala3D
extends Node3D

## Cybernetic 3D Sensor Mandala Visualizer
## Surrounds the Hexy tensegrity geometry with a sacred cybernetic HUD:
## 1. Celestial Outer Ring with 64 Hexagram Graduation Ticks & Compass North Pointer
## 2. 8 Dedicated Orbital Sensor Nodes showcasing real-time physical sensor states:
##    - Light Node (Ambient Lux solar flare / twilight core)
##    - Shake / Jerk Node (Kinetic coins divination reservoir)
##    - Gyroscope Node (3D tri-axis gimbal whirlpool rings)
##    - Chronos Node (Local solar hour / 24-division astrolabe)
##    - Proximity Node (Occultation / Palm eclipse ripple waves)
##    - Battery Node (Vitality metabolism / hexagonal Chi gauge)
##    - Gravity Node (3D inclinometer gimbal & pendulum plumb-bob)
##    - Compass Node (Geomagnetic lodestone star & polar needle)
## 3. Radiant Cybernetic Tensegrity Filaments connecting each sensor node to the creature core
## 4. 8 Ba-Gua Trigram Stations with rendered solid/broken lines & dual-color highlights
## 5. MNN Neural Resonance Breathing Rays during asynchronous token streaming

@export var enabled: bool = true
@export var radius: float = 0.78
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
var lower_tri: int = 7 # Heaven
var upper_tri: int = 7 # Heaven

var gyro_orbit_angle: float = 0.0
var celestial_rot: float = 0.0

# Trigram definitions: 3 bits (0=broken Yin, 1=solid Yang)
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
	celestial_rot += 0.04 * delta
	
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
	var r_nodes: float = radius * 1.06
	var r_inner_tether: float = 0.42
	
	# -------------------------------------------------------------
	# 1. CELESTIAL OUTER RING & 64 HEXAGRAM GRADUATION TICKS
	# -------------------------------------------------------------
	var segments: int = 64
	var base_ring_col: Color = Color(0.2, 0.5, 0.85, 0.28)
	if is_thinking:
		base_ring_col = base_ring_col.lerp(Color(0.4, 0.9, 1.0, 0.75), thought_pulse)
		
	for i in range(segments):
		var th1: float = (float(i) / segments) * TAU
		var th2: float = (float(i + 1) / segments) * TAU
		var p1 := Vector3(cos(th1) * r_outer, sin(th1) * r_outer, 0.0)
		var p2 := Vector3(cos(th2) * r_outer, sin(th2) * r_outer, 0.0)
		_add_line(p1, p2, base_ring_col)
		
		var is_major_tick: bool = (i % 8 == 0)
		var tick_len: float = 0.045 if is_major_tick else 0.02
		var tick_col: Color = Color(0.35, 0.8, 1.0, 0.65) if is_major_tick else Color(0.15, 0.45, 0.7, 0.2)
		var p_tick_in := Vector3(cos(th1) * (r_outer - tick_len), sin(th1) * (r_outer - tick_len), 0.0)
		_add_line(p1, p_tick_in, tick_col)
		
	# Compass North Pointer on Outer Rim
	var north_rad: float = deg_to_rad(heading_deg - 90.0)
	var north_tip := Vector3(cos(north_rad) * (r_outer + 0.08), sin(north_rad) * (r_outer + 0.08), 0.0)
	var north_left := Vector3(cos(north_rad - 0.08) * (r_outer - 0.02), sin(north_rad - 0.08) * (r_outer - 0.02), 0.0)
	var north_right := Vector3(cos(north_rad + 0.08) * (r_outer - 0.02), sin(north_rad + 0.08) * (r_outer - 0.02), 0.0)
	var north_col := Color(0.2, 1.0, 0.8, 0.9)
	_add_line(north_left, north_tip, north_col)
	_add_line(north_tip, north_right, north_col)

	# -------------------------------------------------------------
	# 2. THE 8 DEDICATED ORBITAL SENSOR NODES (Arranged like a Sacred Mandala)
	# -------------------------------------------------------------
	# Angles: 0: Zenith(-PI/2), 1: NE(-PI/4), 2: E(0), 3: SE(PI/4),
	#         4: Nadir(PI/2), 5: SW(3PI/4), 6: W(PI), 7: NW(-3PI/4)
	var node_angles: Array[float] = [
		-PI * 0.5,   # Node 0: Light (Zenith)
		-PI * 0.25,  # Node 1: Shake / Jerk (NE)
		0.0,         # Node 2: Gyroscope (East)
		PI * 0.25,   # Node 3: Chronos / Solar Hour (SE)
		PI * 0.5,    # Node 4: Proximity / Eclipse Eye (Nadir)
		PI * 0.75,   # Node 5: Battery / Chi (SW)
		PI,          # Node 6: Gravity / Inclinometer (West)
		-PI * 0.75   # Node 7: Compass / Geomagnetic (NW)
	]
	
	# Render Tensegrity Filaments from Creature Core to each Sensor Node
	for i in range(8):
		var ang: float = node_angles[i]
		var n_center := Vector3(cos(ang) * r_nodes, sin(ang) * r_nodes, 0.0)
		var core_pt := Vector3(cos(ang) * r_inner_tether, sin(ang) * r_inner_tether, 0.0)
		
		# Filament wave excitation
		var strain_val: float = float(line_strains[i % 6]) if i < 6 else float(line_strains[0])
		var tether_alpha: float = 0.15 + strain_val * 0.6 + thought_pulse * 0.35
		var tether_col := Color(0.25, 0.75, 1.0, tether_alpha)
		_add_line(core_pt, n_center - n_center.normalized() * 0.07, tether_col)
		
		# Electric pulse particle along filament
		if strain_val > 0.2 or is_thinking:
			var wave_phase: float = fmod(t * (2.0 + strain_val * 4.0), 1.0)
			var p_wave := core_pt.lerp(n_center, wave_phase)
			var p_w2 := p_wave + Vector3(0.0, 0.015, 0.0)
			_add_line(p_wave, p_w2, Color(1.0, 0.9, 0.4, 0.9))

	# Render Individual Specialized Sensor Nodes:
	# Node 0: 💡 Light Sensor Node
	var c_light := Vector3(cos(node_angles[0]) * r_nodes, sin(node_angles[0]) * r_nodes, 0.0)
	_render_node_light(c_light, lux, t, float(line_strains[4]))
	
	# Node 1: ⚡ Kinetic Shake / Jerk Node
	var c_shake := Vector3(cos(node_angles[1]) * r_nodes, sin(node_angles[1]) * r_nodes, 0.0)
	_render_node_shake(c_shake, jerk, shake_progress, t, float(line_strains[0]))
	
	# Node 2: 🌀 Gyroscope Node
	var c_gyro := Vector3(cos(node_angles[2]) * r_nodes, sin(node_angles[2]) * r_nodes, 0.0)
	_render_node_gyro(c_gyro, gyro, t, kinetic_excitation)
	
	# Node 3: ⏳ Chronos / Solar Hour Node
	var c_chronos := Vector3(cos(node_angles[3]) * r_nodes, sin(node_angles[3]) * r_nodes, 0.0)
	_render_node_chronos(c_chronos, solar_hour, t)
	
	# Node 4: 👁️ Proximity / Eclipse Eye Node
	var c_prox := Vector3(cos(node_angles[4]) * r_nodes, sin(node_angles[4]) * r_nodes, 0.0)
	_render_node_proximity(c_prox, proximity, t, float(line_strains[3]))
	
	# Node 5: 🔋 Chi Vitality / Battery Node
	var c_bat := Vector3(cos(node_angles[5]) * r_nodes, sin(node_angles[5]) * r_nodes, 0.0)
	_render_node_battery(c_bat, battery, t)
	
	# Node 6: 📐 Gravity Inclinometer Node
	var c_grav := Vector3(cos(node_angles[6]) * r_nodes, sin(node_angles[6]) * r_nodes, 0.0)
	_render_node_gravity(c_grav, gravity, t, float(line_strains[1]))
	
	# Node 7: 🧭 Compass / Geomagnetic Node
	var c_comp := Vector3(cos(node_angles[7]) * r_nodes, sin(node_angles[7]) * r_nodes, 0.0)
	_render_node_compass(c_comp, heading_deg, t, float(line_strains[5]))

	# -------------------------------------------------------------
	# 3. BA-GUA 8 TRIGRAM HUBS (Solid/Broken Line Manifestations)
	# -------------------------------------------------------------
	var r_bagua: float = radius * 0.86
	for station in BAGUA_STATIONS:
		var tri_id: int = station["trigram"]
		var ang: float = station["angle"]
		var center := Vector3(cos(ang) * r_bagua, sin(ang) * r_bagua, 0.0)
		
		var is_lower: bool = (tri_id == lower_tri)
		var is_upper: bool = (tri_id == upper_tri)
		
		var hub_col: Color
		if is_lower and is_upper:
			hub_col = Color(1.0, 0.85, 0.3, 0.95).lerp(Color(0.2, 0.95, 1.0, 0.95), sin(t * 6.0) * 0.5 + 0.5)
		elif is_lower:
			hub_col = Color(1.0, 0.72, 0.15, 0.95)
		elif is_upper:
			hub_col = Color(0.25, 0.9, 1.0, 0.95)
		else:
			hub_col = Color(0.25, 0.5, 0.75, 0.28)
			
		var d_sz: float = 0.022 if (is_lower or is_upper) else 0.014
		var d_top := center + Vector3(0.0, d_sz, 0.0)
		var d_bot := center - Vector3(0.0, d_sz, 0.0)
		var d_left := center - Vector3(d_sz, 0.0, 0.0)
		var d_right := center + Vector3(d_sz, 0.0, 0.0)
		_add_line(d_top, d_right, hub_col)
		_add_line(d_right, d_bot, hub_col)
		_add_line(d_bot, d_left, hub_col)
		_add_line(d_left, d_top, hub_col)
		
		# Trigram lines
		var tri_bits: int = TRIGRAM_BITS[tri_id]
		var glyph_w: float = 0.04
		var line_spacing: float = 0.013
		var glyph_center := center - center.normalized() * 0.05
		var v_rad: Vector3 = center.normalized()
		var v_tan: Vector3 = Vector3(-v_rad.y, v_rad.x, 0.0)
		
		for l_idx in range(3):
			var is_yang: bool = bool((tri_bits >> l_idx) & 1)
			var l_center: Vector3 = glyph_center + v_rad * (float(l_idx - 1) * line_spacing)
			if is_yang:
				_add_line(l_center - v_tan * glyph_w, l_center + v_tan * glyph_w, hub_col)
			else:
				var gap_w: float = glyph_w * 0.28
				_add_line(l_center - v_tan * glyph_w, l_center - v_tan * gap_w, hub_col)
				_add_line(l_center + v_tan * gap_w, l_center + v_tan * glyph_w, hub_col)

	# -------------------------------------------------------------
	# 4. CENTRAL 3D GRAVITY PENDULUM VECTOR & GYRO WHIRLPOOL ARCS
	# -------------------------------------------------------------
	var g_norm := gravity.normalized()
	var g_proj := Vector3(g_norm.x, g_norm.y, 0.0)
	var g_len: float = clamp(g_proj.length(), 0.0, 1.0) * (radius * 0.35)
	if g_len > 0.02:
		var g_tip := g_proj.normalized() * g_len
		var g_col := Color(0.2, 0.95, 0.4, 0.85)
		_add_line(Vector3.ZERO, g_tip, g_col)
		_add_line(g_tip, g_tip + Vector3(-g_tip.y, g_tip.x, 0.0).normalized() * 0.03, g_col)
		_add_line(g_tip, g_tip - Vector3(-g_tip.y, g_tip.x, 0.0).normalized() * 0.03, g_col)
		
	# Central Gyro Whirlpool Arc
	var gyro_speed: float = gyro.length()
	var arc_len: float = clamp(0.3 + gyro_speed * 0.8, 0.3, PI * 1.5)
	var r_gyro: float = radius * 0.22
	var gyro_col := Color(0.1, 0.65, 1.0, 0.65)
	_add_arc(Vector3.ZERO, r_gyro, gyro_orbit_angle, gyro_orbit_angle + arc_len, 24, gyro_col)

	# -------------------------------------------------------------
	# 5. MNN NEURAL RESONANCE BREATHING RAYS
	# -------------------------------------------------------------
	if thought_pulse > 0.02:
		var ray_count: int = 16
		var r_wave: float = radius * (0.3 + thought_pulse * 0.7)
		var ray_col := Color(0.3, 0.85, 1.0, thought_pulse * 0.45)
		for i in range(ray_count):
			var a: float = (float(i) / float(ray_count)) * TAU + t * 0.5
			var r_pt := Vector3(cos(a) * r_wave, sin(a) * r_wave, 0.0)
			_add_line(Vector3.ZERO, r_pt, ray_col)

	mandala_mesh.surface_end()

# -----------------------------------------------------------------
# SENSOR NODE RENDERING SUBROUTINES
# -----------------------------------------------------------------

func _render_node_light(c: Vector3, lux_val: float, t: float, strain: float) -> void:
	var r_base: float = 0.042
	var col_gold := Color(1.0, 0.88, 0.25, 0.95)
	_add_circle(c, r_base, 16, col_gold * Color(1.0, 1.0, 1.0, 0.5))
	
	# Radiant Solar Rays scaled by Illuminance
	var num_rays: int = 12
	var ray_mag: float = 0.02 + clamp(lux_val / 400.0, 0.0, 1.0) * 0.05 + sin(t * 5.0) * 0.008
	for i in range(num_rays):
		var a: float = (float(i) / float(num_rays)) * TAU + t * 0.2
		var p_start := c + Vector3(cos(a) * r_base, sin(a) * r_base, 0.0)
		var p_end := c + Vector3(cos(a) * (r_base + ray_mag), sin(a) * (r_base + ray_mag), 0.0)
		_add_line(p_start, p_end, col_gold)
		
	# Core Diamond
	var cd: float = 0.015
	_add_line(c + Vector3(0.0, cd, 0.0), c + Vector3(cd, 0.0, 0.0), col_gold)
	_add_line(c + Vector3(cd, 0.0, 0.0), c - Vector3(0.0, cd, 0.0), col_gold)
	_add_line(c - Vector3(0.0, cd, 0.0), c - Vector3(cd, 0.0, 0.0), col_gold)
	_add_line(c - Vector3(cd, 0.0, 0.0), c + Vector3(0.0, cd, 0.0), col_gold)
	
	if strain > 0.15:
		_add_circle(c, r_base + 0.02, 16, Color(1.0, 0.5, 0.1, strain * 0.8))

func _render_node_shake(c: Vector3, jerk_val: float, shake_prog: float, t: float, _strain: float) -> void:
	var r_base: float = 0.042
	var col_amber := Color(1.0, 0.65, 0.15, 0.95)
	_add_circle(c, r_base, 16, col_amber * Color(1.0, 1.0, 1.0, 0.4))
	
	# Circular shake reservoir charge arc
	if shake_prog > 0.01:
		_add_arc(c, r_base + 0.015, -PI * 0.5, -PI * 0.5 + shake_prog * TAU, 18, Color(1.0, 0.9, 0.2, 0.95))
		
	# 3 Orbiting Divination Coin Discs
	var coin_orbit_r: float = 0.035
	var coin_spin: float = t * 3.0 + shake_prog * 10.0
	for i in range(3):
		var a: float = (float(i) / 3.0) * TAU + coin_spin
		var c_coin := c + Vector3(cos(a) * coin_orbit_r, sin(a) * coin_orbit_r, 0.0)
		_add_circle(c_coin, 0.01, 8, col_amber)
		
	# High jerk lightning sparks
	if jerk_val > 10.0:
		var spark_a := c + Vector3(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04), 0.0)
		var spark_b := c + Vector3(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04), 0.0)
		_add_line(spark_a, spark_b, Color(1.0, 1.0, 0.7, 0.95))

func _render_node_gyro(c: Vector3, gyro_vec: Vector3, t: float, _excitation: float) -> void:
	var r_base: float = 0.042
	var col_gyro := Color(0.2, 0.65, 1.0, 0.95)
	_add_circle(c, r_base, 16, col_gyro * Color(1.0, 1.0, 1.0, 0.35))
	
	# Triple nested spinning gimbal rings
	var g_speed: float = gyro_vec.length()
	var rot1: float = t * 1.5 + g_speed * 2.0
	var rot2: float = -t * 1.8 - g_speed * 2.5
	
	# Ring 1 (Horizontal squashed ellipse)
	for i in range(12):
		var a1: float = (float(i) / 12.0) * TAU + rot1
		var a2: float = (float(i + 1) / 12.0) * TAU + rot1
		var p1 := c + Vector3(cos(a1) * 0.04, sin(a1) * 0.02, 0.0)
		var p2 := c + Vector3(cos(a2) * 0.04, sin(a2) * 0.02, 0.0)
		_add_line(p1, p2, col_gyro)
		
	# Ring 2 (Vertical squashed ellipse)
	for i in range(12):
		var a1: float = (float(i) / 12.0) * TAU + rot2
		var a2: float = (float(i + 1) / 12.0) * TAU + rot2
		var p1 := c + Vector3(cos(a1) * 0.02, sin(a1) * 0.04, 0.0)
		var p2 := c + Vector3(cos(a2) * 0.02, sin(a2) * 0.04, 0.0)
		_add_line(p1, p2, col_gyro * Color(1.0, 1.0, 1.0, 0.7))

func _render_node_chronos(c: Vector3, hr: float, _t: float) -> void:
	var r_base: float = 0.042
	var col_chr := Color(0.85, 0.9, 1.0, 0.85)
	_add_circle(c, r_base, 16, col_chr * Color(1.0, 1.0, 1.0, 0.35))
	
	# 12-Hour Astrolabe Dial Ticks
	for i in range(12):
		var a: float = (float(i) / 12.0) * TAU - PI * 0.5
		var p_in := c + Vector3(cos(a) * (r_base - 0.012), sin(a) * (r_base - 0.012), 0.0)
		var p_out := c + Vector3(cos(a) * r_base, sin(a) * r_base, 0.0)
		_add_line(p_in, p_out, col_chr * Color(1.0, 1.0, 1.0, 0.5))
		
	# Sun/Moon Dial Hand
	var hr_ang: float = (hr / 24.0) * TAU - PI * 0.5
	var hand_tip := c + Vector3(cos(hr_ang) * 0.038, sin(hr_ang) * 0.038, 0.0)
	_add_line(c, hand_tip, Color(1.0, 0.9, 0.5, 0.95))
	_add_circle(hand_tip, 0.006, 6, Color(1.0, 0.9, 0.5, 0.95))

func _render_node_proximity(c: Vector3, prox_dist: float, t: float, _strain: float) -> void:
	var r_base: float = 0.042
	var is_near: bool = (prox_dist >= 0.0 and prox_dist < 3.5)
	
	if is_near:
		# Occultation / Palm Eclipse: Violet expanding radar echo rings
		var col_eclipse := Color(0.9, 0.35, 1.0, 0.95)
		_add_circle(c, r_base, 16, col_eclipse)
		for ring in range(3):
			var r_echo: float = r_base + fmod(t * 0.15 + float(ring) * 0.025, 0.065)
			var a_fade: float = clamp(1.0 - (r_echo - r_base) / 0.065, 0.0, 1.0)
			_add_circle(c, r_echo, 16, col_eclipse * Color(1.0, 1.0, 1.0, a_fade * 0.7))
		# Dilated pupil
		_add_circle(c, 0.028, 12, col_eclipse)
	else:
		# Open sky calm aperture
		var col_open := Color(0.25, 0.75, 0.95, 0.6)
		_add_circle(c, r_base, 16, col_open * Color(1.0, 1.0, 1.0, 0.35))
		_add_circle(c, 0.012, 8, col_open)
		# Iris aperture blades
		for i in range(6):
			var a: float = (float(i) / 6.0) * TAU
			var p1 := c + Vector3(cos(a) * 0.015, sin(a) * 0.015, 0.0)
			var p2 := c + Vector3(cos(a + 0.4) * r_base, sin(a + 0.4) * r_base, 0.0)
			_add_line(p1, p2, col_open * Color(1.0, 1.0, 1.0, 0.4))

func _render_node_battery(c: Vector3, bat_pct: float, _t: float) -> void:
	var r_base: float = 0.042
	var col_bat: Color = Color(0.25, 0.95, 0.45, 0.9)
	if bat_pct < 20.0:
		col_bat = Color(1.0, 0.25, 0.25, 0.95)
	elif bat_pct < 50.0:
		col_bat = Color(1.0, 0.75, 0.2, 0.95)
		
	# Hexagonal crystal cell casing
	for i in range(6):
		var a1: float = (float(i) / 6.0) * TAU - PI * 0.5
		var a2: float = (float(i + 1) / 6.0) * TAU - PI * 0.5
		var p1 := c + Vector3(cos(a1) * r_base, sin(a1) * r_base, 0.0)
		var p2 := c + Vector3(cos(a2) * r_base, sin(a2) * r_base, 0.0)
		_add_line(p1, p2, col_bat * Color(1.0, 1.0, 1.0, 0.5))
		
	# Internal battery charge level rungs
	var fill_ratio: float = clamp(bat_pct / 100.0, 0.0, 1.0)
	var total_rungs: int = 5
	var active_rungs: int = int(round(fill_ratio * float(total_rungs)))
	for r in range(total_rungs):
		var y_off: float = -0.03 + (float(r) / float(total_rungs - 1)) * 0.06
		var half_w: float = 0.024
		var rung_col := col_bat if r < active_rungs else col_bat * Color(1.0, 1.0, 1.0, 0.15)
		_add_line(c + Vector3(-half_w, y_off, 0.0), c + Vector3(half_w, y_off, 0.0), rung_col)

func _render_node_gravity(c: Vector3, grav_vec: Vector3, _t: float, _strain: float) -> void:
	var r_base: float = 0.042
	var col_gimbal := Color(0.3, 0.95, 0.5, 0.9)
	_add_circle(c, r_base, 16, col_gimbal * Color(1.0, 1.0, 1.0, 0.4))
	
	# Crosshairs
	_add_line(c - Vector3(0.04, 0.0, 0.0), c + Vector3(0.04, 0.0, 0.0), col_gimbal * Color(1.0, 1.0, 1.0, 0.25))
	_add_line(c - Vector3(0.0, 0.04, 0.0), c + Vector3(0.0, 0.04, 0.0), col_gimbal * Color(1.0, 1.0, 1.0, 0.25))
	
	# Suspended plumb-bob displaced by real tilt
	var dx: float = clamp(grav_vec.x / 9.8, -1.0, 1.0) * 0.03
	var dy: float = clamp(grav_vec.y / 9.8, -1.0, 1.0) * 0.03
	var p_bob := c + Vector3(dx, dy, 0.0)
	# Tension string
	_add_line(c, p_bob, col_gimbal * Color(1.0, 1.0, 1.0, 0.6))
	# Plumb bob weight
	_add_circle(p_bob, 0.012, 8, col_gimbal)

func _render_node_compass(c: Vector3, head_deg: float, _t: float, _strain: float) -> void:
	var r_base: float = 0.042
	var col_mag := Color(0.1, 0.95, 0.85, 0.9)
	_add_circle(c, r_base, 16, col_mag * Color(1.0, 1.0, 1.0, 0.4))
	
	# 4-Pointed Lodestone Star
	var star_r: float = 0.035
	var p_n := c + Vector3(0.0, star_r, 0.0)
	var p_s := c - Vector3(0.0, star_r, 0.0)
	var p_e := c + Vector3(star_r, 0.0, 0.0)
	var p_w := c - Vector3(star_r, 0.0, 0.0)
	_add_line(p_n, p_s, col_mag * Color(1.0, 1.0, 1.0, 0.3))
	_add_line(p_e, p_w, col_mag * Color(1.0, 1.0, 1.0, 0.3))
	
	# Dynamic Needle pointing to live magnetic heading
	var rad: float = deg_to_rad(head_deg - 90.0)
	var tip := c + Vector3(cos(rad) * 0.04, sin(rad) * 0.04, 0.0)
	_add_line(c, tip, Color(1.0, 0.3, 0.3, 0.95)) # Red needle pointing North
	_add_line(c, c - Vector3(cos(rad) * 0.025, sin(rad) * 0.025, 0.0), col_mag)