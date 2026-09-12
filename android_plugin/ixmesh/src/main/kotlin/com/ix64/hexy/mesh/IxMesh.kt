package com.ix64.hexy.mesh

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.ConcurrentHashMap

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
 * `./gradlew exportAllAars` copies this string into addons/ixmesh/bin/VERSION,
 * which IS tracked — so what was staged is readable in a diff.
 */
const val PLUGIN_VERSION = "ixmesh/1"

/**
 * Mesh backend for MeshPeer (scripts/net/mesh_peer.gd) over Google Nearby
 * Connections, P2P_CLUSTER: every peer both advertises and discovers, so a
 * gym floor of phones forms a cluster with no host. Wire shape mirrors the
 * desktop LanMesh backend: events are JSON strings, never frames.
 *
 * UNVERIFIED on device until built against libs/godot-lib.template_release.aar.
 */
class IxMesh(godot: Godot) : GodotPlugin(godot) {

	private val serviceId = "ix64.hexy.mesh"
	private val strategy = Strategy.P2P_CLUSTER
	private var client: ConnectionsClient? = null
	private var myName = "hexy"
	/**
	 * ENDPOINT ID -> NAME, AND WHY IT IS CONCURRENT.
	 *
	 * This map is WRITTEN on Nearby's own callback thread ([connectionCallback])
	 * and READ, whole, on Godot's thread — [broadcast] iterates its keys every
	 * time an event goes out, [connected_peers] joins them for the panel, and
	 * [start] walks it to re-announce. A plain HashMap resized under an iterator
	 * does not throw politely across that boundary; it corrupts, spins, or hands
	 * back a peer that disconnected, and it does it on the phone with the most
	 * peers in the room, which is the one demo you cannot repeat. Every map in
	 * this class that Nearby writes to is concurrent for the same reason.
	 */
	private val peers = ConcurrentHashMap<String, String>() // endpointId -> name
	private var pendingStart = false
	private var running = false
	/**
	 * WAS THE MESH UP WHEN WE WENT AWAY, so a resume can put it back. Same shape,
	 * and the same reason, as ixloc's location half: `running` says the radios
	 * are advertising NOW, this says somebody still wants them to be.
	 */
	private var resumeMesh = false

	companion object {
		private const val TAG = "IxMesh"
		private const val PERMISSION_REQUEST_CODE = 6401
		/** How long the app must be truly away before the radios go down. A
		 * dialog or a fold blink is milliseconds; a pocket is minutes. */
		private const val PAUSE_GRACE_MS = 60_000L
		// Mirrored from scripts/social/radar.gd. A distance class, never metres.
		private const val CLS_TOUCH = "touch"
		private const val CLS_ROOM = "room"
		private const val CLS_FAR = "far"
		private const val DEFAULT_CLASS = CLS_ROOM
	}

	override fun getPluginName() = "IxMesh"

	/**
	 * THE HANDSHAKE. Asked once by the GDScript seam at attach, compared with
	 * its own `NEEDS`, and a mismatch degrades that seam to its mock rather
	 * than letting a stale AAR answer new questions. See [PLUGIN_VERSION].
	 */
	@UsedByGodot
	fun plugin_version(): String = PLUGIN_VERSION

	override fun getPluginSignals() = setOf(
		SignalInfo("peer_found", String::class.java, String::class.java),
		SignalInfo("peer_lost", String::class.java),
		SignalInfo("event_received", String::class.java, String::class.java),
		SignalInfo("peer_proximity", String::class.java, String::class.java),
		// The raw bandwidth class, unmapped — `peer_proximity` collapses HIGH and
		// MEDIUM into two distance words and loses the one fact the Wi-Fi-upgrade
		// probe exists to read. Both are emitted; neither replaces the other.
		SignalInfo("bandwidth_changed", String::class.java, String::class.java),
		// endpoint, direction ("sent"/"received"), bytes, seconds.
		// javaObjectType, NOT ::class.java: a primitive double in a SignalInfo
		// makes emitSignal fail silently and the signal never arrives.
		SignalInfo(
			"probe_done", String::class.java, String::class.java,
			Double::class.javaObjectType, Double::class.javaObjectType
		),
	)

	/**
	 * WHAT NEARBY ACTUALLY GIVES YOU, and what it does not.
	 *
	 * There is no RSSI in this API. `DiscoveredEndpointInfo` carries only the
	 * service id, the endpoint name and whether the endpoint is incoming — no
	 * signal strength, no TX power, nothing distance-shaped. Once a connection
	 * is up, `ConnectionInfo` adds an auth token and `isIncomingConnection`,
	 * and that is the end of it. Google exposes no raw radio measurement at any
	 * point in the lifecycle, by design: Nearby picks and upgrades the medium
	 * for you and does not report which one it landed on either.
	 *
	 * The single quantity it does surface that varies with the link is
	 * [BandwidthInfo.getQuality] in [onBandwidthChanged]. That is a bandwidth
	 * class, not a distance — but the mediums it stands for have very different
	 * ranges, so it is a weak, honest lower bound on how near a peer must be:
	 *
	 *   HIGH    -> WiFi Direct / hotspot / LAN class link. Negotiating one of
	 *              these means the radios held a high-rate link, which in
	 *              practice is the same room or nearer. -> "room"
	 *   MEDIUM  -> BLE L2CAP or an unupgraded WiFi-class path. -> "far"
	 *   LOW     -> plain Bluetooth. Reachable, nothing more. -> "far"
	 *   UNKNOWN -> it declined to say. -> DEFAULT
	 *
	 * "touch" is therefore never emitted by this backend. Nothing Nearby hands
	 * over can distinguish a phone on the same table from a phone across the
	 * room, and a class that cannot be earned is not going to be guessed. The
	 * desktop LanMesh backend does emit "touch", for the one case it can prove
	 * (a peer on this very machine — see scripts/net/lan_mesh.gd).
	 *
	 * A connected peer that has not yet had a bandwidth callback gets
	 * [DEFAULT_CLASS]: we are meshed, so they are within a radio's reach, which
	 * is "room" and no better. The radar draws them on its inner
	 * "direction unknown" ring, which is exactly what that claim is worth.
	 */
	private fun classFor(quality: Int): String = when (quality) {
		BandwidthInfo.Quality.HIGH -> CLS_ROOM
		BandwidthInfo.Quality.MEDIUM, BandwidthInfo.Quality.LOW -> CLS_FAR
		else -> DEFAULT_CLASS
	}

	/** The quality constant's own name, for the log and for `bandwidth_changed`. */
	private fun qualityName(quality: Int): String = when (quality) {
		BandwidthInfo.Quality.HIGH -> "HIGH"
		BandwidthInfo.Quality.MEDIUM -> "MEDIUM"
		BandwidthInfo.Quality.LOW -> "LOW"
		else -> "UNKNOWN"
	}

	/** Last class emitted per endpoint, so a repeat callback is not a repeat signal. */
	private val proximity = ConcurrentHashMap<String, String>()

	/**
	 * Last bandwidth quality name per endpoint, kept for two reasons: a repeat
	 * callback is not a transition, and [start] re-announces it. An emit before
	 * GDScript connected is destroyed, not delayed — the same trap ixloc paid
	 * for with the heading.
	 */
	private val bandwidth = ConcurrentHashMap<String, String>()

	private fun emitBandwidth(endpointId: String, name: String) {
		if (bandwidth[endpointId] == name) return
		bandwidth[endpointId] = name
		Log.i(TAG, "bandwidth_changed $endpointId $name at ${System.currentTimeMillis()}")
		emitSignal("bandwidth_changed", endpointId, name)
	}

	private fun emitProximity(endpointId: String, cls: String) {
		if (proximity[endpointId] == cls) return
		proximity[endpointId] = cls
		Log.i(TAG, "peer_proximity $endpointId $cls")
		emitSignal("peer_proximity", endpointId, cls)
	}

	/**
	 * Nearby's dangerous permissions for this device's API level. On 31+ the
	 * Bluetooth trio replaced location; 33+ adds NEARBY_WIFI_DEVICES; below 31
	 * Nearby still rides on ACCESS_FINE_LOCATION.
	 */
	private fun requiredPermissions(): Array<String> {
		val needed = ArrayList<String>()
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			needed += Manifest.permission.BLUETOOTH_ADVERTISE
			needed += Manifest.permission.BLUETOOTH_CONNECT
			needed += Manifest.permission.BLUETOOTH_SCAN
		} else {
			needed += Manifest.permission.ACCESS_FINE_LOCATION
		}
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
			needed += Manifest.permission.NEARBY_WIFI_DEVICES
		return needed.toTypedArray()
	}

	private fun deviceSuffix(): String {
		val ctx = activity ?: return "0000"
		val id = android.provider.Settings.Secure.getString(
			ctx.contentResolver, android.provider.Settings.Secure.ANDROID_ID
		) ?: return "0000"
		return if (id.length >= 4) id.substring(0, 4) else id
	}

	private fun missingPermissions(): Array<String> {
		val ctx = activity ?: return emptyArray()
		return requiredPermissions().filter {
			ContextCompat.checkSelfPermission(ctx, it) != PackageManager.PERMISSION_GRANTED
		}.toTypedArray()
	}

	@UsedByGodot
	fun start(displayName: String) {
		val activity = activity ?: return
		// start() is the one moment the plugin knows a listener exists, so say
		// again everything already known. A signal emitted before GDScript
		// connected is destroyed, not delayed — see ixloc's heading.
		for ((endpointId, name) in peers) {
			emitSignal("peer_found", endpointId, name)
			bandwidth[endpointId]?.let { emitSignal("bandwidth_changed", endpointId, it) }
			proximity[endpointId]?.let { emitSignal("peer_proximity", endpointId, it) }
		}
		// Endpoint names must differ between installs: the discovery tiebreak is
		// lexicographic, and every phone ships the same GDScript display name.
		myName = "$displayName-" + deviceSuffix()
		val missing = missingPermissions()
		if (missing.isNotEmpty()) {
			Log.i(TAG, "requesting ${missing.size} permission(s): ${missing.joinToString()}")
			pendingStart = true
			runOnUiThread {
				ActivityCompat.requestPermissions(activity, missing, PERMISSION_REQUEST_CODE)
			}
			return
		}
		startNearby()
	}

	private fun startNearby() {
		val activity = activity ?: return
		pendingStart = false
		if (running) return
		running = true
		Log.i(TAG, "permissions granted; starting advertising + discovery as $myName")
		client = Nearby.getConnectionsClient(activity)
		client?.startAdvertising(
			myName, serviceId, connectionCallback,
			AdvertisingOptions.Builder().setStrategy(strategy).build()
		)?.addOnFailureListener { Log.w(TAG, "startAdvertising failed", it) }
		client?.startDiscovery(
			serviceId, discoveryCallback,
			DiscoveryOptions.Builder().setStrategy(strategy).build()
		)?.addOnFailureListener { Log.w(TAG, "startDiscovery failed", it) }
	}

	override fun onMainRequestPermissionsResult(
		requestCode: Int, permissions: Array<out String>?, grantResults: IntArray?
	) {
		if (requestCode != PERMISSION_REQUEST_CODE) return
		val denied = missingPermissions()
		if (denied.isEmpty()) {
			startNearby()
		} else {
			Log.w(TAG, "permissions denied: ${denied.joinToString()} — mesh stays off")
			pendingStart = false
		}
	}

	/** Safety net: if the dialog was answered while Godot was paused, retry on resume. */
	override fun onMainResume() {
		// A resume inside the grace window is a blink, not a return: the armed
		// teardown is disarmed and the radios never noticed anything happened.
		pauseTask?.cancel(false)
		pauseTask = null
		if (pendingStart && missingPermissions().isEmpty()) startNearby()
		// …and the other half of [onMainPause]: whatever was up when we went away
		// comes back up, under the name this session already chose.
		if (resumeMesh && missingPermissions().isEmpty()) {
			resumeMesh = false
			Log.i(TAG, "resume — restarting advertising and discovery")
			startNearby()
		}
	}

	@UsedByGodot
	fun stop() {
		teardownNearby()
		running = false
		pendingStart = false
		// An explicit stop is a decision, not an interruption: a later resume must
		// not undo it.
		resumeMesh = false
	}

	/**
	 * PUT THE RADIOS DOWN AND FORGET WHO WAS THERE.
	 *
	 * The forgetting is the half that was missing. `stop()` used to clear [peers]
	 * and leave [proximity] and [bandwidth] behind, so the next `start()` — whose
	 * whole job is to re-announce what is already known to a listener that has
	 * only just connected — walked a map of peers that had been disconnected
	 * minutes ago and told the radar about phones that were no longer in the
	 * building. A stale peer drawn on a dial is worse than an empty dial: it is
	 * the app being confidently wrong about who is near you, which is the one
	 * thing this whole lane exists to be right about.
	 *
	 * `stopAllEndpoints` also fires no `onDisconnected` we can rely on, so the
	 * clearing has to be done here rather than waited for.
	 */
	private fun teardownNearby() {
		try {
			client?.stopAllEndpoints()
			client?.stopAdvertising()
			client?.stopDiscovery()
		} catch (t: Throwable) {
			Log.w(TAG, "nearby teardown", t)
		}
		peers.clear()
		proximity.clear()
		bandwidth.clear()
		sending.clear()
		receiving.clear()
		chunkRun = null
	}

	/**
	 * A TRIP TO THE HOME SCREEN PUTS THE RADIOS DOWN — AFTER A GRACE PERIOD.
	 *
	 * Advertising and discovery are a Bluetooth scan and a Wi-Fi negotiation that
	 * run until told otherwise; nothing about the Activity going away stops them,
	 * so a phone in a pocket kept announcing itself to a gym floor for the rest of
	 * the session. That is the battery law and the presence promise failing in the
	 * same breath — a peer the radar shows as "here" is a phone whose owner left.
	 *
	 * BUT GODOT PAUSES FOR A BLINK, CONSTANTLY (field, 2026-08-26): a permission
	 * dialog, the shade, a fold posture change — each fired onMainPause/onMainResume
	 * milliseconds apart, and a teardown on every blink made the OTHER phone watch
	 * this one leave and re-arrive every few seconds. So the pause arms a timer and
	 * the resume disarms it: the radios go down only when the app has really been
	 * away for [PAUSE_GRACE_MS], which a pocket satisfies and a dialog never does.
	 */
	override fun onMainPause() {
		if (!running) return
		pauseTask?.cancel(false)
		pauseTask = rxIdle.schedule({
			activity?.runOnUiThread {
				if (!running) return@runOnUiThread
				Log.i(TAG, "paused ${PAUSE_GRACE_MS}ms — stopping advertising and discovery")
				teardownNearby()
				running = false
				resumeMesh = true
			}
		}, PAUSE_GRACE_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
	}

	/**
	 * THE PROCESS IS GOING. Nearby holds registrations in a system service that
	 * outlives this plugin, so a destroy that left them up would leave callbacks
	 * pointing into a dead object — and, on Godot's restart-in-place path, a
	 * second advertiser under the same service id.
	 */
	override fun onMainDestroy() {
		stop()
		client = null
		rxIdle.shutdownNow()
	}

	@UsedByGodot
	fun broadcast(json: String) {
		val payload = Payload.fromBytes(json.toByteArray(Charsets.UTF_8))
		for (endpointId in peers.keys) client?.sendPayload(endpointId, payload)
	}

	/** Comma-separated endpoint ids we are connected to. "" when alone. */
	@UsedByGodot
	fun connected_peers(): String = peers.keys.joinToString(",")

	// ---------------------------------------------------------------- the probe
	//
	// WHY A STREAM AND NOT CHUNKED BYTES. Nearby's BYTES payload is capped at
	// 32 KiB (`ConnectionsClient.MAX_BYTES_DATA_SIZE`), so five megabytes is
	// either 160 separate payloads or one stream. Chunking would measure our own
	// framing as much as the link: 160 sends, 160 receive callbacks, and a
	// request/response rhythm the transport can never pipeline through. A STREAM
	// payload is one call, Nearby pulls from it as fast as the negotiated medium
	// allows, and the number that comes out is the medium's number rather than
	// ours. That is the honest measurement, and it is also the simplest.
	//
	// The bytes are generated, never allocated: a 5 MiB ByteArray on the A22's
	// 4 GB is avoidable and the pattern is deterministic either way, so both
	// phones can say what they should have received.

	/** Deterministic filler: byte i is (i % 251), a prime so no 256-run aliases. */
	private class ProbeStream(private val total: Long) : java.io.InputStream() {
		private var sent = 0L
		override fun read(): Int {
			if (sent >= total) return -1
			return ((sent++ % 251L).toInt()) and 0xFF
		}

		override fun read(b: ByteArray, off: Int, len: Int): Int {
			if (sent >= total) return -1
			val n = minOf(len.toLong(), total - sent).toInt()
			for (i in 0 until n) b[off + i] = ((sent + i) % 251L).toByte()
			sent += n
			return n
		}
	}

	/** payloadId -> (endpoint, start ms) for transfers we started. Written from
	 * Godot's thread in [probe_send] and from Nearby's in the transfer updates —
	 * see the note on [peers] for why that means concurrent. */
	private val sending = ConcurrentHashMap<Long, Pair<String, Long>>()
	/** payloadId -> start ms for transfers arriving at us. Written on Nearby's
	 * callback thread and cleared on the drain thread this class starts. */
	private val receiving = ConcurrentHashMap<Long, Long>()

	/**
	 * Send [totalBytes] of filler to [endpointId] and time it. Returns false if
	 * we are not connected to that endpoint — the caller gets a no, not silence.
	 *
	 * Both ends report: the sender from its transfer updates, the receiver from
	 * the clock around its own read loop. The receiver's number is the honest
	 * one; the sender's SUCCESS can land when the last byte was handed to the
	 * transport rather than when it arrived.
	 */
	@UsedByGodot
	fun probe_send(endpointId: String, totalBytes: Int): Boolean {
		val c = client ?: return false
		if (!peers.containsKey(endpointId)) {
			Log.w(TAG, "probe_send: not connected to $endpointId")
			return false
		}
		val payload = Payload.fromStream(ProbeStream(totalBytes.toLong()))
		sending[payload.id] = Pair(endpointId, System.currentTimeMillis())
		Log.i(TAG, "probe: sending $totalBytes B to $endpointId " +
			"payload=${payload.id} quality=${bandwidth[endpointId]} " +
			"at ${System.currentTimeMillis()}")
		c.sendPayload(endpointId, payload)
			.addOnFailureListener { Log.w(TAG, "probe: sendPayload failed", it) }
		return true
	}

	/**
	 * A run of capped BYTES payloads, and the reason it exists next to the
	 * stream above.
	 *
	 * A STREAM payload's sender-side SUCCESS means "Nearby drained the pipe",
	 * not "the peer holds the bytes" — on device it returned 5 MiB in 147 ms,
	 * a local buffer measured, not a link. A BYTES payload is acknowledged by
	 * the receiving Nearby, so the last SUCCESS in a run of them is the closest
	 * thing to a delivery receipt this API offers. It costs 160 framings on
	 * 5 MiB and undercounts the link by that much: the number it gives is a
	 * FLOOR, which is the honest direction for a number to be wrong in.
	 *
	 * It also survives a peer running an older build, which a stream does not —
	 * that peer's `onPayloadReceived` drops anything `asBytes()` cannot answer,
	 * so nothing ever drains the stream and the sender measures its own RAM.
	 */
	private class ChunkRun(
		val endpointId: String, var startedAt: Long, val total: Long
	) {
		val outstanding = HashSet<Long>()
		var acked = 0L
	}

	/**
	 * @Volatile because the run is PUBLISHED from Godot's thread in
	 * [probe_send_chunks] and read — and cleared — from Nearby's, inside
	 * `onPayloadTransferUpdate`. Without it the callback thread may keep reading
	 * a stale null and never close a run that has finished, which is a probe
	 * that reports nothing rather than a probe that reports badly.
	 */
	@Volatile private var chunkRun: ChunkRun? = null

	@UsedByGodot
	fun probe_send_chunks(endpointId: String, totalBytes: Int, chunkBytes: Int): Boolean {
		val c = client ?: return false
		if (!peers.containsKey(endpointId)) {
			Log.w(TAG, "probe_send_chunks: not connected to $endpointId")
			return false
		}
		if (chunkRun != null) {
			Log.w(TAG, "probe_send_chunks: a run is already in flight")
			return false
		}
		val cap = chunkBytes.coerceIn(1024, 32 * 1024)
		val run = ChunkRun(endpointId, System.currentTimeMillis(), totalBytes.toLong())
		Log.i(TAG, "probe: chunk run $totalBytes B in ${cap} B payloads to " +
			"$endpointId quality=${bandwidth[endpointId]} at ${run.startedAt}")
		// BUILD EVERY PAYLOAD FIRST, SEND SECOND. Nearby delivers transfer
		// updates on the main thread while this method runs on Godot's, so
		// interleaving the two lets chunk 1's SUCCESS empty `outstanding`
		// before chunk 3 has been added — and the run closes after 64 KB,
		// reporting a 38 ms number for a five megabyte transfer. Measured on a
		// Fold 4 before this loop was split in two.
		val payloads = ArrayList<Payload>()
		var left = totalBytes.toLong()
		while (left > 0) {
			val n = minOf(left, cap.toLong()).toInt()
			// Valid JSON, so a peer on an older build parses it, fails the
			// envelope check and drops it — rather than logging a parse error
			// 160 times. The filler is a cheap deterministic pattern.
			// `{"probe":"` is 10 bytes and `"}` is 2, so the filler is n-12 and
			// the payload is exactly n. Off by two per chunk is 320 bytes over
			// a 5 MiB run, which reads in the log as loss that never happened.
			val filler = StringBuilder(n)
			for (i in 0 until maxOf(0, n - 12)) filler.append(('a' + (i % 26)))
			val p = Payload.fromBytes("{\"probe\":\"$filler\"}".toByteArray(Charsets.UTF_8))
			payloads.add(p)
			left -= n
		}
		synchronized(run) { for (p in payloads) run.outstanding.add(p.id) }
		// Published only once every id it will ever wait for is in it: an
		// update for a payload the run has not heard of is somebody else's.
		chunkRun = run
		run.startedAt = System.currentTimeMillis()
		for (p in payloads)
			c.sendPayload(endpointId, p)
				.addOnFailureListener { Log.w(TAG, "probe: chunk send failed", it) }
		return true
	}

	/**
	 * The receiving half of a chunk run. Nobody announces how many chunks are
	 * coming, so the run ends the only way it can: by going quiet. 750 ms of
	 * silence closes it, and the elapsed time reported is first chunk to last —
	 * the idle wait is not counted as transfer time.
	 */
	private val rxIdle = java.util.concurrent.Executors.newSingleThreadScheduledExecutor()
	/** The armed pause-teardown, if the app is currently away. See [onMainPause]. */
	@Volatile private var pauseTask: java.util.concurrent.ScheduledFuture<*>? = null
	private var rxBytes = 0L
	private var rxStart = 0L
	private var rxLast = 0L
	private var rxTask: java.util.concurrent.ScheduledFuture<*>? = null

	@Synchronized
	private fun noteProbeChunk(endpointId: String, n: Long) {
		val now = System.currentTimeMillis()
		if (rxBytes == 0L) {
			rxStart = now
			Log.i(TAG, "probe: incoming chunks from $endpointId " +
				"quality=${bandwidth[endpointId]} at $now")
		}
		rxBytes += n
		rxLast = now
		rxTask?.cancel(false)
		rxTask = rxIdle.schedule(
			{ closeProbeRx(endpointId) }, 750L, java.util.concurrent.TimeUnit.MILLISECONDS
		)
	}

	@Synchronized
	private fun closeProbeRx(endpointId: String) {
		if (rxBytes == 0L) return
		val bytes = rxBytes
		val ms = rxLast - rxStart
		rxBytes = 0L
		probeDone(endpointId, "received-chunked", bytes, ms)
	}

	private fun probeDone(endpointId: String, dir: String, bytes: Long, ms: Long) {
		val seconds = ms / 1000.0
		val rate = if (seconds > 0.0) bytes / seconds else 0.0
		Log.i(TAG, "probe: $dir $bytes B in ${"%.3f".format(seconds)} s = " +
			"${"%.0f".format(rate)} B/s (${"%.1f".format(rate / 1024.0)} KiB/s) " +
			"peer=$endpointId quality=${bandwidth[endpointId]}")
		emitSignal("probe_done", endpointId, dir, bytes.toDouble(), seconds)
	}

	private val discoveryCallback = object : EndpointDiscoveryCallback() {
		override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
			Log.i(TAG, "endpoint found: ${info.endpointName} ($endpointId)")
			// A force-killed previous process can leave ghost endpoints behind; a
			// phone must never mesh with its own advertised name.
			if (info.endpointName == myName) {
				Log.i(TAG, "ignoring self endpoint: ${info.endpointName} ($endpointId)")
				return
			}
			// Lexicographic tiebreak so exactly one side requests the connection.
			if (myName <= info.endpointName)
				client?.requestConnection(myName, endpointId, connectionCallback)
					?.addOnFailureListener { Log.w(TAG, "requestConnection failed", it) }
		}

		override fun onEndpointLost(endpointId: String) {}
	}

	private val connectionCallback = object : ConnectionLifecycleCallback() {
		private val names = HashMap<String, String>()

		override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
			if (info.endpointName == myName) {
				Log.i(TAG, "rejecting self endpoint: ${info.endpointName} ($endpointId)")
				client?.rejectConnection(endpointId)
				return
			}
			names[endpointId] = info.endpointName
			client?.acceptConnection(endpointId, payloadCallback)
		}

		override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
			if (result.status.isSuccess) {
				peers[endpointId] = names[endpointId] ?: "?"
				emitSignal("peer_found", endpointId, peers[endpointId])
				// A baseline with a timestamp on it: whatever the link is at the
				// moment it comes up, before any bulk traffic asks it to be more.
				emitBandwidth(endpointId, "UNKNOWN")
				// Connected is itself the weakest honest proximity claim there
				// is: within radio reach. Say it now rather than leave the radar
				// with nothing until a bandwidth callback that may never come.
				emitProximity(endpointId, DEFAULT_CLASS)
			}
		}

		/**
		 * The one link measurement Nearby offers. See [classFor] for why a
		 * bandwidth class is being read as a distance class, and how weakly.
		 */
		override fun onBandwidthChanged(endpointId: String, info: BandwidthInfo) {
			Log.i(TAG, "bandwidth $endpointId quality=${info.quality} " +
				"(${qualityName(info.quality)})")
			emitBandwidth(endpointId, qualityName(info.quality))
			emitProximity(endpointId, classFor(info.quality))
		}

		override fun onDisconnected(endpointId: String) {
			peers.remove(endpointId)
			proximity.remove(endpointId)
			bandwidth.remove(endpointId)
			emitSignal("peer_lost", endpointId)
		}
	}

	private val payloadCallback = object : PayloadCallback() {
		override fun onPayloadReceived(endpointId: String, payload: Payload) {
			// A STREAM payload is the probe and nothing else: the mesh itself only
			// ever sends BYTES. Drain it on a thread of our own — Nearby hands over
			// the pipe the moment the first byte lands, so the read loop's own
			// clock IS the transfer time.
			if (payload.type == Payload.Type.STREAM) {
				val stream = payload.asStream()?.asInputStream() ?: return
				receiving[payload.id] = System.currentTimeMillis()
				Log.i(TAG, "probe: incoming stream from $endpointId " +
					"payload=${payload.id} quality=${bandwidth[endpointId]} " +
					"at ${System.currentTimeMillis()}")
				Thread {
					val t0 = System.currentTimeMillis()
					var total = 0L
					val buf = ByteArray(32 * 1024)
					try {
						while (true) {
							val n = stream.read(buf)
							if (n < 0) break
							total += n
						}
					} catch (e: Exception) {
						Log.w(TAG, "probe: read failed after $total B", e)
					} finally {
						try { stream.close() } catch (_: Exception) {}
					}
					receiving.remove(payload.id)
					probeDone(endpointId, "received", total, System.currentTimeMillis() - t0)
				}.start()
				return
			}
			val bytes = payload.asBytes() ?: return
			val text = String(bytes, Charsets.UTF_8)
			// A chunk of somebody's probe. Counted here rather than in GDScript
			// because the fabric would drop it (it is not an envelope) and the
			// receiving end's own clock is the number that matters.
			if (text.startsWith("{\"probe\":\"")) {
				noteProbeChunk(endpointId, bytes.size.toLong())
				return
			}
			emitSignal("event_received", endpointId, text)
		}

		override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
			val run = chunkRun
			if (run != null) {
				var mine = false
				var finished = false
				synchronized(run) {
					mine = run.outstanding.contains(update.payloadId)
					if (mine && update.status != PayloadTransferUpdate.Status.IN_PROGRESS) {
						run.outstanding.remove(update.payloadId)
						if (update.status == PayloadTransferUpdate.Status.SUCCESS)
							run.acked += update.totalBytes
						finished = run.outstanding.isEmpty()
					}
				}
				if (finished) {
					chunkRun = null
					val ms = System.currentTimeMillis() - run.startedAt
					Log.i(TAG, "probe: chunk run done, ${run.acked}/${run.total} B acked")
					probeDone(run.endpointId, "chunked", run.acked, ms)
				}
				if (mine) return
			}
			val started = sending[update.payloadId] ?: return
			when (update.status) {
				PayloadTransferUpdate.Status.SUCCESS -> {
					sending.remove(update.payloadId)
					probeDone(endpointId, "sent", update.bytesTransferred,
						System.currentTimeMillis() - started.second)
				}
				PayloadTransferUpdate.Status.FAILURE,
				PayloadTransferUpdate.Status.CANCELED -> {
					sending.remove(update.payloadId)
					Log.w(TAG, "probe: transfer to $endpointId ended status=" +
						"${update.status} after ${update.bytesTransferred} B")
					probeDone(endpointId, "failed", update.bytesTransferred,
						System.currentTimeMillis() - started.second)
				}
				else -> {
					// One line per megabyte, so a five-minute transfer is five
					// lines and a stalled one is visibly a stalled one.
					val mb = update.bytesTransferred / (1024 * 1024)
					if (mb != lastLoggedMb) {
						lastLoggedMb = mb
						Log.i(TAG, "probe: ${update.bytesTransferred} B out to " +
							"$endpointId after ${System.currentTimeMillis() - started.second} ms " +
							"quality=${bandwidth[endpointId]}")
					}
				}
			}
		}

		private var lastLoggedMb = -1L
	}
}
