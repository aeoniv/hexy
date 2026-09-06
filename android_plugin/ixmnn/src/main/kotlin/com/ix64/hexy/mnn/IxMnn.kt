package com.ix64.hexy.mnn

import android.app.ActivityManager
import android.content.Context
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * THE VERSION THIS AAR ANSWERS TO. Bump the number with ANY change to the seam
 * this plugin presents to GDScript — a new @UsedByGodot method, a changed
 * signature, a new or renamed signal — and bump the matching `NEEDS` in every
 * GDScript seam that binds it (`scripts/seam.gd` lists them).
 *
 * WHY IT EXISTS. The AARs are gitignored build output staged by
 * `./gradlew exportAllAars`. A forgotten stage ships an OLD plugin under a NEW
 * script, and the failure is silent: the call lands on a method that is not
 * there, or worse, on one that still is and means something else. The handshake
 * turns that into one loud line at attach and a degrade to the mock.
 *
 * `./gradlew exportAllAars` copies this string into addons/ixmnn/bin/VERSION,
 * which IS tracked — so what was staged is readable in a diff.
 */
const val PLUGIN_VERSION = "ixmnn/1"

/**
 * MNN runtime host for MnnRuntime (scripts/brain/mnn_runtime.gd).
 *
 * One inference runtime for the whole app (the lesson from ix64-avatar's
 * MediaPipe dual-registry crash, its ARCHITECTURE.md §4.2): both the embedder
 * and the chat session are MNN LLM-engine objects behind the same JNI bridge.
 *
 * Models never ride in the APK. `embed_start` / `chat_start` take a directory
 * name relative to the app's external files dir —
 * `/storage/emulated/0/Android/data/app.ix64.hexy/files/<dir>` — which is where
 * `tools/push_mnn_model.ps1` puts them. A missing model is not an error the
 * caller has to guess at: start returns false and the GDScript seam keeps
 * saying `backend=mock`.
 *
 * Threading: MNN's Executor is thread-local and Llm is not reentrant, so every
 * native call runs on one dedicated worker thread. Godot's caller blocks on
 * the result — honest and simple for v1; a streaming/async seam can come later
 * without changing the GDScript contract.
 */
class IxMnn(godot: Godot) : GodotPlugin(godot) {

	private companion object {
		const val TAG = "IxMnn"
		const val MAX_NEW_TOKENS = 192
	}

	private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "ixmnn").apply { isDaemon = true } }

	private var loaded: Boolean? = null
	/**
	 * THE NATIVE HANDLES, AND WHY THEY ARE VOLATILE.
	 *
	 * Every native CALL runs on the one "ixmnn" worker thread, but the guards in
	 * front of those calls do not: `chat_stream` reads [chatHandle] on Godot's
	 * thread to decide whether there is a mind to talk to at all, and the
	 * `embed_*` doors read [embedHandle] and [embedDim] the same way — while
	 * `release` and the `*_start` doors write them from the worker. Without
	 * `@Volatile` the reading thread may keep a cached zero long after a model
	 * has loaded (a mind that is up and reports itself absent) or a cached
	 * non-zero after a release (a pointer into freed memory, handed to JNI). The
	 * pattern is the one ixbody's landmarker learned the hard way: the field is
	 * cheap, the wrong answer is a crash on somebody else's phone.
	 */
	@Volatile private var embedHandle = 0L
	@Volatile private var embedDim = 0
	@Volatile private var chatHandle = 0L
	/** Phase 10c. One streaming chat turn at a time; see [chat_stream]. */
	private val streaming = AtomicBoolean(false)

	override fun getPluginName() = "IxMnn"

	/**
	 * THE HANDSHAKE. Asked once by the GDScript seam at attach, compared with
	 * its own `NEEDS`, and a mismatch degrades that seam to its mock rather
	 * than letting a stale AAR answer new questions. See [PLUGIN_VERSION].
	 */
	@UsedByGodot
	fun plugin_version(): String = PLUGIN_VERSION

	/**
	 * PHASE 11b — THERE IS NO CAMERA IN THIS PLUGIN ANY MORE.
	 *
	 * `look_answer`, `look_fault`, `lens_changed` and `look_frame` were the
	 * world sense's four signals, and `IxLens` was the one-shot back camera that
	 * fed them. All five are deleted with the model they served: Qwen2-VL took
	 * seconds per frame, needed 1.7 GB of weights and a six-gigabyte phone, had
	 * to be told to answer in English, and emitted grounding tokens into the
	 * middle of prose. The eyes are a MediaPipe detector in ixbody now, LOOK is
	 * one pass of it, and this module is a mind and an embedder.
	 *
	 * WHAT THAT DELETED BESIDES A CLASS: the only place in this app that ever
	 * wrote a camera frame to disk. `IxLens.toFrameFile` put one JPEG in the
	 * private cache because MNN's in-memory image door answered in question
	 * marks and a path was the road MNN itself tested. There is no such file now
	 * and no code that could make one.
	 *
	 * `Boolean::class.javaObjectType`, NOT `Boolean::class.java` — the latter is
	 * the PRIMITIVE `boolean.class` and `emitSignal`'s vararg boxes every
	 * argument, so the declared type never matches the delivered one and the
	 * signal is dropped in silence. ixmesh's `probe_done`, ixloc's compass and
	 * ixbody's `face_seen` have each paid this bill once. Nothing here is a
	 * primitive today; the law is left written down for the next signal.
	 */
	override fun getPluginSignals(): Set<SignalInfo> = setOf(
		// PHASE 10c — THE FAST MOUTH. One signal per token-ish chunk while a
		// chat turn is generating, and one when the turn is over carrying the
		// whole of it.
		SignalInfo("chat_token", String::class.java),
		SignalInfo("chat_done", String::class.java),
		// A TURN THAT BROKE, SAID OUT LOUD. `chat_done("")` alone is a mind that
		// thought for a moment and had nothing to say, which is a thing that can
		// honestly happen — so it cannot also be how a native failure is
		// reported, or the FSM above can never tell "no answer" from "no engine".
		// Both are emitted, fault FIRST: the fault is the news, and the empty
		// `chat_done` after it is what ends the turn for a seam that is only
		// listening for that. See [chat_stream].
		SignalInfo("chat_fault", String::class.java))

	private fun <T> onWorker(default: T, body: () -> T): T = try {
		worker.submit(Callable { body() }).get()
	} catch (t: Throwable) {
		Log.e(TAG, "native call failed", t)
		default
	}

	/** Resolves a caller-supplied model directory and its MNN config.json. */
	private fun configPath(dir: String): String? {
		val base = activity?.getExternalFilesDir(null) ?: return null
		val modelDir = File(base, dir)
		val config = File(modelDir, "config.json")
		if (!config.isFile) {
			Log.w(TAG, "no model at ${config.absolutePath} — push one with tools/push_mnn_model.ps1")
			return null
		}
		return config.absolutePath
	}

	/**
	 * INSTALLED RAM IN BYTES, or -1 if even this cannot answer.
	 *
	 * PHASE 9.7e, AND IT IS THE THIRD ROAD TO THE SAME NUMBER. The RAM gate in
	 * `scripts/net/model_store.gd` refuses the 1.7 GB vision lane on a phone
	 * that cannot hold it, and it could not find out how much memory it was
	 * standing on: Godot's `OS.get_memory_info().physical` is -1 on Android,
	 * and `/proc/meminfo` — the obvious answer, and readable over adb — is not
	 * readable from inside the app sandbox. Both were tried on the A22 and both
	 * said "unknown", which the gate ALLOWS, so a 4 GiB phone was cleared for a
	 * lane it can never run.
	 *
	 * `ActivityManager.MemoryInfo.totalMem` is the same figure by an API that
	 * no filesystem question can block. It needs no permission, it is a
	 * constant for the life of the device, and it is what every Android memory
	 * check is written against.
	 *
	 * WHY IT LIVES IN THIS PLUGIN. `IxMnn` is the thing that loads models into
	 * memory; how much memory there is to load them into is its own business,
	 * and the one caller is the store that decides which models to fetch. The
	 * alternative was the voice plugin, which is cheaper to rebuild and has
	 * nothing whatever to do with the question.
	 */
	@UsedByGodot
	fun total_ram(): Long {
		val act = activity ?: return -1L
		return try {
			val am = act.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
				?: return -1L
			val info = ActivityManager.MemoryInfo()
			am.getMemoryInfo(info)
			// 0 would be a lie the gate cannot see through - it reads any
			// non-positive number as "nobody would say", which is the honest
			// unknown it already handles.
			if (info.totalMem > 0L) info.totalMem else -1L
		} catch (t: Throwable) {
			Log.w(TAG, "total_ram", t)
			-1L
		}
	}

	@UsedByGodot
	fun runtime_ready(): Boolean {
		loaded?.let { return it }
		loaded = try {
			// libMNN + libMNN_Express + libllm are dependencies of our bridge,
			// so loading the bridge loads the runtime. libc++_shared must
			// already be beside them or none of it resolves.
			System.loadLibrary("ixmnnjni")
			true
		} catch (t: Throwable) {
			Log.e(TAG, "MNN native load failed", t)
			false
		}
		return loaded == true
	}

	/** Loads an MNN embedding model. Returns its dimension, or 0 on failure. */
	@UsedByGodot
	fun embed_start(dir: String): Int {
		if (!runtime_ready()) return 0
		if (embedHandle != 0L) return embedDim
		val config = configPath(dir) ?: return 0
		return onWorker(0) {
			val h = IxMnnNative.nativeEmbeddingCreate(config)
			if (h == 0L) {
				0
			} else {
				embedHandle = h
				embedDim = IxMnnNative.nativeEmbeddingDim(h)
				Log.i(TAG, "embedding ready: $dir, dim=$embedDim")
				embedDim
			}
		}
	}

	/** 0 until embed_start has succeeded. */
	@UsedByGodot
	fun embed_dim(): Int = embedDim

	@UsedByGodot
	fun embed(text: String): FloatArray {
		if (embedHandle == 0L) return FloatArray(0)
		return onWorker(FloatArray(0)) { IxMnnNative.nativeEmbed(embedHandle, text) }
	}

	/** Loads an MNN LLM for chat. Slow (hundreds of MB of weights). */
	@UsedByGodot
	fun chat_start(dir: String): Boolean {
		if (!runtime_ready()) return false
		if (chatHandle != 0L) return true
		val config = configPath(dir) ?: return false
		return onWorker(false) {
			val h = IxMnnNative.nativeLlmCreate(config)
			if (h == 0L) {
				false
			} else {
				chatHandle = h
				Log.i(TAG, "chat ready: $dir")
				true
			}
		}
	}

	@UsedByGodot
	fun chat_ready(): Boolean = chatHandle != 0L

	/** Blocking single-turn completion. Empty string means "no reply". */
	@UsedByGodot
	fun chat(prompt: String): String {
		if (chatHandle == 0L) return ""
		return onWorker("") { IxMnnNative.nativeChat(chatHandle, prompt, MAX_NEW_TOKENS) }
	}

	/**
	 * PHASE 10c — THE SAME TURN, SPOKEN AS IT IS THOUGHT.
	 *
	 * Returns IMMEDIATELY and answers with signals: `chat_token` per chunk while
	 * the model generates, then exactly one `chat_done` carrying the whole
	 * reply. [chat] is left exactly as it was, because a peer's question is
	 * answered as one message and has nothing to stream to.
	 *
	 * NOT `onWorker`. That helper blocks the caller on `.get()`, and the caller
	 * here is the frame the room is drawn on — blocking it would make a
	 * streaming mouth slower than the silent one it replaces. The submit is
	 * bare and the result comes back as signals.
	 *
	 * ONE STREAM AT A TIME, and it is a CAS rather than a flag: MNN's Llm is not
	 * reentrant and [tokenSink] is one field, so two overlapping streams would
	 * interleave two answers into one voice. The refusal is a `false` the
	 * GDScript seam turns back into the blocking road.
	 */
	@UsedByGodot
	fun chat_stream(prompt: String): Boolean {
		if (chatHandle == 0L) return false
		if (!streaming.compareAndSet(false, true)) return false
		worker.submit {
			var reply = ""
			var fault: String? = null
			try {
				IxMnnNative.tokenSink = { t -> emitSignal("chat_token", t) }
				reply = String(
					IxMnnNative.nativeChatStream(chatHandle, prompt, MAX_NEW_TOKENS),
					Charsets.UTF_8)
			} catch (t: Throwable) {
				Log.e(TAG, "chat stream failed", t)
				fault = t.message ?: t.javaClass.simpleName
			} finally {
				// THE SINK DIES WITH THE TURN, and `chat_done` is emitted on
				// every road out of this block including the throwing one — a
				// stream that ended without saying so is a turn the FSM would
				// have to watchdog out of, which is the silence this phase is
				// about.
				IxMnnNative.tokenSink = null
				streaming.set(false)
				// THE FAULT FIRST, THEN THE END OF THE TURN. Pretending a broken
				// turn produced an empty reply is the kind of quiet lie this
				// project keeps paying for; but a seam waiting on `chat_done`
				// would hang forever if the fault replaced it, so it does not
				// replace it — it precedes it.
				fault?.let { emitSignal("chat_fault", it) }
				emitSignal("chat_done", reply)
			}
		}
		return true
	}

	@UsedByGodot
	fun chat_streaming(): Boolean = streaming.get()

	// ------------------------------------------------------------ world sense
	//
	// DELETED IN PHASE 11b, and this comment is the marker where it stood.
	// `look_start`, `look_ready`, `look`, `look_stop`, `lens_open`, the separate
	// vision Llm session and `IxLens` were the whole of it. The world sense now
	// talks to ixbody's detector and to nothing in this file; MNN here is chat
	// and embeddings, which is what it is actually good at.

	@UsedByGodot
	fun set_hex_prior(hexBits: Int, beta: Float): Boolean {
		if (chatHandle == 0L) return false
		return onWorker(false) {
			IxMnnNative.nativeSetHexPrior(chatHandle, hexBits, beta)
		}
	}

	@UsedByGodot
	fun release(): Unit = onWorker(Unit) {
		if (embedHandle != 0L) IxMnnNative.nativeEmbeddingRelease(embedHandle)
		if (chatHandle != 0L) IxMnnNative.nativeLlmRelease(chatHandle)
		embedHandle = 0L
		chatHandle = 0L
		embedDim = 0
	}

	override fun onMainDestroy() {
		release()
		worker.shutdown()
	}
}
