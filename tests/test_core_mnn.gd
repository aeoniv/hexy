extends SceneTree

## Headless checks for scripts/core/mnn: the figure vector, the tiny predictor,
## and the promise that generate() always speaks.

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST CORE MNN (q6_embed + figure_net + mnn) ---")
	_test_q6_embed()
	_test_figure_net()
	await _test_mnn()
	if failures == 0:
		print("--- ALL CORE MNN TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CORE MNN TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _test_q6_embed() -> void:
	var v: PackedFloat32Array = Q6Embed.vec(0b101010)
	check(v.size() == 32, "vec is 32 wide")
	check(v[0] == -1.0 and v[1] == 1.0, "line bits map to -1 / +1")
	check(v[6 + 2] == 1.0, "lower trigram one-hot")
	check(v[14 + 5] == 1.0, "upper trigram one-hot")
	check(absf(v[25] - 0.5) < 0.0001, "popcount / 6")

	var all_near_closer: bool = true
	for bits in range(64):
		var far: float = Q6Embed.dist(bits, Q6.flip_all(bits))
		for n in Q6.neighbors(bits):
			if Q6Embed.dist(bits, n) >= far:
				all_near_closer = false
	check(all_near_closer, "each figure sits closer to its neighbours than to its antipode")

	var fused: PackedFloat32Array = Q6Embed.fuse(Q6Embed.vec(63), Q6Embed.vec(0))
	var sum_sq: float = 0.0
	for x in fused:
		sum_sq += x * x
	check(fused.size() == 64, "fuse concatenates")
	check(absf(sum_sq - 1.0) < 0.0001, "fuse is L2 normalised")


func _test_figure_net() -> void:
	var net: FigureNet = FigureNet.new()
	var walk: Array[int] = [0, 1, 3, 7]
	for round_i in range(5):
		for b in walk:
			net.push(b, [0.0, 0, 0, 0, 0, 0, 0, 0], [0.0, 0, 0, 0, 0, 0, 0, 0])
	var p: Dictionary = net.predict(0)
	check(int(p["bits"]) == 1, "walk 0->1->3->7 predicts 1 from 0")
	check(int(p["moving"]) == 1, "moving line is the first")
	check(float(p["confidence"]) > 0.5, "confidence over half, got %f" % float(p["confidence"]))

	var path: String = "user://test_figure_net.json"
	check(net.save(path), "save writes json")
	var back: FigureNet = FigureNet.new()
	check(back.load_file(path), "load_file reads json")
	check(back.samples() == net.samples(), "ring round trips")
	var q: Dictionary = back.predict(0)
	check(int(q["bits"]) == int(p["bits"]), "prediction survives the round trip")
	check(absf(float(q["confidence"]) - float(p["confidence"])) < 0.0001, "confidence survives")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_mnn() -> void:
	var m: Mnn = Mnn.new()
	root.add_child(m)
	await process_frame
	check(not m.available(), "headless has no IxMnn, so available() is false")
	check(m.backend_name() == "mock", "backend falls back to mock")
	var t: Array[Dictionary] = m.tiers()
	check(t.size() == 4, "four tiers")
	check(String(t[0]["id"]) == "floor" and String(t[0]["params"]) == "0.6B", "floor is 0.6B")
	check(String(t[3]["id"]) == "embed" and String(t[3]["params"]) == "gte", "embed lane is gte")
	check(not m.load_tier("floor"), "load_tier reports no weights in headless")

	var prompt: String = "figure 1 Creative; machine: the room is still; human: the breath is slow"
	m.generate(prompt, 40)
	var text: String = await m.done
	check(text.length() > 0, "generate still returns text through MockLlm")
	check(text.begins_with("Creative."), "mock speaks the judgement of the figure asked for")
	check(text.contains("the breath is slow"), "mock echoes the human sentence")
	m.queue_free()
