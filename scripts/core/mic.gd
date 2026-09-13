class_name Mic
extends Node

## THE MIC, SEEN FROM THE CORE AS ONE SMALL DOOR.
##
## The phone already owns a speech recogniser, so hexy does not carry a second
## one: android_plugin/ixmnn exposes Android's own SpeechRecognizer -- asked to
## prefer offline, and on API 31+ asked for the strictly on-device engine first
## -- through five signals, and this node is the whole of the GDScript side.
##
## OFF THE PHONE IT IS STILL A MIC. With no IxMnn singleton the node answers
## with a mock that walks the same three steps in the same order: listening,
## one partial, one result, stopped. Nothing upstream branches on the device,
## and the flow is testable headless.
##
## IT NEVER SENDS. A result lands in the composer line and stops there; the
## person still taps SEND. A microphone that speaks for you is not a microphone.

signal partial(text: String)
signal result(text: String)
signal error(code: int, message: String)
signal level(rms: float)
signal state(name: String)

const STATE_LISTENING: String = "listening"
const STATE_STOPPED: String = "stopped"
const STATE_PERMISSION: String = "permission"

const LANG: String = "en-US"

## The mock's two words and the beat between them. Short enough that a test
## can await it twice without a sleep that reads like a wait.
const MOCK_PARTIAL: String = "mock"
const MOCK_TEXT: String = "mock transcript"
const MOCK_STEP_S: float = 0.05
## The level the mock reports while it is pretending to hear, in the same dB
## scale onRmsChanged uses.
const MOCK_RMS: float = 4.0

var _plugin: Object = null
var _listening: bool = false
var _step: int = 0
var _timer: Timer = null


func _init() -> void:
	if not Engine.has_singleton("IxMnn"):
		return
	var p: Object = Engine.get_singleton("IxMnn")
	if p == null or not p.has_method("mic_available"):
		return
	_plugin = p
	_connect_plugin()


func _connect_plugin() -> void:
	var rows: Array = [
		["mic_partial", _on_plugin_partial],
		["mic_result", _on_plugin_result],
		["mic_error", _on_plugin_error],
		["mic_level", _on_plugin_level],
		["mic_state", _on_plugin_state],
	]
	for row in rows:
		var sig: String = String(row[0])
		if _plugin.has_signal(sig):
			_plugin.connect(sig, row[1])


func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "MockStep"
	_timer.wait_time = MOCK_STEP_S
	_timer.one_shot = false
	_timer.timeout.connect(_on_mock_step)
	add_child(_timer)


# -- what the glass asks -----------------------------------------------------

## True when a tap on MIC would do something. The mock counts: a desktop with
## no recogniser can still be walked through the whole flow.
func available() -> bool:
	if _plugin == null:
		return true
	return bool(_plugin.call("mic_available"))


func backend_name() -> String:
	return "android" if _plugin != null else "mock"


func listening() -> bool:
	return _listening


## "granted", "denied" or "unknown". The plugin fires the request itself when
## the answer is denied, and says so with state("permission").
func permission() -> String:
	if _plugin == null:
		return "granted"
	if not _plugin.has_method("mic_permission"):
		return "unknown"
	return String(_plugin.call("mic_permission"))


func start() -> bool:
	if _listening:
		return false
	if not available():
		error.emit(-1, "no recogniser on this device")
		return false
	if _plugin != null:
		_plugin.call("mic_start", LANG)
		return true
	_listening = true
	_step = 0
	state.emit(STATE_LISTENING)
	level.emit(MOCK_RMS)
	if _timer != null:
		_timer.start()
	return true


func stop() -> void:
	if not _listening:
		return
	if _plugin != null:
		_plugin.call("mic_stop")
		return
	_finish_mock()


func cancel() -> void:
	if _plugin != null:
		if _plugin.has_method("mic_cancel"):
			_plugin.call("mic_cancel")
		return
	if not _listening:
		return
	if _timer != null:
		_timer.stop()
	_listening = false
	state.emit(STATE_STOPPED)


# -- the mock ----------------------------------------------------------------

func _on_mock_step() -> void:
	if not _listening:
		if _timer != null:
			_timer.stop()
		return
	_step += 1
	if _step == 1:
		partial.emit(MOCK_PARTIAL)
		level.emit(MOCK_RMS)
		return
	_finish_mock()


func _finish_mock() -> void:
	if _timer != null:
		_timer.stop()
	_listening = false
	result.emit(MOCK_TEXT)
	state.emit(STATE_STOPPED)


# -- the phone ---------------------------------------------------------------

func _on_plugin_partial(text: String) -> void:
	partial.emit(text)


func _on_plugin_result(text: String) -> void:
	result.emit(text)


func _on_plugin_error(code: int, message: String) -> void:
	error.emit(code, message)


func _on_plugin_level(rms: float) -> void:
	level.emit(rms)


func _on_plugin_state(name_of: String) -> void:
	if name_of == STATE_LISTENING:
		_listening = true
	elif name_of == STATE_STOPPED:
		_listening = false
	state.emit(name_of)
