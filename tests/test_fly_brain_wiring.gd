extends MainLoop

## ONE FLY BRAIN, STEPPED ONCE, READ BY EVERYONE.
##
## Proves the wiring rather than the neuroscience: that feeding the Character a
## sensory sample moves the one central complex the glass reads, that a startle
## reaches the neuromodulators, that every key of state() is really there, and
## that the glass no longer names a member that does not exist.

const CharacterScript := preload("res://scripts/brain/character.gd")

const STATE_KEYS: Array[String] = [
	"heading_rad", "dominant_trigram", "target_alignment", "coherence",
	"startle", "curl", "is_startled", "pdf", "phase", "solar_hour",
	"habit_bias", "kc_active", "kc_count",
]

## The old bad names hud3.gd used to reach for on subsystems that never had them.
const BANNED_MEMBERS: Array[String] = [
	"simulated_hour", "get_phase_name", "get_active_kc_indices",
	"predict_habit_hexagram", "in_escape_mode",
]

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
	print("HEXY_TEST: Running Fly Brain Wiring Suite...")
	_test_heading_integrates()
	_test_startle_reaches_the_needs()
	_test_circadian_phase()
	_test_state_is_complete()
	_test_glass_names_nothing_that_does_not_exist()

	print("\n=== FLY BRAIN WIRING RESULTS ===")
	print("Passed: %d, Failed: %d" % [passes, failures])
	if failures == 0:
		print("=== ALL PASS === (One Brain, One Step, One Reader)")
	return true


func _senses() -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(16)
	v.fill(0.5)
	return v


func _test_heading_integrates() -> void:
	print("\n• Testing that feed_senses turns the one central complex...")
	var ch: RefCounted = CharacterScript.new()
	check(ch.fly_brain != null, "Character owns exactly one FlyBrain")
	check(ch.mushroom_body != null, "mushroom_body accessor sees the brain's mushroom body")
	check(ch.giant_fiber != null, "giant_fiber accessor sees the brain's giant fiber")
	check(ch.circadian_clock != null, "circadian_clock accessor sees the brain's clock")

	var start_h: float = float(ch.get_fly_state()["heading_rad"])
	var travelled := 0.0
	var prev := start_h
	for i in range(300):
		ch.feed_senses({
			"accel": Vector3(0.0, -9.8, 0.0),
			"gyro_yaw_rate": 1.0,
			"senses": _senses(),
		}, 1.0 / 60.0)
		var now_h: float = float(ch.get_fly_state()["heading_rad"])
		travelled += absf(fposmod(now_h - prev + PI, TAU) - PI)
		prev = now_h
	check(travelled > 0.5, "300 samples of 1.0 rad/s yaw moved the heading (%.3f rad travelled)" % travelled)
	check(int(ch.get_fly_state()["kc_count"]) == 16, "Mushroom body projected the 16 senses into 16 Kenyon cells")


func _test_startle_reaches_the_needs() -> void:
	print("\n• Testing that a freefall sample startles the brain and the needs...")
	var ch: RefCounted = CharacterScript.new()
	var before_oa: float = ch.get_fullness(ch.LINE_BREATH)
	ch.feed_senses({"accel": Vector3.ZERO}, 1.0 / 60.0)
	var st: Dictionary = ch.get_fly_state()
	check(is_equal_approx(float(st["startle"]), 1.0), "Freefall drives startle to 1.0 (got %.2f)" % float(st["startle"]))
	check(bool(st["is_startled"]), "Brain reports is_startled after freefall")
	check(is_equal_approx(float(st["curl"]), 1.0), "Curl factor follows the startle")
	var after_oa: float = ch.get_fullness(ch.LINE_BREATH)
	check(after_oa > before_oa, "Octopamine (BREATH) rose on startle (%.3f -> %.3f)" % [before_oa, after_oa])
	check(float(st["octopamine"]) > before_oa, "get_fly_state carries the raised octopamine too")


func _test_circadian_phase() -> void:
	print("\n• Testing that the solar hour reaches the clock...")
	var ch: RefCounted = CharacterScript.new()
	ch.feed_senses({"solar_hour": 6.5, "senses": _senses()}, 1.0 / 60.0)
	var st: Dictionary = ch.get_fly_state()
	check(is_equal_approx(float(st["solar_hour"]), 6.5), "solar_hour 6.5 reached the clock (got %.2f)" % float(st["solar_hour"]))
	var phase: String = String(st["phase"])
	check(phase.contains("Dawn") or phase.contains("Morning"),
		"06:30 reads as a dawn/morning phase (got '%s')" % phase)
	check(float(st["pdf"]) > 0.5, "PDF is elevated at the morning peak (got %.2f)" % float(st["pdf"]))


func _test_state_is_complete() -> void:
	print("\n• Testing that every state() key is present and non-null...")
	var ch: RefCounted = CharacterScript.new()
	ch.feed_senses({"senses": _senses()}, 1.0 / 60.0)
	var st: Dictionary = ch.get_fly_state()
	for key in STATE_KEYS:
		check(st.has(key) and st[key] != null, "state() carries a non-null '%s'" % key)
	check((st["habit_bias"] as Array).size() == 6, "habit_bias is a 6-element vector")
	check(String(st["dominant_trigram"]).length() > 0, "dominant_trigram is a readable name")


func _test_glass_names_nothing_that_does_not_exist() -> void:
	print("\n• Testing that the glass names no member that was never there...")
	var f := FileAccess.open("res://scripts/glass/hud3.gd", FileAccess.READ)
	check(f != null, "scripts/glass/hud3.gd is readable")
	if f == null:
		return
	var text: String = f.get_as_text()
	for banned in BANNED_MEMBERS:
		check(not text.contains(banned), "hud3.gd no longer reaches for '%s'" % banned)
