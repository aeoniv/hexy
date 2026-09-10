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
		SignalInfo("chat_fault", String::class.java)
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
	fun chat(prompt: String): String {
		if (chatHandle == 0L) return ""
		return onWorker("") { IxMnnNative.nativeChat(chatHandle, prompt, MAX_NEW_TOKENS) }
	}

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

	@UsedByGodot
	fun release(): Unit = onWorker(Unit) {
		if (embedHandle != 0L) IxMnnNative.nativeEmbeddingRelease(embedHandle)
		if (chatHandle != 0L) IxMnnNative.nativeLlmRelease(chatHandle)
		embedHandle = 0L
		chatHandle = 0L
		embedDim = 0
	}

	override fun onMainDestroy() {
		sensorManager?.unregisterListener(this)
		release()
		worker.shutdown()
	}
}
