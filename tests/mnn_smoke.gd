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

	# --- the desktop fallbacks the ixmnn/2 surface brought down ---------------

	_check(MnnRuntime.REQUIRES == "ixmnn/2", "seam requires ixmnn/2")

	# SAMPLING ROUNDTRIP. The clamps are the seam's, not the plugin's, so the
	# mock and the phone agree about what a legal temperature is.
	_check(m.set_sampling(0.42, 0.8, 1.05), "set_sampling accepted")
	var s := m.get_sampling()
	_check(absf(float(s["temperature"]) - 0.42) < 0.0001, "temperature roundtrips")
	_check(absf(float(s["top_p"]) - 0.8) < 0.0001, "top_p roundtrips")
	_check(absf(float(s["repetition_penalty"]) - 1.05) < 0.0001, "penalty roundtrips")
	m.set_sampling(9.0, 9.0, 9.0)
	var clamped := m.get_sampling()
	_check(float(clamped["temperature"]) <= 2.0, "temperature is clamped")
	_check(float(clamped["top_p"]) <= 1.0, "top_p is clamped")
	_check(float(clamped["repetition_penalty"]) <= 2.0, "penalty is clamped")
	var owned := m.get_sampling()
	owned["temperature"] = -1.0
	_check(float(m.get_sampling()["temperature"]) > 0.0, "a caller cannot poke the knobs")

	# TOKENIZE / DETOKENIZE on the mock: stable ids, and a round trip.
	var ids := m.tokenize("the breath is slow")
	_check(ids.size() == 4, "mock tokenizer splits on spaces, got %d" % ids.size())
	_check(m.tokenize("the breath is slow") == ids, "same text, same ids")
	_check(m.detokenize(ids[0]).strip_edges() == "the", "detokenize round-trips a known id")
	_check(m.detokenize(999999).begins_with("[tok_"), "an unknown id says so")
	_check(m.tokenize("").is_empty(), "empty text is no tokens")

	# PARTITION_THINK, pure and static: the three shapes a model actually emits.
	var whole := MnnRuntime.partition_think("<think>weighing it</think>Yield.")
	_check(String(whole["thought"]) == "weighing it", "thought is separated")
	_check(String(whole["speech"]) == "Yield.", "speech is what is left")
	var plain := MnnRuntime.partition_think("  Yield.  ")
	_check(String(plain["thought"]) == "", "no tags, no thought")
	_check(String(plain["speech"]) == "Yield.", "no tags, speech is the whole")
	var unclosed := MnnRuntime.partition_think("Yield.<think>still weighing")
	_check(String(unclosed["thought"]) == "still weighing", "an unclosed think is all thought")
	_check(String(unclosed["speech"]) == "Yield.", "and the speech before it survives")

	# STREAM_CHUNKS keeps the trailing space on the chunk, the shape a real
	# tokenizer produces and therefore the shape a splitter must survive.
	var chunks := MnnRuntime.stream_chunks("a b c")
	_check(chunks.size() == 3, "three chunks")
	_check(String(chunks[0]) == "a ", "the space rides with its word")
	_check("".join(PackedStringArray(chunks)) == "a b c", "chunks rejoin to the text")

	# APPLY_TEMPLATE and the context window, on the mock.
	var tmpl := m.apply_template("hello")
	_check(tmpl.contains("<|im_start|>user"), "mock template is ChatML shaped")
	_check(tmpl.ends_with("<|im_start|>assistant
"), "template ends on the assistant turn")
	_check(m.get_history_count() >= 0, "history count is a number")
	var before := m.get_history_count()
	_check(m.trim_history(0, 4), "trim_history accepted")
	_check(m.get_history_count() <= before, "trimming never grows the window")

	# PERF has the seven keys whether or not anything ever generated.
	var perf := m.get_perf()
	for k in ["prompt_len", "gen_seq_len", "all_seq_len", "prefill_ms", "decode_ms", "tps", "status"]:
		_check(perf.has(k), "perf carries %s" % k)

	_check(not m.streaming(), "nothing is streaming at rest")
	_check(m.chat_loaded() == m.chat_ready(), "chat_loaded is chat_ready")
	_check(m.embedding_name() == "mock_hash", "headless embeddings say they are a mock")
	_check(not MnnRuntime._wants_no_think("qwen3.5-0.8b-mnn"), "qwen3.5 gets no /no_think")
	_check(MnnRuntime._wants_no_think("qwen3-0.6b-mnn"), "qwen3- does")

	print("=== ALL PASS ===" if _fails == 0 else "=== FAILURES: %d ===" % _fails)
	quit(0 if _fails == 0 else 1)
