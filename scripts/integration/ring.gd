extends RefCounted
## One tick through the six techs: senses -> brain -> q6 -> voice -> mesh -> journal.

const Senses = preload("res://scripts/logic/senses/senses.gd")
const Brain = preload("res://scripts/logic/brain/brain.gd")
const Q6 = preload("res://scripts/logic/q6/q6.gd")
const Voice = preload("res://scripts/logic/voice/voice.gd")
const MeshLogic = preload("res://scripts/logic/mesh/mesh.gd")
const Journal = preload("res://scripts/logic/journal/journal.gd")

var senses = Senses.new()
var brain = Brain.new()
var q6 = Q6.new()
var voice = Voice.new()
var mesh = MeshLogic.new()
var journal = Journal.new()

func tick(now_ms: int) -> Dictionary:
	var sample: Dictionary = senses.sample(now_ms)
	var state: Dictionary = brain.step(sample)
	var judgement: Dictionary = q6.judge(sample.human, state.X)
	var spoken: Dictionary = voice.speak(judgement)
	var sharing: Dictionary = mesh.share(judgement)
	var receipt: Dictionary = journal.remember(sample, judgement, spoken, sharing)
	return {"time_ms": now_ms, "X": judgement.X, "H": judgement.H, "d": judgement.d,
		"line": spoken.line, "receipt": receipt}
