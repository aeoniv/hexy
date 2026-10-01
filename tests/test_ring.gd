extends SceneTree

const Senses = preload("res://scripts/logic/senses/senses.gd")
const Brain = preload("res://scripts/logic/brain/brain.gd")
const Q6 = preload("res://scripts/logic/q6/q6.gd")
const Voice = preload("res://scripts/logic/voice/voice.gd")
const MeshLogic = preload("res://scripts/logic/mesh/mesh.gd")
const Journal = preload("res://scripts/logic/journal/journal.gd")

var failed: bool = false

func _initialize() -> void:
	var now_ms: int = Time.get_ticks_msec()
	var sample: Dictionary = Senses.new().sample(now_ms)
	check(sample.clock.time_ms == now_ms and sample.clock.source == "system_clock", "one tick has a clock sense")
	check(sample.signals.size() == 6 and sample.signals.all(func(v): return v == null), "missing add-ons stay absent")
	var state: Dictionary = Brain.new().step(sample)
	check(state.time_ms == now_ms and state.X == null, "brain receives tick without inventing needs")
	var q6 = Q6.new()
	check(q6.vertex(0) == {"lines": 0, "dimension": 6} and q6.vertex(64).is_empty(), "Q6 has bounded vertices")
	var judgement: Dictionary = q6.judge(sample.human, state.X)
	check(judgement.d == null, "distance is absent without H and X")
	var spoken: Dictionary = Voice.new().speak(judgement)
	check(not spoken.available and spoken.card == null and spoken.line == Voice.NO_VOICE, "fixed no-voice line")
	var sharing: Dictionary = MeshLogic.new().share(judgement)
	check(not sharing.available and not sharing.sent and sharing.peers == null, "mesh reports absent")
	var receipt: Dictionary = Journal.new().remember(sample, judgement, spoken, sharing)
	check(receipt.kind == "tick" and receipt.time_ms == now_ms and not receipt.minted, "clock receipt does not mint an act")
	quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failed = true
