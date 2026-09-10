extends SceneTree
## Smoke test for MnnRuntime with I-Ching semantic queries.

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")

var _fails := 0
var _checks := 0

func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", what)
	else:
		_fails += 1
		printerr("FAIL ", what)

func _initialize() -> void:
	var m := MnnRuntime.new()
	_check(m.backend_name() == "mock" or m.available(), "backend reports status")
	var dim := m.embed_start()
	_check(dim > 0, "embed_start reports dimension")
	var a := m.embed("I-Ching Hexagram 1 Creative")
	var a2 := m.embed("I-Ching Hexagram 1 Creative")
	var b := m.embed("I-Ching Hexagram 2 Receptive")
	_check(a.size() == dim, "embedding matches dimension")
	_check(a == a2, "deterministic embedding for same text")
	_check(absf(MnnRuntime.cosine(a, a) - 1.0) < 0.001, "self-cosine unit length")
	_check(MnnRuntime.cosine(a, b) < 0.99, "different hexagrams produce distinct vectors")
	_check(m.chat_start(), "chat starts successfully")
	var reply := m.chat("Counsel on Hexagram 1")
	_check(reply.length() > 0, "chat returns non-empty response")
	print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)
