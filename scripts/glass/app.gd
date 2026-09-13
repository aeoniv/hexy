class_name HexyApp
extends Node

## THE ROOT, AND THE ONLY PLACE THE PARTS MEET.
##
## Seven objects, built once, wired once, and never again referred to by each
## other by name: store, mnn, qwen, wmn, senses, creature, hud. Every one of
## them is handed its neighbours through a bind() and nothing reaches sideways
## for a singleton. That is why the import wall test can be short.
##
## THE ALCHEMY IS THE EIGHTH OBJECT, AND IT IS NOT THE GLASS'S. The head and
## the body are two figures now, and the thing that turns one line of the body
## when a person has been still long enough lives in the core beside the senses
## that feed it. The app builds it, binds it, and ticks it right after the
## sixteen, which is the only place it can be ticked without the glass having
## an opinion about pacing.
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
## THE MIC: Android's own recogniser on the phone, a mock everywhere else.
var mic: Mic = null
## The surface is the THIRD GLASS: five bands, three dials, one bubble.
## scripts/glass/glass.gd and scripts/glass/hud_bridge.gd both stay on disk,
## and the import wall still keeps them honest, but nothing boots them.
var hud: Hud3 = null

## THE ALCHEMY, LOADED RATHER THAN NAMED. It belongs to the core and the core
## may land after the glass does; naming the class outright would stop the
## whole app from parsing on a tree where the file is not there yet, and an app
## that cannot boot teaches nobody anything. When it is on disk it is built,
## bound and ticked; when it is not, the body simply does not walk.
const ALCHEMY_PATH: String = "res://scripts/core/alchemy.gd"

var alchemy: Node = null

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

	alchemy = _build_alchemy()
	if alchemy != null:
		alchemy.name = "Alchemy"
		add_child(alchemy)

	mic = Mic.new()
	mic.name = "Mic"
	add_child(mic)

	hud = Hud3.new()
	hud.name = "Hud"
	add_child(hud)

	creature = Creature.new()
	creature.name = "Creature"

	qwen.bind(store, mnn)
	senses.bind(store)
	wmn.bind(store)
	if alchemy != null and alchemy.has_method("bind"):
		alchemy.bind(store, senses)

	hud.bind(store, qwen, mnn, wmn)
	hud.set_senses(senses)
	hud.set_creature(creature)
	hud.set_alchemy(alchemy)
	## THE GLASS MAY NOT HAVE ITS MIC BUTTON YET. The core node is built either
	## way, because the test that walks the mock does not need a surface, and an
	## app that will not boot against a slightly older glass teaches nobody.
	if hud.has_method("set_mic"):
		hud.set_mic(mic)
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
	var now: int = wmn.now_ms()
	senses.tick(now, senses.telemetry_from_input())
	if alchemy != null and alchemy.has_method("tick"):
		alchemy.tick(now)


## The alchemy, if the core has landed. One load, no stub, no substitute.
static func _build_alchemy() -> Node:
	if not ResourceLoader.exists(ALCHEMY_PATH):
		return null
	var script: Script = load(ALCHEMY_PATH) as Script
	return (script.new() as Node) if script != null else null


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
