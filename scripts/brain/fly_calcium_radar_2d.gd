class_name FlyCalciumRadar2D
extends Control

## DROSOPHILA CENTRAL COMPLEX (EB/PB) CIRCULAR CALCIUM RADAR
##
## Visualizes the real-time activity bump of the fruit fly's 8-wedge ellipsoid body.
## Mirroring 2-photon GCaMP calcium imaging in neuroscience labs:
##   - 8 Circular wedges mapping to the 8 Bagua trigrams.
##   - Real-time fluorescent glow proportional to wedge activity.
##   - Heading vector pointer (P-EN heading angle).
##   - 6 Neuromodulatory spectrum bars (DA, NPF, OA, dFB, CX, Fru).

const TRIGRAM_NAMES := ["坤 ☷", "艮 ☶", "坎 ☵", "巽 ☴", "震 ☳", "离 ☲", "兑 ☱", "乾 ☰"]
const NEURO_NAMES := ["DA (Body)", "NPF (Food)", "OA (Breath)", "dFB (Rest)", "CX (Focus)", "Fru (Conn)"]
const NEURO_COLORS := [
	Color(0.95, 0.75, 0.2),  # DA: Gold
	Color(0.3, 0.85, 0.4),   # NPF: Green
	Color(1.0, 0.45, 0.2),   # OA: Orange/Red
	Color(0.4, 0.6, 0.95),   # dFB: Indigo/Blue
	Color(0.2, 0.95, 0.95),  # CX: Cyan
	Color(0.95, 0.35, 0.85)  # Fru: Magenta
]

var central_complex: RefCounted = null
var character: RefCounted = null

@export var radar_radius: float = 72.0
@export var ring_thickness: float = 18.0
@export var show_neuromodulators: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(220, 260)


func _ready() -> void:
	custom_minimum_size = Vector2(220, 260)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, radar_radius + 18.0)
	var tau_slice: float = TAU / 8.0
	
	# 1. Background ring track
	draw_arc(center, radar_radius, 0.0, TAU, 48, Color(0.12, 0.16, 0.22, 0.8), ring_thickness, true)
	
	# 2. Draw 8 Calcium Activity Wedges
	var activities: Array = central_complex.activity if (central_complex and "activity" in central_complex) else [0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125]
	var current_heading: float = central_complex.current_heading if (central_complex and "current_heading" in central_complex) else 0.0
	
	for i in range(8):
		var start_angle: float = float(i) * tau_slice - (tau_slice * 0.5)
		var end_angle: float = start_angle + tau_slice * 0.92
		var act: float = float(activities[i]) if i < activities.size() else 0.125
		
		# Fluorescent GCaMP Calcium Green/Cyan glow
		var glow_alpha: float = clampf(act * 2.5, 0.15, 1.0)
		var glow_color := Color(0.1, 0.95, 0.7, glow_alpha)
		if act > 0.22:
			glow_color = Color(0.4, 1.0, 0.85, glow_alpha) # Peak excitation
			
		draw_arc(center, radar_radius, start_angle, end_angle, 12, glow_color, ring_thickness * clampf(act * 2.2, 0.7, 1.3), true)
		
		# Trigram label on perimeter
		var label_angle: float = float(i) * tau_slice
		var label_pos: Vector2 = center + Vector2(cos(label_angle), sin(label_angle)) * (radar_radius + ring_thickness * 0.5 + 14.0)
		draw_string(ThemeDB.fallback_font, label_pos + Vector2(-12, 5), TRIGRAM_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.75, 0.82, 0.9, glow_alpha))
	
	# 3. Inner Heading Cursor Needle
	var needle_dir := Vector2(cos(current_heading), sin(current_heading))
	var needle_end := center + needle_dir * (radar_radius - ring_thickness * 0.6)
	draw_line(center, needle_end, Color(1.0, 0.95, 0.3, 0.95), 2.5, true)
	draw_circle(center, 4.0, Color(1.0, 0.95, 0.3, 0.95))
	
	# 4. Neuromodulator Spectrum Gauges
	if show_neuromodulators and character != null and "_fullness" in character:
		var bar_y := center.y + radar_radius + 36.0
		var bar_w := size.x * 0.8
		var bar_x := (size.x - bar_w) * 0.5
		var bar_h := 7.0
		var spacing := 14.0
		
		var fullness_arr: Array = character._fullness
		for n in range(mini(6, fullness_arr.size())):
			var y: float = bar_y + float(n) * spacing
			var val: float = clampf(float(fullness_arr[n]), 0.0, 1.0)
			
			# Label
			draw_string(ThemeDB.fallback_font, Vector2(bar_x, y - 2), NEURO_NAMES[n], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.72, 0.8))
			# Value text
			draw_string(ThemeDB.fallback_font, Vector2(bar_x + bar_w - 28, y - 2), "%d%%" % int(val * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(0.85, 0.9, 0.95))
			
			# Bar track
			draw_rect(Rect2(bar_x, y, bar_w, bar_h), Color(0.12, 0.15, 0.20, 0.9), true)
			# Fill
			var fill_color: Color = NEURO_COLORS[n]
			if val < 0.5:
				fill_color = fill_color.lerp(Color(0.4, 0.4, 0.4), 0.5)
			draw_rect(Rect2(bar_x, y, bar_w * val, bar_h), fill_color, true)
