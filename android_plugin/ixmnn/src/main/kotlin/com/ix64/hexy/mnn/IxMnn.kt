package com.ix64.hexy.mnn

import android.app.ActivityManager
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

const val PLUGIN_VERSION = "ixmnn/1"

/**
 * MNN runtime host for MnnRuntime (scripts/brain/mnn_runtime.gd).
 * Provides JNI bindings for on-device Qwen LLM inference and GTE embeddings.
 */
class IxMnn(godot: Godot) : GodotPlugin(godot), SensorEventListener {

	private companion object {
		const val TAG = "IxMnn"
		const val MAX_NEW_TOKENS = 192
		const val MIC_NO_ENGINE = -1
		const val MIC_NO_PERMISSION = -2
		const val MIC_FAILED = -3
		const val MIC_PERMISSION_REQUEST = 6401
	}

	private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "ixmnn").apply { isDaemon = true } }

	private var loaded: Boolean? = null
	@Volatile private var embedHandle = 0L
	@Volatile private var embedDim = 0
	@Volatile private var chatHandle = 0L
	private val streaming = AtomicBoolean(false)

	override fun getPluginName() = "IxMnn"

	@UsedByGodot
	fun plugin_version(): String = PLUGIN_VERSION

	override fun getPluginSignals(): Set<SignalInfo> = setOf(
		SignalInfo("chat_token", String::class.java),
		SignalInfo("chat_done", String::class.java),
		SignalInfo("chat_fault", String::class.java),
		SignalInfo("mic_partial", String::class.java),
		SignalInfo("mic_result", String::class.java),
		SignalInfo("mic_error", Integer::class.java, String::class.java),
		SignalInfo("mic_level", java.lang.Float::class.java),
		SignalInfo("mic_state", String::class.java)
	)

	private fun <T> onWorker(default: T, body: () -> T): T = try {
		worker.submit(Callable { body() }).get()
	} catch (t: Throwable) {
		Log.e(TAG, "native call failed", t)
		default
	}

	private fun configPath(dir: String): String? {
		val base = activity?.getExternalFilesDir(null) ?: return null
		val modelDir = File(base, dir)
		val config = File(modelDir, "config.json")
		if (!config.isFile) {
			Log.w(TAG, "no model at ${config.absolutePath}")
			return null
		}
		return config.absolutePath
	}

	@UsedByGodot
	fun total_ram(): Long {
		val act = activity ?: return -1L
		return try {
			val am = act.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
				?: return -1L
			val info = ActivityManager.MemoryInfo()
			am.getMemoryInfo(info)
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
			System.loadLibrary("ixmnnjni")
			true
		} catch (t: Throwable) {
			Log.e(TAG, "MNN native load failed", t)
			false
		}
		return loaded == true
	}

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

	@UsedByGodot
	fun embed_dim(): Int = embedDim

	@UsedByGodot
	fun embed(text: String): FloatArray {
		if (embedHandle == 0L) return FloatArray(0)
		return onWorker(FloatArray(0)) { IxMnnNative.nativeEmbed(embedHandle, text) }
	}

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

	@UsedByGodot
	fun chat(prompt: String): String = chat_at(prompt, -1)

	/**
	 * CHAT AGAINST A DECLARED CAST. `castVersion` is the version the caller
	 * believes the cube carries -- the one stamped by [q6_set_figure_words].
	 * -1 means "don't care" and is exactly what [chat] passes. A mismatch is
	 * counted in [q6_prior_mismatches] and logged natively; the answer still
	 * comes back. A cube that cannot lean must never cost the user an answer.
	 */
	@UsedByGodot
	fun chat_at(prompt: String, castVersion: Int): String {
		if (chatHandle == 0L) return ""
		return onWorker("") {
			IxMnnNative.nativeChat(chatHandle, prompt, MAX_NEW_TOKENS, castVersion)
		}
	}

	@UsedByGodot
	fun chat_stream(prompt: String): Boolean = chat_stream_at(prompt, -1)

	/** [chat_stream] against a declared cast version; see [chat_at]. */
	@UsedByGodot
	fun chat_stream_at(prompt: String, castVersion: Int): Boolean {
		if (chatHandle == 0L) return false
		if (!streaming.compareAndSet(false, true)) return false
		worker.submit {
			var reply = ""
			var fault: String? = null
			try {
				IxMnnNative.tokenSink = { t -> emitSignal("chat_token", t) }
				reply = String(
					IxMnnNative.nativeChatStream(chatHandle, prompt, MAX_NEW_TOKENS, castVersion),
					Charsets.UTF_8
				)
			} catch (t: Throwable) {
				Log.e(TAG, "chat stream failed", t)
			fault = t.message ?: t.javaClass.simpleName
			} finally {
				IxMnnNative.tokenSink = null
				streaming.set(false)
				fault?.let { emitSignal("chat_fault", it) }
				emitSignal("chat_done", reply)
			}
		}
		return true
	}

	@UsedByGodot
	fun chat_streaming(): Boolean = streaming.get()

	// --- Q6: the six-bit cube -------------------------------------------------
	//
	// ONE state p[64] over the 64 hexagrams, native, in q6/q6.cpp, sitting beside
	// the Qwen decode loop and the MNN runtime. Godot moves it (Pacing, every
	// tick), the decode loop reads it as a prior (every token), and embed() turns
	// it into a point in R^32 for the room and the mesh. Three readers, one state.
	//
	// These are plain arithmetic over 64 doubles -- microseconds, no model, no
	// file -- so unlike chat and embed they run on the CALLING thread rather than
	// being posted to the worker. The native side takes a mutex, because the
	// decode loop is reading the same cube on the worker while Godot writes it.
	//
	// Every one of them is a no-op returning a safe default when the native
	// library did not load, so the GDScript client never has to branch.

	@UsedByGodot
	fun q6_reset(bits: Int) {
		if (runtime_ready()) IxMnnNative.nativeQ6Reset(bits)
	}

	@UsedByGodot
	fun q6_inject(bits: Int) {
		if (runtime_ready()) IxMnnNative.nativeQ6Inject(bits)
	}

	@UsedByGodot
	fun q6_uniform() {
		if (runtime_ready()) IxMnnNative.nativeQ6Uniform()
	}

	@UsedByGodot
	fun q6_anchor(bits: Int, amount: Float) {
		if (runtime_ready()) IxMnnNative.nativeQ6Anchor(bits, amount)
	}

	@UsedByGodot
	fun q6_step(bias: FloatArray, t: Float, beta: Float) {
		if (runtime_ready()) IxMnnNative.nativeQ6Step(bias, t, beta)
	}

	@UsedByGodot
	fun q6_state(): FloatArray =
		if (runtime_ready()) IxMnnNative.nativeQ6State() else FloatArray(64)

	@UsedByGodot
	fun q6_set_state(state: FloatArray) {
		if (runtime_ready()) IxMnnNative.nativeQ6SetState(state)
	}

	@UsedByGodot
	fun q6_argmax(): Int = if (runtime_ready()) IxMnnNative.nativeQ6Argmax() else 0

	@UsedByGodot
	fun q6_tension(): Float = if (runtime_ready()) IxMnnNative.nativeQ6Tension() else 0f

	@UsedByGodot
	fun q6_best_neighbour(bits: Int): Int =
		if (runtime_ready()) IxMnnNative.nativeQ6BestNeighbour(bits) else 0

	@UsedByGodot
	fun q6_embed(): FloatArray =
		if (runtime_ready()) IxMnnNative.nativeQ6Embed() else FloatArray(32)

	/**
	 * How hard the decode loop hears the cube. 0 -- the default -- is the old
	 * behaviour exactly: MNN's own Llm::response() runs and no logit is touched.
	 * Above 0 the native side runs its own decode loop and adds w * p[h] * 64 to
	 * the logit of each of the 64 figure words set by [q6_set_figure_words].
	 */
	@UsedByGodot
	fun q6_set_prior_weight(w: Float) {
		if (runtime_ready()) IxMnnNative.nativeQ6SetPriorWeight(w)
	}

	@UsedByGodot
	fun q6_prior_weight(): Float =
		if (runtime_ready()) IxMnnNative.nativeQ6PriorWeight() else 0f

	/**
	 * The 64 figure words the prior leans on, indexed by hexagram BITS, handed
	 * down from scripts/core/iching/king_wen.gd so no second copy of that table
	 * lives here to drift. Anything shorter than 64 is padded with empty strings,
	 * and an empty word is simply never biased.
	 */
	@UsedByGodot
	fun q6_set_figure_words(words: Array<String>, version: Int) {
		if (!runtime_ready()) return
		val full = Array(64) { i -> if (i < words.size) words[i] else "" }
		IxMnnNative.nativeQ6SetFigureWords(full, version)
	}

	/**
	 * The cast version stamped on the cube's current figure-word push, or -1
	 * when nothing has stamped it. Mass moves -- inject, step, anchor, a state
	 * restore -- never change it.
	 */
	@UsedByGodot
	fun q6_figure_version(): Int =
		if (runtime_ready()) IxMnnNative.nativeQ6FigureVersion() else -1

	/**
	 * How many decodes have run with a chat asking for one version and the cube
	 * carrying another. Reported, never enforced.
	 */
	@UsedByGodot
	fun q6_prior_mismatches(): Int =
		if (runtime_ready()) IxMnnNative.nativeQ6PriorMismatches() else 0

	
	private var sensorManager: SensorManager? = null
	private var lightSensor: Sensor? = null
	private var proximitySensor: Sensor? = null
	@Volatile private var ambientLux: Float = -1f
	@Volatile private var proximityDistance: Float = -1f

	private fun ensureSensors() {
		if (sensorManager != null) return
		val act = activity ?: return
		val sm = act.getSystemService(Context.SENSOR_SERVICE) as? SensorManager ?: return
		sensorManager = sm
		lightSensor = sm.getDefaultSensor(Sensor.TYPE_LIGHT)?.also {
			sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
		}
		proximitySensor = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY)?.also {
			sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
		}
		Log.i(TAG, "Hardware sensors registered: light=" + (lightSensor != null) + ", prox=" + (proximitySensor != null))
	}

	override fun onSensorChanged(event: SensorEvent) {
		when (event.sensor.type) {
			Sensor.TYPE_LIGHT -> ambientLux = event.values[0]
			Sensor.TYPE_PROXIMITY -> proximityDistance = event.values[0]
		}
	}

	override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}

	@UsedByGodot
	fun get_ambient_lux(): Float {
		ensureSensors()
		return ambientLux
	}

	@UsedByGodot
	fun get_proximity(): Float {
		ensureSensors()
		return proximityDistance
	}

	@UsedByGodot
	fun get_battery_level(): Float {
		val act = activity ?: return -1f
		return try {
			val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
			val batteryStatus = act.registerReceiver(null, ifilter) ?: return -1f
			val level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
			val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
			if (level >= 0 && scale > 0) (level.toFloat() / scale.toFloat()) * 100f else -1f
		} catch (e: Exception) {
			-1f
		}
	}

	// --- THE MIC: Android's own recogniser, on the device, on the main thread --
	//
	// No network service and no second model. SpeechRecognizer is asked to
	// prefer offline, and on API 31+ we ask for the strictly on-device engine
	// first and fall back to the ordinary one when the phone has none. The
	// recogniser is a main-thread object: every touch of it is posted to the UI
	// thread, and every answer leaves as a Godot signal.

	@Volatile private var recognizer: SpeechRecognizer? = null
	@Volatile private var listening = false
	private var micLang: String = "en-US"

	private fun ui(body: () -> Unit) {
		val act = activity ?: return
		act.runOnUiThread {
			try {
				body()
			} catch (t: Throwable) {
				Log.e(TAG, "mic main-thread call failed", t)
				emitSignal("mic_error", MIC_FAILED, t.message ?: t.javaClass.simpleName)
			}
		}
	}

	@UsedByGodot
	fun mic_available(): Boolean {
		val act = activity ?: return false
		return try {
			SpeechRecognizer.isRecognitionAvailable(act)
		} catch (t: Throwable) {
			Log.w(TAG, "mic_available", t)
			false
		}
	}

	/** "granted", "denied" or "unknown" -- and a request is fired when denied. */
	@UsedByGodot
	fun mic_permission(): String {
		val act = activity ?: return "unknown"
		return try {
			val have = act.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
				PackageManager.PERMISSION_GRANTED
			if (have) {
				"granted"
			} else {
				ui {
					act.requestPermissions(
						arrayOf(Manifest.permission.RECORD_AUDIO), MIC_PERMISSION_REQUEST)
					emitSignal("mic_state", "permission")
				}
				"denied"
			}
		} catch (t: Throwable) {
			Log.w(TAG, "mic_permission", t)
			"unknown"
		}
	}

	@UsedByGodot
	fun mic_listening(): Boolean = listening

	@UsedByGodot
	fun mic_start(lang: String) {
		if (listening) return
		val act = activity ?: return
		if (!mic_available()) {
			emitSignal("mic_error", MIC_NO_ENGINE, "no recognition engine on this device")
			return
		}
		if (mic_permission() != "granted") {
			emitSignal("mic_error", MIC_NO_PERMISSION, "RECORD_AUDIO not granted")
			return
		}
		micLang = if (lang.isBlank()) "en-US" else lang
		ui {
			val rec = recognizer ?: newRecognizer(act) ?: return@ui
			val intent = android.content.Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
				putExtra(
					RecognizerIntent.EXTRA_LANGUAGE_MODEL,
					RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
				putExtra(RecognizerIntent.EXTRA_LANGUAGE, micLang)
				putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
				putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
				putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, act.packageName)
			}
			listening = true
			rec.startListening(intent)
			emitSignal("mic_state", "listening")
		}
	}

	@UsedByGodot
	fun mic_stop() {
		if (!listening) return
		ui { recognizer?.stopListening() }
	}

	@UsedByGodot
	fun mic_cancel() {
		ui {
			recognizer?.cancel()
			if (listening) {
				listening = false
				emitSignal("mic_state", "stopped")
			}
		}
	}

	/** Main thread only. On-device first on API 31+, ordinary engine after. */
	private fun newRecognizer(act: android.app.Activity): SpeechRecognizer? {
		var rec: SpeechRecognizer? = null
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			rec = try {
				if (SpeechRecognizer.isOnDeviceRecognitionAvailable(act))
					SpeechRecognizer.createOnDeviceSpeechRecognizer(act) else null
			} catch (t: Throwable) {
				Log.w(TAG, "on-device recogniser unavailable", t)
				null
			}
		}
		if (rec == null) {
			rec = try {
				SpeechRecognizer.createSpeechRecognizer(act)
			} catch (t: Throwable) {
				Log.e(TAG, "no recogniser", t)
				emitSignal("mic_error", MIC_NO_ENGINE, t.message ?: "no recogniser")
				null
			}
		}
		rec?.setRecognitionListener(micListener)
		recognizer = rec
		return rec
	}

	private fun firstOf(results: Bundle?): String {
		val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
		return if (list.isNullOrEmpty()) "" else list[0]
	}

	private val micListener = object : RecognitionListener {
		override fun onReadyForSpeech(params: Bundle?) {}
		override fun onBeginningOfSpeech() {}

		override fun onRmsChanged(rmsdB: Float) {
			emitSignal("mic_level", rmsdB)
		}

		override fun onBufferReceived(buffer: ByteArray?) {}

		override fun onEndOfSpeech() {}

		override fun onError(error: Int) {
			listening = false
			emitSignal("mic_error", error, micErrorText(error))
			emitSignal("mic_state", "stopped")
		}

		override fun onResults(results: Bundle?) {
			listening = false
			emitSignal("mic_result", firstOf(results))
			emitSignal("mic_state", "stopped")
		}

		override fun onPartialResults(partialResults: Bundle?) {
			val text = firstOf(partialResults)
			if (text.isNotEmpty()) emitSignal("mic_partial", text)
		}

		override fun onEvent(eventType: Int, params: Bundle?) {}
	}

	private fun micErrorText(code: Int): String = when (code) {
		SpeechRecognizer.ERROR_AUDIO -> "audio recording error"
		SpeechRecognizer.ERROR_CLIENT -> "client side error"
		SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "no microphone permission"
		SpeechRecognizer.ERROR_NETWORK -> "network error"
		SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network timeout"
		SpeechRecognizer.ERROR_NO_MATCH -> "heard nothing it knows"
		SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "recogniser busy"
		SpeechRecognizer.ERROR_SERVER -> "server error"
		SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no speech"
		else -> "speech error " + code
	}

	private fun micRelease() {
		val rec = recognizer ?: return
		recognizer = null
		listening = false
		try {
			rec.destroy()
		} catch (t: Throwable) {
			Log.w(TAG, "mic release", t)
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
		micRelease()
		sensorManager?.unregisterListener(this)
		release()
		worker.shutdown()
	}
}
