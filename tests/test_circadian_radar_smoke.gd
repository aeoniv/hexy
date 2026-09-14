extends MainLoop

const FlyCircadianClockScript := preload("res://scripts/brain/fly_circadian_clock.gd")
const FlyCalciumRadar2DScript := preload("res://scripts/brain/fly_calcium_radar_2d.gd")
const FlyCentralComplexScript := preload("res://scripts/brain/fly_central_complex.gd")
const CharacterScript := preload("res://scripts/brain/character.gd")

var passes := 0
var failures := 0


func check(condition: bool, msg: String) -> void:
	if condition:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		failures += 1
		printerr("  FAIL: %s" % msg)


func _process(_delta: float) -> bool:
	print("HEXY_TEST: Running Circadian Clock & Calcium Radar Smoke Tests...")
	_test_circadian_clock()
	_test_calcium_radar_component()
	
	print("\n=== CIRCADIAN & RADAR RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (Circadian & Radar Verified)")
	return true


func _test_circadian_clock() -> void:
	print("\n• Testing FlyCircadianClock (s-LNv & l-LNv Pacemakers + PDF)...")
	var clock: RefCounted = FlyCircadianClockScript.new()
	
	# Test 1: Dawn Morning Peak (~07:00 AM)
	clock.update(7.0)
	var dawn_mods: Dictionary = clock.get_circadian_modifiers()
	check(dawn_mods["morning_drive"] > 0.85, "Morning drive surges at dawn (got %.3f > 0.85)" % dawn_mods["morning_drive"])
	check(dawn_mods["pdf_level"] > 0.65, "PDF neuropeptide peaks at dawn (got %.3f > 0.65)" % dawn_mods["pdf_level"])
	check(dawn_mods["da_boost"] > 0.20, "Dopamine motor vigor is boosted at dawn")
	check(dawn_mods["phase_name"].contains("Morning"), "Phase name identifies Morning Dawn")
	
	# Test 2: Night Torpor (~02:00 AM)
	clock.update(2.0)
	var night_mods: Dictionary = clock.get_circadian_modifiers()
	check(night_mods["pdf_level"] < 0.15, "PDF drops to trough during night torpor (got %.3f < 0.15)" % night_mods["pdf_level"])
	check(night_mods["dfb_permissiveness"] > 0.85, "dFB sleep permissiveness unlocks at night (got %.3f > 0.85)" % night_mods["dfb_permissiveness"])
	check(night_mods["phase_name"].contains("Night"), "Phase name identifies Night Torpor")
	
	# Test 3: Evening Twilight (~18:30 PM)
	clock.update(18.5)
	var eve_mods: Dictionary = clock.get_circadian_modifiers()
	check(eve_mods["evening_drive"] > 0.85, "Evening drive peaks at dusk (got %.3f > 0.85)" % eve_mods["evening_drive"])
	check(eve_mods["phase_name"].contains("Evening"), "Phase name identifies Evening Twilight")


func _test_calcium_radar_component() -> void:
	print("\n• Testing FlyCalciumRadar2D Visual Component Lifecycle...")
	var radar: Control = FlyCalciumRadar2DScript.new()
	var cx: RefCounted = FlyCentralComplexScript.new()
	var ch: RefCounted = CharacterScript.new()
	
	radar.central_complex = cx
	radar.character = ch
	radar.size = Vector2(240, 280)
	
	check(radar.TRIGRAM_NAMES.size() == 8, "Calcium radar has 8 Bagua trigrams")
	check(radar.NEURO_NAMES.size() == 6, "Calcium radar has 6 neuromodulator meters")
	check(radar.custom_minimum_size.x >= 220, "Custom minimum size is >= 220 px")
	
	radar.free()
