extends Control
## Page 01: ticks the ring once per second and draws X, H, d and the voice line.

const Ring = preload("res://scripts/integration/ring.gd")

var ring = Ring.new()
var last: Dictionary = {}

@onready var label: Label = $Readout

func _ready() -> void:
	step()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(step)
	add_child(timer)

func step() -> void:
	last = ring.tick(Time.get_ticks_msec())
	label.text = "01\nX: %s\nH: %s\nd: %s\n%s" % [fmt(last.X), fmt(last.H), fmt(last.d), last.line]
	print(label.text.replace("\n", " | "))

func fmt(v: Variant) -> String:
	return "absent" if v == null else str(v)
