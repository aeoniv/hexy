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
## THE ORACLE: the phone's raw accelerometer, gyro and light, filtered into
## the sample the fly brain eats sixty times a second. The sixteen senses elect
## trigrams at the ticker's pace; the oracle feeds the organism every frame.
## Without it the fly is built and never fed: the radar stands still, the
## ball never turns its head, and the habit memory never sees a context.
var oracle: SensorOracle = null
var creature: Creature = null
## THE MIC: Android's own recogniser on the phone, a mock everywhere else.
var mic: Mic = null
## THE COMPASS, AND IT IS GODOT'S OWN. `Input.get_magnetometer()` and
## `Input.get_gravity()` are engine API: base, no plugin, no door. Headless and
## on a phone with no magnetometer this node simply never goes live, and the
## radar draws the allocentric disc it drew before. GPS is NOT here and will not
## be: a position is a future add-on's gift, handed in through
## `Heading.set_fix()`.
var heading: Heading = null
## THE SURFACE IS THE FRONT GLASS: one sentence, one room, one composer. The
## third glass is still on disk and still the page a finger opens by tapping
## the creature -- the front instantiates it itself, once, and parks it over
## the room -- but the app mounts the FRONT and nothing else. One glass child,
## one bind, and every page beyond the dials is somebody else's signal to
## answer. scripts/glass/glass.gd and scripts/glass/hud_bridge.gd both stay on
## disk, and the import wall still keeps them honest, but nothing boots them.
var front: Front = null

## THE ALCHEMY, LOADED RATHER THAN NAMED. It belongs to the core and the core
## may land after the glass does; naming the class outright would stop the
## whole app from parsing on a tree where the file is not there yet, and an app
## that cannot boot teaches nobody anything. When it is on disk it is built,
## bound and ticked; when it is not, the body simply does not walk.
const ALCHEMY_PATH: String = "res://scripts/core/alchemy.gd"

var alchemy: Node = null

## THE ADD-ONS, IF ANY ARE ON DISK. The loader scans
## `res://addons/hexy_*/addon.gd` and nothing in base names one, so a phone
## built without them boots exactly the same app with an empty doors panel.
var addons: HexyAddons = null

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

	oracle = SensorOracle.new()
	oracle.name = "Oracle"
	add_child(oracle)

	mic = Mic.new()
	mic.name = "Mic"
	add_child(mic)

	heading = Heading.new()
	heading.name = "Heading"
	add_child(heading)

	front = Front.new()
	front.name = "Hud"
	add_child(front)

	creature = Creature.new()
	creature.name = "Creature"

	qwen.bind(store, mnn)
	senses.bind(store)
	oracle.bind(store)
	wmn.bind(store)
	if alchemy != null and alchemy.has_method("bind"):
		alchemy.bind(store, senses)

	## THE SIX OBJECTS, IN ONE CALL. The front takes what the third glass took
	## in four calls -- store, mnn, wmn, senses, alchemy, qwen -- and hands the
	## same six on to the dials page when a finger asks for it.
	front.bind(store, mnn, wmn, senses, alchemy, qwen)
	front.set_creature(creature)
	## THE GLASS MAY NOT HAVE ITS MIC BUTTON YET. The core node is built either
	## way, because the test that walks the mock does not need a surface, and an
	## app that will not boot against a slightly older glass teaches nobody.
	if front.has_method("set_mic"):
		front.set_mic(mic)
	if front.has_method("set_heading"):
		front.set_heading(heading)
	creature.bind(store)
	creature.set_senses(senses)

	front.set_who(_identity_name())
	wmn.start(front.who())

	## THE ADD-ONS, LAST, AFTER EVERY CORE OBJECT IS BOUND. An add-on may only
	## write through the seat bus, the homeostat and the registry, so it must
	## find all three already standing. One call; the loader does the rest.
	addons = HexyAddons.new()
	addons.name = "Addons"
	add_child(addons)
	addons.load_all(store, {
		"store": store,
		"character": store.get_character(),
		"alchemy": alchemy,
	})
	if front.has_method("set_addons"):
		front.set_addons(addons)

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
	if OS.is_debug_build():
		_fly_lamp()


## A LAMP ON THE FLY'S FEED, debug builds only and printed nowhere else. It
## answers the four questions a logcat cannot otherwise answer: which profile
## the phone resolved to, whether the oracle exists, whether the glass and the
## oracle hold the SAME character, and whether the radar is standing where a
## frame can reach it. Then it reads the two sensors out loud five times, so a
## phone that delivers nothing says so instead of looking still.
func _fly_lamp() -> void:
	var prof: Dictionary = DeviceProfile.resolve()
	var dial: Control = front.radar_dial()
	print("hexy fly: profile=%s view=%s oracle=%s hud_char=%d oracle_char=%d radar=%s/%s" % [
		String(prof.get("id", "?")), str(DisplayServer.window_get_size()),
		"yes" if oracle != null else "no",
		front._store.get_character().get_instance_id() if front._store != null else -1,
		oracle.store.get_character().get_instance_id() if oracle.store != null else -1,
		front.radar_layout(), "fed" if dial != null and dial.is_visible_in_tree() else "cold"])
	## THE INPUTS THE PROFILE WAS RESOLVED FROM, said out loud, because a lamp
	## that names the answer and not the question cannot tell a wrong table
	## from a wrong measurement.
	var view: Vector2i = prof.get("resolved_viewport", Vector2i(1, 1))
	print("hexy ram: ram=%d aspect=%.3f os=%s layout=%s lane=%s" % [
		int(prof.get("resolved_ram_bytes", -1)),
		float(view.y) / maxf(1.0, float(view.x)),
		String(prof.get("resolved_os_name", "?")),
		String(prof.get("layout", "?")), String(prof.get("chat_lane", "?"))])
	## WHICH MODELS THIS PHONE MAY CARRY, and why not the others. Asked of the
	## same gate the list and the load path ask, so a logcat and the Brain
	## panel can never tell two different stories.
	if mnn != null and mnn.has_method("tier_lamp_line"):
		print(mnn.tier_lamp_line())
	for _i in 5:
		await get_tree().create_timer(2.0).timeout
		print("hexy fly: gyro=%s grav=%s" % [str(Input.get_gyroscope()), str(Input.get_gravity())])


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
	## THE HOMEOSTAT DECAYS ON THE SAME CLOCK. Needs fall, the conductance
	## matrix couples them, and lines open or close; the oracle feeds the fly
	## between these ticks, this is the metabolic beat.
	var ch: Variant = store.get_character()
	if ch != null and ch.has_method("tick"):
		ch.tick(now)
	if alchemy != null and alchemy.has_method("tick"):
		alchemy.tick(now)
	## AND THE GLASS BEATS ON THE SAME CLOCK. One call: the front pushes the
	## room into the radar, samples the day, and composes its one sentence.
	if front != null:
		front.beat()


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
