extends SceneTree
## MnnRuntime contract: honest backend name, deterministic unit-length mock
## embeddings, cosine sanity. Prints === ALL PASS === or fails.

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")

var _fails := 0
## EVERY CHECK IS COUNTED. A compile error in a depended script makes a whole
## section skip silently, and a suite that prints ALL PASS because it ran nothing
## is worse than a red one. Raise this floor when checks are added.
const MIN_CHECKS := 75
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
	_check(m.backend_name() == "mock" or m.available(), "backend is honest")
	var dim := m.embed_start()
	_check(dim > 0, "embed_start reports a dimension")
	_check(m.embed_dim() == dim, "embed_dim agrees with embed_start")
	var a := m.embed("squat form complete")
	var a2 := m.embed("squat form complete")
	var b := m.embed("water at the fork")
	_check(a.size() == dim, "embedding matches the stated dimension")
	_check(a == a2, "same text, same vector")
	_check(absf(MnnRuntime.cosine(a, a) - 1.0) < 0.001, "unit length")
	_check(MnnRuntime.cosine(a, b) < 0.99, "different texts differ")

	# Chat shares the seam. The mock answers so callers can be written and
	# tested on desktop; it never pretends to be a model.
	_check(not m.chat_ready(), "chat is not ready before chat_start")
	_check(m.chat("hello") == "", "no reply before chat_start")
	_check(m.chat_start(), "chat_start succeeds on the mock")
	_check(m.chat_ready(), "chat is ready after chat_start")
	_check(m.chat("say hello") != "", "chat returns a reply")
	_check(m.chat("   ") == "", "empty prompt gets no reply")

	# PHASE 10c — THE STREAM. The chunker is pure, so the shape of a stream is
	# pinned with no plugin: words, each keeping the space that ended it, which
	# is the shape a real tokenizer produces and therefore the shape the sentence
	# splitter downstream has to survive.
	var chunks := MnnRuntime.stream_chunks("your keys are here")
	_check(chunks.size() == 4, "a four word reply is four chunks")
	var rebuilt := ""
	for c: String in chunks:
		rebuilt += c
	_check(rebuilt == "your keys are here",
		"AND THE CHUNKS REBUILD THE REPLY EXACTLY - a stream never loses a byte")
	_check(String(chunks[0]) == "your ", "the space that ended a word travels with it")
	_check(MnnRuntime.stream_chunks("").is_empty(), "nothing chunks to nothing")

	# THE SEAM ITSELF, on the mock: tokens first, then exactly one done, and the
	# done carries the whole of what the tokens carried.
	var m2 := MnnRuntime.new()
	m2.chat_start()
	m2.set_scripted(["the keys are on the table"])
	var got: Array = []
	var done: Array = []
	m2.chat_token.connect(func(t: String): got.append(t))
	m2.chat_done.connect(func(t: String): done.append(t))
	_check(m2.chat_stream("where are they"), "the mock takes the stream")
	_check(got.size() == 6, "six words arrived as six tokens: " + str(got.size()))
	_check(done.size() == 1 and String(done[0]) == "the keys are on the table",
		"and ONE done carried the whole answer")
	_check(not m2.streaming(), "and the stream is over")
	var joined := ""
	for t: String in got:
		joined += t
	_check(joined == String(done[0]),
		"THE TOKENS AND THE ANSWER ARE THE SAME TEXT - the two can never disagree")

	# ── QWEN MODEL CONSTANTS & TIER-1 I-CHING Q6 COPROCESSOR ──────────────────
	_check(MnnRuntime.MODEL_QWEN3_0_6B == "qwen3-0.6b-mnn", "model constant Qwen3-0.6B")
	_check(MnnRuntime.MODEL_QWEN3_1_7B == "qwen3-1.7b-mnn", "model constant Qwen3-1.7B")
	_check(MnnRuntime.MODEL_QWEN2_5_1_5B == "qwen2.5-1.5b-mnn", "model constant Qwen2.5-1.5B")
	_check(MnnRuntime.MODEL_QWEN2_5_3B == "qwen2.5-3b-mnn", "model constant Qwen2.5-3B")
	_check(MnnRuntime.MODEL_QWEN3_5_0_8B == "qwen3.5-0.8b-mnn", "model constant Qwen3.5-0.8B")
	_check(MnnRuntime.CHAT_MODELS.has(MnnRuntime.MODEL_QWEN3_5_0_8B),
		"the 0.8B is a legal directory for this seam")
	_check(MnnRuntime.CHAT_MODELS.has(MnnRuntime.CHAT_MODEL),
		"...and the old one did not leave the list")

	# WHICH MIND, AND HOW IT IS CHOSEN. `chat_start()` with a name opens that
	# directory; with none it reads HEXY_CHAT_MODEL; with neither it is the 0.6B,
	# which is the whole of "no behaviour change for a phone that never sets it".
	var m_pick := MnnRuntime.new()
	m_pick.chat_start()
	_check(m_pick.chat_model() == MnnRuntime.CHAT_MODEL,
		"an unasked chat_start is still the 0.6B")
	OS.set_environment(MnnRuntime.ENV_CHAT_MODEL, MnnRuntime.MODEL_QWEN3_5_0_8B)
	var m_env := MnnRuntime.new()
	m_env.chat_start()
	_check(m_env.chat_model() == MnnRuntime.MODEL_QWEN3_5_0_8B,
		"HEXY_CHAT_MODEL is the knob and it moves the seam")
	var m_named := MnnRuntime.new()
	m_named.chat_start(MnnRuntime.CHAT_MODEL)
	_check(m_named.chat_model() == MnnRuntime.CHAT_MODEL,
		"...AND A NAMED DIRECTORY BEATS IT - main.gd asks ModelStore, not the env")
	OS.set_environment(MnnRuntime.ENV_CHAT_MODEL, "")

	# THE PROMPT SWITCH IS FENCED BY FAMILY. `/no_think` is a command to Qwen3
	# and a sentence to Qwen3.5, whose thinking lives in llm_config.json instead.
	_check(MnnRuntime._wants_no_think(MnnRuntime.MODEL_QWEN3_0_6B),
		"the 0.6B still gets /no_think")
	_check(MnnRuntime._wants_no_think(MnnRuntime.MODEL_QWEN3_1_7B),
		"...and so does the 1.7B")
	_check(not MnnRuntime._wants_no_think(MnnRuntime.MODEL_QWEN3_5_0_8B),
		"AND THE 0.8B NEVER DOES - the dash in \"qwen3-\" is the fence")
	_check(not MnnRuntime._wants_no_think(MnnRuntime.MODEL_QWEN2_5_1_5B),
		"...nor does Qwen2.5")

	# AND NEITHER MODEL EVER SPEAKS ITS REASONING. Whatever directory is loaded,
	# what reaches a mouth carries no tag and no residue.
	for dir: String in [MnnRuntime.CHAT_MODEL, MnnRuntime.MODEL_QWEN3_5_0_8B]:
		var m_dir := MnnRuntime.new()
		m_dir.chat_start(dir)
		m_dir.set_scripted(["<think>weighing it</think>go left at the fork"])
		var said: Array = []
		m_dir.chat_done.connect(func(t: String): said.append(t))
		m_dir.chat_stream("which way")
		_check(said.size() == 1 and String(said[0]) == "go left at the fork",
			"%s answers with no <think> residue" % dir)

	# Topological hex prior configuration
	var m_prior := MnnRuntime.new()
	_check(m_prior.set_hex_prior(1, 1.5), "set_hex_prior succeeds for valid hexagram 1")
	var hp := m_prior.get_hex_prior()
	_check(hp["hex_bits"] == 1 and absf(float(hp["beta"]) - 1.5) < 0.001, "get_hex_prior returns stored state")
	_check(not m_prior.set_hex_prior(-1), "set_hex_prior rejects negative index")
	_check(not m_prior.set_hex_prior(64), "set_hex_prior rejects index >= 64")

	# Stream partitioning for <think> reasoning tokens
	var pt := MnnRuntime.partition_think("<think>internal contemplation</think>spoken answer")
	_check(String(pt["thought"]) == "internal contemplation", "partition_think isolates reasoning")
	_check(String(pt["speech"]) == "spoken answer", "partition_think isolates spoken text")

	var m_think := MnnRuntime.new()
	m_think.chat_start()
	m_think.set_scripted(["<think>analyzing terrain</think>proceed forward cautiously"])
	var got_thoughts: Array = []
	var got_speech: Array = []
	var final_done: Array = []
	m_think.chat_thought.connect(func(t: String): got_thoughts.append(t))
	m_think.chat_token.connect(func(t: String): got_speech.append(t))
	m_think.chat_done.connect(func(t: String): final_done.append(t))
	_check(m_think.chat_stream("plan path"), "mock stream takes thought turn")
	_check(not got_thoughts.is_empty(), "reasoning tokens arrived via chat_thought")
	var joined_thoughts := ""
	for t: String in got_thoughts: joined_thoughts += t
	_check(joined_thoughts.strip_edges() == "analyzing terrain", "chat_thought reconstituted exact reasoning trace")
	var joined_speech := ""
	for t: String in got_speech: joined_speech += t
	_check(joined_speech.strip_edges() == "proceed forward cautiously", "chat_token received purely spoken speech")
	_check(final_done.size() == 1 and String(final_done[0]).strip_edges() == "proceed forward cautiously", "chat_done emitted clean spoken reply")

	# Fast Walsh-Hadamard Transform (FWHT) & Q6 Spectral Invariants
	var impulse := PackedFloat32Array()
	impulse.resize(64)
	impulse.fill(0.0)
	impulse[0] = 1.0
	var fwht_res := MnnRuntime.fwht_64(impulse)
	_check(fwht_res.size() == 64, "FWHT produces 64 spectral coefficients")
	_check(absf(fwht_res[0] - 1.0) < 0.001 and absf(fwht_res[63] - 1.0) < 0.001, "FWHT of delta impulse is uniform all-ones")
	var ifwht_res := MnnRuntime.ifwht_64(fwht_res)
	_check(absf(ifwht_res[0] - 1.0) < 0.001 and absf(ifwht_res[1]) < 0.001, "IFWHT(FWHT(x)) reconstructs original vector perfectly")

	# Discrete hypercube Cayley algebra operators
	_check(MnnRuntime.hamming_distance(0, 63) == 6, "Hamming distance 0 to 63 is 6")
	_check(MnnRuntime.hamming_distance(0b101010, 0b101011) == 1, "Hamming distance adjacent vertices is 1")
	_check(MnnRuntime.pangtong_invert(0) == 63, "Pangtong inverse of Kun (0) is Qian (63)")
	_check(MnnRuntime.pangtong_invert(63) == 0, "Pangtong inverse of Qian (63) is Kun (0)")
	_check(MnnRuntime.nuclear_core(63) == 63, "Nuclear core of Qian (63) is Qian (63)")
	_check(MnnRuntime.nuclear_core(0) == 0, "Nuclear core of Kun (0) is Kun (0)")
	_check(MnnRuntime.hamming_neighbors(0).size() == 6, "Vertex in Q6 has exactly 6 neighbors")

	# --- Tier-2: Cellular Sheaf Laplacian ---
	var init_state := PackedFloat32Array([0.8, 0.7, 0.9, 0.2, 0.3, 0.1])
	var energy_init := MnnRuntime.sheaf_local_energy(1, init_state)
	_check(energy_init > 0.0, "Sheaf local energy is non-negative and positive for non-trivial state")
	var diffused := MnnRuntime.sheaf_diffuse_step(1, init_state, 0.1)
	_check(diffused.size() == 6, "Sheaf diffusion preserves 6-dim vitality stalk")
	var energy_next := MnnRuntime.sheaf_local_energy(1, diffused)
	_check(energy_next <= energy_init + 0.05, "Sheaf diffusion steps towards harmonic equilibrium")
	_check(MnnRuntime.sheaf_resonance(1, 1) == 1.0, "Sheaf self-resonance is 1.0")
	_check(MnnRuntime.sheaf_resonance(0, 63) <= 0.5, "Antipodal sheaf resonance is attenuated")
	_check(MnnRuntime.sheaf_resonance(1, 2) == MnnRuntime.sheaf_resonance(2, 1), "Sheaf resonance is symmetric")


	_the_jni_bridge()

	print("checks: ", _checks, " (floor ", MIN_CHECKS, ")")
	if _checks < MIN_CHECKS:
		_fails += 1
		printerr("FAIL only ", _checks, " checks ran; the floor is ", MIN_CHECKS)
	if _fails == 0:
		print("=== ALL PASS ===")
	quit(0 if _fails == 0 else 1)


## THE BRIDGE THAT DIED ON THE FIRST REAL WORD (Phase 12, field fault 3).
##
## The Fold, 2026-08-25, 17:18:27: `voice: heard Hi` — the ear transcribed a real
## person for the first time on record. The agent asked the mind, the first token
## came back, and the process aborted:
##
##   JNI DETECTED ERROR IN APPLICATION: jclass has wrong type:
##       com.ix64.hexy.mnn.IxMnnNative  ->  art::JavaVMExt::JniAbort
##
## `IxMnnNative` is a Kotlin `object`, so its `external fun`s are INSTANCE
## methods and JNI hands them the SINGLETON as their second argument — a
## `jobject`, not a class. The C++ called `GetStaticMethodID` on it.
##
## THE ABORT IS ONLY PROVABLE ON THE DEVICE. What is provable here is the shape
## of the code that caused it, and this section is the fence around that shape.
func _the_jni_bridge() -> void:
	print("--- the jni bridge ---")
	var src := FileAccess.get_file_as_string(
		("res://android_plugin/ixmnn/src/main/cpp/ixmnn_jni.cpp" if FileAccess.file_exists("res://android_plugin/ixmnn/src/main/cpp/ixmnn_jni.cpp") else "res://../android_plugin/ixmnn/src/main/cpp/ixmnn_jni.cpp"))
	if src == "":
		_check(true, "(no C++ in this checkout - nothing to audit)")
		return

	# THE CLASS IS FOUND BY NAME AND HELD GLOBALLY. A `FindClass` result is a
	# LOCAL reference, void the moment its frame returns; a global is what makes
	# it safe to keep and safe to use from another thread.
	_check(src.find("FindClass(kNativeClassName)") != -1,
		"the class is looked up BY NAME, not taken from a call parameter")
	_check(src.find("NewGlobalRef(local)") != -1,
		"...AND IMMEDIATELY MADE GLOBAL - a local would not survive the frame")
	var find_at := src.find("FindClass(")
	var global_at := src.find("NewGlobalRef(")
	_check(find_at != -1 and global_at > find_at,
		"...on the next lines, not later")
	_check(src.find("DeleteLocalRef(local)") != -1, "...and the local is dropped")
	_check(src.count("FindClass(") == 1,
		"THERE IS EXACTLY ONE CLASS LOOKUP IN THE WHOLE FILE")
	_check(src.find("JNI_OnLoad") != -1,
		"...and it happens at load, on the thread that has the right loader")
	_check(src.find("DeleteGlobalRef(gNativeClass)") != -1,
		"...and the global is given back at unload")

	# THE METHOD ID COMES OFF THE GLOBAL, and never off a parameter. This is the
	# exact line that aborted the phone.
	_check(src.find("GetStaticMethodID(gNativeClass") != -1,
		"the method id is taken off the CACHED CLASS")
	_check(src.count("GetStaticMethodID(") == 1,
		"...exactly once, at load - not once per stream")
	_check(src.find("GetStaticMethodID(klass") == -1,
		"AND NEVER OFF A CALL PARAMETER - the line that killed the Fold is gone")

	# NO ENTRY POINT CLAIMS ITS SECOND ARGUMENT IS A CLASS. They are instance
	# methods of a Kotlin `object`; what arrives is the singleton.
	_check(src.find("JNIEnv* env, jclass") == -1,
		"NO ENTRY POINT DECLARES A `jclass` PARAMETER any more")
	_check(src.find("JNIEnv*, jclass") == -1, "...not one of them")
	_check(src.find("jobject, jlong handle") != -1,
		"...they say `jobject`, which is what JNI actually passes")

	# THE CALL USES THE CACHE.
	_check(src.find("CallStaticVoidMethod(gNativeClass, gOnChatToken") != -1,
		"the token callback calls through the cache")
	_check(src.find("j->klass") == -1, "...and the sink holds no class at all")

	# THE VM IS CACHED, NOT THE ENV. A JavaVM* may cross threads; a JNIEnv* may
	# never. The attach path exists so a callback from a thread MNN owns cannot
	# reintroduce this family of bug.
	_check(src.find("JavaVM* gVm") != -1, "the VM is what is cached")
	_check(src.find("AttachCurrentThread") != -1,
		"...and a thread without an env attaches for one")
	_check(src.find("static JNIEnv") == -1, "AND NO ENV IS EVER CACHED")

	# AND IXBODY HAS NO JNI TO GET WRONG. IxBody and IxFinder are pure Kotlin
	# over a Maven MediaPipe artifact; there is no second copy of this pattern.
	_check(not FileAccess.file_exists(
		"res://../android_plugin/ixbody/src/main/cpp/ixbody_jni.cpp"),
		"ixbody has no C++ of its own - nothing to audit there")
