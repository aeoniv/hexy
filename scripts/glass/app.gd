class_name HexyApp
extends Node

## THE ROOT, AND THE ONLY PLACE THE PARTS MEET.
##
## Seven objects, built once, wired once, and never again referred to by each
## other by name: store, mnn, qwen, wmn, senses, creature, hud. Every one of
## them is handed its neighbours through a bind() and nothing reaches sideways
## for a singleton. That is why the import wall test can be short.
##
## THE BOOT LINE IS THE CONTRACT. One ASCII line, printed once, saying whether
## a model is really on the device, which fabric the mesh came up on, and that
## the sixteen are all there. A person reading a logcat should learn the three
## things that change what the app can do, and nothing else.

var store: HexyStore = null
var mnn: Mnn = null
var qwen: Qwen = null
var wmn: Wmn = null
var senses: Senses = null
var creature: Creature = null
## The surface is the OWNER'S HUD, bridged to the core -- not the sixteen-seat
## ring that scripts/glass/glass.gd draws. That file stays on disk, and the
## import wall still keeps it honest, but nothing boots it any more.
var hud: HudBridge = null

var _ticker: Timer = null
var _boot_line: String = ""


func _ready() -> void:
	store = HexyStore.new()
	store.name = "Store"
	add_child(store)

	mnn = Mnn.new()
	mnn.name = "Mnn"
	add_child(mnn)

	qwen = Qwen.new()
	qwen.name = "Qwen"
	add_child(qwen)

	wmn = Wmn.new()
	wmn.name = "Wmn"
	add_child(wmn)

	senses = Senses.new()
	senses.name = "Senses"
	senses.period_changed.connect(_on_period_changed)
	add_child(senses)

	hud = HudBridge.new()
	hud.name = "Hud"
	add_child(hud)

	creature = Creature.new()
	creature.name = "Creature"

	qwen.bind(store, mnn)
	senses.bind(store)
	wmn.bind(store)
	hud.bind(store, qwen, mnn, wmn)
	hud.set_senses(senses)
	hud.set_creature(creature)
	creature.bind(store)
	creature.set_senses(senses)

	hud.set_who(_identity_name())
	wmn.start(hud.who())

	mnn.token.connect(_on_token)
	mnn.done.connect(_on_done)

	_ticker = Timer.new()
	_ticker.name = "Ticker"
	_ticker.wait_time = _period_s()
	_ticker.autostart = true
	_ticker.timeout.connect(_on_tick)
	add_child(_ticker)

	_boot_line = "hexy base: mnn=%s mesh=%s senses=%d" % [
		"yes" if mnn.available() else "no",
		"lan" if wmn.force_lan else "nearby",
		senses.machine.size() + senses.human.size(),
	]
	print(_boot_line)


## The line printed at boot, for a test to read back.
func boot_line() -> String:
	return _boot_line


## The ticker's period, in seconds, taken from the one place it lives.
func _period_s() -> float:
	return maxf(0.001, float(senses.period_ms) / 1000.0)


func _on_period_changed(_ms: int) -> void:
	if _ticker != null:
		_ticker.wait_time = _period_s()


func _on_tick() -> void:
	senses.tick(wmn.now_ms(), senses.telemetry_from_input())


func _on_token(_t: String) -> void:
	creature.set_thinking(true)


func _on_done(_text: String) -> void:
	creature.set_thinking(false)


## A name for this phone. The sheet can change it later; this is only the one
## it wakes up with, and a machine with no user name is still somebody.
static func _identity_name() -> String:
	var n: String = OS.get_environment("HEXY_WHO").strip_edges()
	if n != "":
		return n
	n = String(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
	return n if n != "" else "hexy"
