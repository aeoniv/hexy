extends SceneTree
## Smoke test for MnnRuntime with I-Ching semantic queries.

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")


## A stand-in for the IxMnn JNISingleton. It answers the handshake at ixmnn/2
## and owns a slice of the /2 surface, so the runtime's on-device branch can be
## pinned headless. Note it is NOT asked whether it `has_method` anything — that
## is the whole point of the fix this file guards.
class FakePlugin extends RefCounted:
	signal chat_token(text: String)
	signal chat_done(text: String)
	var calls: Array = []
	var version := "ixmnn/2"
	func plugin_version() -> String:
		return version
	func runtime_ready() -> bool:
		return true
	func tokenize(text: String) -> PackedInt32Array:
		calls.append("tokenize")
		var out := PackedInt32Array()
		for i in text.length():
			out.append(7000 + i)
		return out
	func detokenize(_id: int) -> String:
		calls.append("detokenize")
		return "<plug>"
	func get_perf() -> String:
		calls.append("get_perf")
		return JSON.stringify({
			"prompt_len": 11, "gen_seq_len": 4, "all_seq_len": 15,
			"prefill_us": 2000, "decode_us": 4000, "status": 0,
		})
	func set_sampling(_t: float, _p: float, _r: float) -> bool:
		calls.append("set_sampling")
		return true
	func get_history_count() -> int:
		calls.append("get_history_count")
		return 42
	func trim_history(_b: int, _e: int) -> bool:
		calls.append("trim_history")
		return true
	func apply_template(_p: String) -> String:
		calls.append("apply_template")
		return "<plugin-template>"
	func chat_start(_m: String) -> bool:
		calls.append("chat_start")
		return true
	func chat_at(_p: String, v: int) -> String:
		calls.append("chat_at:%d" % v)
		return "[plug] answered"
	func chat_stream_at(_p: String, v: int) -> bool:
		calls.append("chat_stream_at:%d" % v)
		return true

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

	# ── THE HANDSHAKE IS THE ONLY GATE ──────────────────────────────────────
	#
	# SOURCE CHECK. A JNISingleton answers `has_method` false for every method
	# it owns, so a per-call has_method fence sends the whole ixmnn/2 surface to
	# the mock on exactly the device it exists for. There must be none left.
	var src := FileAccess.get_file_as_string("res://scripts/brain/mnn_runtime.gd")
	_check(src != "", "runtime source is readable")
	for banned in ["chat_at", "chat_stream_at", "tokenize", "detokenize", "get_perf",
			"set_sampling", "get_history_count", "trim_history", "apply_template"]:
		_check(not src.contains("has_method(\"%s\")" % banned),
			"no has_method fence on %s" % banned)
	_check(not src.contains("_android.has_method("),
		"the runtime never probes the singleton with has_method")
	_check(src.contains("Seam.check(node, REQUIRES, REQUIRES_TAG)"),
		"the version handshake is still what attaches the singleton")

	# BEHAVIOUR, ON A FAKE PLUGIN THAT PASSES THE HANDSHAKE. It is never asked
	# has_method; the runtime must call straight through to it.
	var fake := FakePlugin.new()
	var live := MnnRuntime.new()
	_check(live._attach_plugin_for_test(fake), "handshake passes at ixmnn/2")
	_check(live.available(), "a handshaken plugin is available")
	_check(live.backend_name() == "mnn", "backend names the plugin")
	_check(live.tokenize("abc").size() == 3, "tokenize goes to the plugin")
	_check(live.detokenize(1) == "<plug>", "detokenize goes to the plugin")
	_check(live.apply_template("hi") == "<plugin-template>", "template goes to the plugin")
	_check(live.get_history_count() == 42, "history count goes to the plugin")
	_check(live.trim_history(0, 2), "trim goes to the plugin")
	var lperf := live.get_perf()
	_check(int(lperf["prompt_len"]) == 11, "perf is parsed from the plugin")
	_check(absf(float(lperf["decode_ms"]) - 4.0) < 0.001, "perf microseconds become ms")
	_check(absf(float(lperf["tps"]) - 1000.0) < 0.1, "perf tps is derived")
	_check(live.set_sampling(0.5), "set_sampling goes to the plugin")
	live.chat_start("qwen3-0.6b-mnn")
	_check(live.chat("ask", 9) == "[plug] answered", "chat uses the versioned call")
	_check(fake.calls.has("chat_at:9"), "the Q6 cast version reaches the plugin")
	_check(live.chat_stream("ask", 3), "chat_stream uses the versioned call")
	_check(fake.calls.has("chat_stream_at:3"), "the cast version reaches the stream")
	for want in ["tokenize", "detokenize", "get_perf", "set_sampling",
			"get_history_count", "trim_history", "apply_template"]:
		_check(fake.calls.has(want), "the plugin actually served %s" % want)

	# A STALE AAR still degrades — the handshake, not a fence, is what catches it.
	var stale := FakePlugin.new()
	stale.version = "ixmnn/1"
	var dead := MnnRuntime.new()
	_check(not dead._attach_plugin_for_test(stale), "a stale aar fails the handshake")
	_check(not dead.available(), "and is dropped rather than half-used")
	_check(dead.backend_name() == "mock", "so the seam says it is a mock")
	_check(dead.apply_template("hi").contains("<|im_start|>"), "and the mock answers")

	print("=== ALL PASS ===" if _fails == 0 else "=== FAILURES: %d ===" % _fails)
	quit(0 if _fails == 0 else 1)
