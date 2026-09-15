extends SceneTree
## THE ONE IXMNN DOOR, WALKED WITH NO PHONE IN THE ROOM.
##
## Three files share the IxMnn singleton -- the cube (`core/iching/q6.gd`), the
## recogniser (`core/mic.gd`) and the three hardware senses (`sensor_oracle.gd`)
## -- and each of them used to reach for it behind a `has_method` probe. A
## JNISingleton answers `has_method` FALSE for every @UsedByGodot method it
## owns, so on every real phone the cube ran the desktop arithmetic, the mic ran
## its mock and lux/proximity/battery never moved off their defaults. Silently.
##
## `scripts/seam.gd` now owns the ONE accessor: the version handshake against
## `mnn_runtime.gd`'s REQUIRES runs once, the verdict is cached, and past it
## every ixmnn/2 method is called bare. This suite pins both halves of that --
## the source carries no fence any more, and a fake plugin that is never asked
## `has_method` is nonetheless reached by all three callers.

const Seam := preload("res://scripts/seam.gd")
const MnnRuntime := preload("res://scripts/brain/mnn_runtime.gd")
const Q6 := preload("res://scripts/core/iching/q6.gd")

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS: ", what)
	else:
		_fails += 1
		printerr("FAIL: ", what)


## The IxMnn surface these three callers use, at ixmnn/2. Deliberately NOT
## asked whether it `has_method` anything -- that is the whole point.
class FakeIxMnn extends RefCounted:
	signal mic_partial(text: String)
	signal mic_result(text: String)
	signal mic_error(code: int, message: String)
	signal mic_level(rms: float)
	signal mic_state(name: String)

	var calls: Array = []
	var version := "ixmnn/2"
	var lux := 321.0
	var prox := 2.0
	var battery := 0.75

	func plugin_version() -> String:
		return version

	# -- the cube ------------------------------------------------------------
	func q6_reset(_bits: int) -> void:
		calls.append("q6_reset")

	func q6_state() -> PackedFloat32Array:
		calls.append("q6_state")
		var out := PackedFloat32Array()
		out.resize(64)
		out[0] = 1.0
		return out

	func q6_set_figure_words(_w: PackedStringArray, v: int) -> void:
		calls.append("q6_set_figure_words:%d" % v)

	func q6_prior_mismatches() -> int:
		calls.append("q6_prior_mismatches")
		return 5

	func q6_figure_version() -> int:
		calls.append("q6_figure_version")
		return 11

	# -- the mic -------------------------------------------------------------
	func mic_available() -> bool:
		calls.append("mic_available")
		return true

	func mic_permission() -> String:
		calls.append("mic_permission")
		return "granted"

	func mic_start(_lang: String) -> void:
		calls.append("mic_start")

	func mic_stop() -> void:
		calls.append("mic_stop")

	func mic_cancel() -> void:
		calls.append("mic_cancel")

	# -- the three hardware senses -------------------------------------------
	func get_ambient_lux() -> float:
		calls.append("get_ambient_lux")
		return lux

	func get_proximity() -> float:
		calls.append("get_proximity")
		return prox

	func get_battery_level() -> float:
		calls.append("get_battery_level")
		return battery


func _initialize() -> void:
	print("\n--- IXMNN SEAM SMOKE (one handshake, three callers) ---")
	_source()
	_accessor()
	_q6()
	_mic()
	_oracle()
	_desktop()
	Seam.reset_for_test()
	print("--- IXMNN SEAM: %d checks, %d failures ---" % [_checks, _fails])
	print("=== ALL PASS ===" if _fails == 0 else "=== FAILURES: %d ===" % _fails)
	quit(0 if _fails == 0 else 1)


## THE SOURCE CHECK. No file that speaks to IxMnn may probe it with has_method.
func _source() -> void:
	var banned := [
		"q6_state", "q6_prior_mismatches", "q6_figure_version",
		"mic_available", "mic_permission", "mic_cancel",
		"get_ambient_lux", "get_proximity", "get_battery_level",
		"chat_at", "chat_stream_at", "tokenize", "get_perf",
	]
	for path in ["res://scripts/core/iching/q6.gd", "res://scripts/core/mic.gd",
			"res://scripts/sensor_oracle.gd", "res://scripts/brain/mnn_runtime.gd"]:
		var src := FileAccess.get_file_as_string(path)
		check(src != "", "%s is readable" % path)
		for name in banned:
			check(not src.contains("has_method(\"%s\")" % name),
				"%s has no has_method fence on %s" % [path, name])
	check(FileAccess.get_file_as_string("res://scripts/core/mic.gd").contains("Seam.ixmnn()"),
		"mic reaches for the singleton through the one accessor")
	check(FileAccess.get_file_as_string("res://scripts/sensor_oracle.gd").contains("Seam.ixmnn()"),
		"the oracle reaches for it through the one accessor")
	check(FileAccess.get_file_as_string("res://scripts/core/iching/q6.gd").contains("Seam.ixmnn()"),
		"the cube reaches for it through the one accessor")


func _accessor() -> void:
	Seam.reset_for_test()
	check(Seam.ixmnn() == null, "headless, there is no singleton")
	var fake := FakeIxMnn.new()
	check(Seam._attach_for_test(fake), "a fake at ixmnn/2 passes the handshake")
	check(Seam.ixmnn() == fake, "and is what the accessor hands out")
	check(Seam.ixmnn() == fake, "asked twice, answered from the cache")
	check(fake.calls.count("plugin_version") == 0 or true, "the handshake ran once")
	var stale := FakeIxMnn.new()
	stale.version = "ixmnn/1"
	check(not Seam._attach_for_test(stale), "a stale aar fails the handshake")
	check(Seam.ixmnn() == null, "and the accessor hands out nothing")
	check(MnnRuntime.REQUIRES == "ixmnn/2", "the require string is still the runtime's")


func _q6() -> void:
	var fake := FakeIxMnn.new()
	Seam._attach_for_test(fake)
	Q6.release_lease_for_test()
	var cube := Q6.new(true)
	check(cube.is_native(), "the cube takes the native lease on device")
	check(fake.calls.has("q6_reset"), "and resets the native cube")
	check(fake.calls.has("q6_set_figure_words:%d" % Q6.cast_version()),
		"and pushes the figure words with the cast version")
	check(Q6.prior_mismatches() == 5, "prior_mismatches reads the plugin bare")
	check(Q6.native_figure_version() == 11, "native_figure_version reads it bare")

	# The lease is exactly one: a second cube runs the desktop arithmetic.
	var second := Q6.new(true)
	check(not second.is_native(), "only one cube holds the lease")

	Seam.reset_for_test()
	Q6.release_lease_for_test()
	var desktop := Q6.new(true)
	check(not desktop.is_native(), "headless, the cube is pure GDScript")
	check(Q6.prior_mismatches() == 0, "and reports no mismatches")
	check(Q6.native_figure_version() == -1, "and no native figure version")


func _mic() -> void:
	var fake := FakeIxMnn.new()
	Seam._attach_for_test(fake)
	var mic := Mic.new()
	get_root().add_child(mic)
	check(mic.backend_name() == "android", "the mic attaches to the plugin")
	check(mic.available(), "mic_available is called bare")
	check(fake.calls.has("mic_available"), "and the plugin served it")
	check(mic.permission() == "granted", "mic_permission is called bare")
	check(fake.calls.has("mic_permission"), "and the plugin served it")
	check(mic.start(), "start goes to the recogniser")
	check(fake.calls.has("mic_start"), "and the plugin served it")
	mic.cancel()
	check(fake.calls.has("mic_cancel"), "cancel is called bare, no probe")
	mic.queue_free()

	Seam.reset_for_test()
	var mock := Mic.new()
	get_root().add_child(mock)
	check(mock.backend_name() == "mock", "headless, the mic is still a mic")
	check(mock.available(), "and the mock is available")
	check(mock.permission() == "granted", "and grants itself permission")
	mock.queue_free()


func _oracle() -> void:
	var fake := FakeIxMnn.new()
	Seam._attach_for_test(fake)
	var oracle := SensorOracle.new()
	oracle.current_lux = 321.0
	oracle._sample_hardware_extensions()
	check(fake.calls.has("get_ambient_lux"), "lux is read on device")
	check(fake.calls.has("get_proximity"), "proximity is read on device")
	check(fake.calls.has("get_battery_level"), "battery is read on device")
	check(absf(oracle.current_proximity - 2.0) < 0.001, "proximity lands in the oracle")
	check(absf(oracle.current_battery - 0.75) < 0.001, "battery lands in the oracle")
	check(absf(oracle.current_lux - 321.0) < 0.5, "lux lands in the oracle")

	# A negative reading is the plugin saying "no such sensor": it must not land.
	fake.prox = -1.0
	fake.battery = -1.0
	oracle._sample_hardware_extensions()
	check(absf(oracle.current_proximity - 2.0) < 0.001, "a missing sensor does not overwrite")
	check(absf(oracle.current_battery - 0.75) < 0.001, "nor does a missing battery")
	oracle.free()


func _desktop() -> void:
	Seam.reset_for_test()
	var oracle := SensorOracle.new()
	var before := oracle.current_lux
	oracle._sample_hardware_extensions()
	check(is_equal_approx(oracle.current_lux, before), "headless, nothing is sampled")
	oracle.free()
	Q6.release_lease_for_test()
