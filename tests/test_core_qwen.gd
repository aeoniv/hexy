extends SceneTree

## Headless checks for scripts/core/qwen: the prompt, the answer, the cooldown,
## and the 64 fallback lines.

const HexyStoreScript = preload("res://scripts/core/store.gd")

var failures: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST CORE QWEN (ground + ask + thought + judgements) ---")
	_test_judgements()
	_test_ground()
	await _test_ask()
	await _test_cooldown()
	if failures == 0:
		print("--- ALL CORE QWEN TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- CORE QWEN TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _test_judgements() -> void:
	check(Judgements.count() == 64, "64 judgements")
	var all_ok: bool = true
	for i in range(64):
		var line: String = Judgements.LINES[i]
		if line.strip_edges() == "":
			all_ok = false
		for c in line:
			if c.unicode_at(0) > 126 or c.unicode_at(0) < 32:
				all_ok = false
	check(all_ok, "every judgement is non-empty printable ASCII")
	check(Judgements.for_number(1).begins_with("Creative."), "figure 1 is the Creative")
	check(Judgements.for_bits(0) == Judgements.for_number(2), "bits 0 is the Receptive")


func _build() -> Array:
	var store: HexyStore = HexyStoreScript.new()
	var mnn: Mnn = Mnn.new()
	var qwen: Qwen = Qwen.new()
	root.add_child(store)
	root.add_child(mnn)
	root.add_child(qwen)
	store.set_hexagram({"bits": 63, "moving": 1})
	store.set_machine({"trigram": 7, "score": 0.8, "sentence": "the room is still"})
	store.set_human({"trigram": 0, "score": 0.4, "sentence": "the breath is slow"})
	qwen.bind(store, mnn)
	return [store, mnn, qwen]


func _test_ground() -> void:
	var parts: Array = _build()
	var store: HexyStore = parts[0]
	var qwen: Qwen = parts[2]
	var text: String = qwen.ground(IChing.describe(63, 1), "the room is still", "the breath is slow")
	check(text.contains("figure 1"), "ground names the number")
	check(text.contains(IChing.name_of(63)), "ground names the figure")
	check(text.contains(IChing.pinyin(63)), "ground carries the pinyin")
	check(text.contains("the room is still"), "ground echoes the machine sentence")
	check(text.contains("the breath is slow"), "ground echoes the human sentence")
	check(text.length() < 700, "ground stays under 700 chars, got %d" % text.length())
	check(qwen.label(63) == IChing.name_of(63), "cached label matches KingWen")
	check(qwen.label(63) == IChing.name_of(63), "cached label is stable on the second call")
	store.queue_free()
	parts[1].queue_free()
	qwen.queue_free()


func _test_ask() -> void:
	var parts: Array = _build()
	var store: HexyStore = parts[0]
	var qwen: Qwen = parts[2]
	var seen: Array[String] = ([] as Array[String])
	store.answer_changed.connect(func(a: String) -> void: seen.append(a))
	qwen.ask("What is this moment?")
	var text: String = await qwen.answer_ready
	check(text.length() > 0, "ask returns text through the mock")
	check(store.answer == text, "store.answer holds the answer")
	check(seen.size() == 1, "answer_changed fired once")
	store.queue_free()
	parts[1].queue_free()
	qwen.queue_free()


func _test_cooldown() -> void:
	var parts: Array = _build()
	var store: HexyStore = parts[0]
	var qwen: Qwen = parts[2]
	var answers: Array[String] = ([] as Array[String])
	qwen.answer_ready.connect(func(t: String) -> void: answers.append(t))
	var before: int = qwen.thoughts_fired()
	store.set_hexagram({"bits": 5, "moving": 2})
	store.set_hexagram({"bits": 9, "moving": 4})
	check(qwen.thoughts_fired() - before == 1, "two changes inside 3 s make one thought at once")
	# The cooldown thins the stream; it must not swallow the end of it.
	await create_timer(3.5).timeout
	check(qwen.thoughts_fired() - before == 2,
		"the held-back change is spoken for once the cooldown passes (got %d)"
			% (qwen.thoughts_fired() - before))
	check(answers.size() == 2, "two changes, two answers in all (got %d)" % answers.size())
	check(not answers.is_empty()
		and answers[answers.size() - 1].begins_with(Judgements.for_bits(9)),
		"the trailing answer is about the LAST figure, not the first")
	store.queue_free()
	parts[1].queue_free()
	qwen.queue_free()
