extends SceneTree
## MnnRuntime contract: honest backend name, deterministic unit-length mock
## embeddings, cosine sanity. Prints === ALL PASS === or fails.

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")

var _fails := 0
## EVERY CHECK IS COUNTED. A compile error in a depended script makes a whole
## section skip silently, and a suite that prints ALL PASS because it ran nothing
## is worse than a red one. Raise this floor when checks are added.
const MIN_CHECKS := 21
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
		"res://../android_plugin/ixmnn/src/main/cpp/ixmnn_jni.cpp")
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
