extends SceneTree

## Headless smoke test for the Drosophila (Fruit Fly) Brain biological integration in Hexy.
## Tests:
##   1. FlyConductance: 6x6 synaptic coupling matrix, reciprocal inhibition, and bounds conservation.
##   2. FlyCentralComplex: 8-wedge heading ring attractor, stimulus steering, and coherence.
##   3. Character: Neuromodulatory 6-needs kinetics, deterministic clockless tick, and feed gates.
##   4. ReadingWords: Tri-lingual biological observations across English, Portuguese, and Chinese.
##   5. Q6Lattice Integration: Full pipeline coupling Character -> FlyConductance -> Q6Lattice.
##
## Prints === ALL PASS === or exits with error code 1.

const FlyConductanceScript := preload("res://scripts/brain/fly_conductance.gd")
const FlyCentralComplexScript := preload("res://scripts/brain/fly_central_complex.gd")
const CharacterScript := preload("res://scripts/brain/character.gd")
const ReadingWordsScript := preload("res://scripts/creature/reading_words.gd")
const Q6Script := preload("res://scripts/core/iching/q6_lattice.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	print("HEXY_TEST: Starting Fruit Fly Brain Biological Smoke Test...")
	
	_test_fly_conductance()
	_test_central_complex()
	_test_character_neuromodulators()
	_test_reading_words_trilingual()
	_test_q6_lattice_pipeline()
	
	if _fails == 0:
		print("=== ALL PASS === (%d checks clean)" % _checks)
		quit(0)
	else:
		printerr("=== %d FAILS === (%d checks completed)" % [_fails, _checks])
		quit(1)


func _test_fly_conductance() -> void:
	print("  • Testing FlyConductance Synaptic Matrix...")
	var initial := PackedFloat64Array([0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
	
	# Conservation test under 1000 simulated seconds
	var current := initial
	for s in 1000:
		current = FlyConductanceScript.step_coupling(current, 1.0)
		for i in 6:
			_check(current[i] >= 0.0 and current[i] <= 1.0, "Need %d out of bounds: %f" % [i, current[i]])
	
	# Reciprocal inhibition test: High Breath (Octopamine) must depress Rest (dFB sleep homeostat)
	var active_flight := PackedFloat64Array([0.5, 0.5, 0.95, 0.5, 0.5, 0.5])
	for s in 50:
		active_flight = FlyConductanceScript.step_coupling(active_flight, 0.5)
	_check(active_flight[3] < 0.45, "High Octopamine failed to inhibit dFB sleep: rest=%f" % active_flight[3])
	
	# Bias conversion
	var bias: PackedFloat64Array = FlyConductanceScript.to_q6_bias(PackedFloat64Array([1.0, 0.0, 0.5, 0.8, 0.2, 0.5]))
	_check(is_equal_approx(float(bias[0]), 1.0), "Bias 0 should be 1.0, got %f" % bias[0])
	_check(is_equal_approx(float(bias[1]), -1.0), "Bias 1 should be -1.0, got %f" % bias[1])
	_check(is_equal_approx(float(bias[2]), 0.0), "Bias 2 should be 0.0, got %f" % bias[2])


func _test_central_complex() -> void:
	print("  • Testing FlyCentralComplex 8-Wedge Compass...")
	var cx = FlyCentralComplexScript.new()
	_check(cx.activity.size() == 8, "CX should have 8 wedges, got %d" % cx.activity.size())
	_check(cx.dominant_trigram() >= 0 and cx.dominant_trigram() < 8, "Dominant trigram in 0..7")
	
	# Steer bump towards wedge 5 (Fire / Li)
	var stimulus := [0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 0.0, 0.0]
	cx.inject_stimulus(stimulus, 1.5)
	for s in 10:
		cx.step(0.1, 0.0, 0.0)
	_check(cx.dominant_trigram() == 5, "Compass should settle on wedge 5 (Fire), got %d" % cx.dominant_trigram())
	_check(cx.coherence() > 0.3, "Coherence should be high with strong stimulus, got %f" % cx.coherence())


func _test_character_neuromodulators() -> void:
	print("  • Testing Character Neuromodulatory Kinetics...")
	var ch = CharacterScript.new()
	_check(ch.NEED_COUNT == 6, "Character has 6 needs")
	
	# Check neuromodulator metadata
	var meta0: Dictionary = ch.fly_neuromodulator(0)
	_check(meta0.get("transmitter", "").begins_with("Dopamine"), "Line 1 is Dopamine")
	var meta2: Dictionary = ch.fly_neuromodulator(2)
	_check(meta2.get("transmitter", "").begins_with("Octopamine"), "Line 3 is Octopamine")
	var meta3: Dictionary = ch.fly_neuromodulator(3)
	_check(meta3.get("transmitter", "").begins_with("GABA"), "Line 4 is GABA/5-HT dFB")
	
	# Test clockless tick advancing 2 hours
	var t0: int = 1000000
	ch.tick(t0)
	var v0: float = ch.vitality()
	ch.tick(t0 + 2 * 3600 * 1000) # +2 hours
	var v1: float = ch.vitality()
	_check(v1 < v0, "Vitality must decay over time: %f -> %f" % [v0, v1])
	
	# Test feed & attested gate for connection
	var fullness_before: float = ch.get_fullness(0)
	ch.feed(1, 0.3, "food_source", t0 + 2 * 3600 * 1000)
	_check(ch.get_fullness(0) > fullness_before, "Feeding body line increased fullness: %f -> %f" % [fullness_before, ch.get_fullness(0)])
	
	var refused_box := [false]
	ch.refused.connect(func(_why): refused_box[0] = true)
	ch.feed(6, 0.5, "unattested_self_claim", t0 + 2 * 3600 * 1000)
	_check(refused_box[0], "Unattested connection must be refused")


func _test_reading_words_trilingual() -> void:
	print("  • Testing ReadingWords Tri-Lingual Observations...")
	for lang in ["en", "pt", "zh"]:
		for line in range(1, 7):
			var obs_yang: String = ReadingWordsScript.biological_sentence(line, 0.8, lang)
			_check(obs_yang.length() > 5, "Valid Yang observation in %s for line %d: %s" % [lang, line, obs_yang])
			var obs_yin: String = ReadingWordsScript.biological_sentence(line, 0.2, lang)
			_check(obs_yin.length() > 5, "Valid Yin observation in %s for line %d: %s" % [lang, line, obs_yin])
	
	# Verify King Wen title lookups in Portuguese and Chinese
	var title_pt: String = ReadingWordsScript.name_of(1, "pt")
	_check(title_pt == "O Criador", "Hexagram 1 in PT should be 'O Criador', got '%s'" % title_pt)
	var zh_char: String = ReadingWordsScript.NAMES[1]["zh"]
	_check(zh_char == "乾", "Hexagram 1 Chinese character should be '乾', got '%s'" % zh_char)
	var title_zh: String = ReadingWordsScript.title(1, "zh")
	_check(title_zh == "1 · qián", "Hexagram 1 title in ZH should be '1 · qián', got '%s'" % title_zh)


func _test_q6_lattice_pipeline() -> void:
	print("  • Testing Character -> FlyConductance -> Q6Lattice Pipeline...")
	var ch = CharacterScript.new()
	var bias: PackedFloat64Array = ch.to_q6_bias()
	_check(bias.size() == 6, "Q6 bias vector size is 6")
	
	# Diffuse and step Q6 distribution
	var p: PackedFloat64Array = Q6Script.uniform()
	var next_p: PackedFloat64Array = Q6Script.step(p, bias, 0.1, 1.2)
	_check(next_p.size() == 64, "Q6 distribution size is 64")
	
	var best_hex: int = Q6Script.argmax(next_p)
	_check(best_hex >= 0 and best_hex < 64, "Argmax hexagram in 0..63: got %d" % best_hex)
	var tension: float = Q6Script.tension(next_p)
	_check(tension >= 0.0 and tension <= 1.0, "Tension in [0, 1]: got %f" % tension)
