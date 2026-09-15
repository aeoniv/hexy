class_name HexyApp
extends Node

## THE ROOT, AND THE ONLY PLACE THE PARTS MEET.
##
## Seven objects, built once, wired once, and never again referred to by each
## other by name: store, mnn, qwen, wmn, senses, creature, hud. Every one of
## them is handed its neighbours through a bind() and nothing reaches sideways
## for a singleton. That is why the import wall test can be short.
##
## W8e -- THE BUS IS THE EIGHTH OBJECT, AND IT IS THE ONLY WAY THE PARTS MEET.
## One HexyTopic, one HexyGauge, one Broker, one HexySenses, built here and
## handed to everything: the organism subscribes to "/sense" and answers with
## "/body" and "/phase", the store follows "/body", the gauge fits itself
## slowly off "/sense", the add-ons are handed the same four in a bus
## dictionary, and every page of the glass SUBSCRIBES. Nothing on the glass
## writes organism state any more.
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
## answer. The dead glass (glass.gd, hud_bridge.gd, mobile_hud_store.gd) is
## off disk entirely now; the front is the only surface there is.
var front: Front = null

## THE CUBE. W10d deleted alchemy.gd (the old hysteresis shim); all that was
## still consumed of it was the 64-corner Pacing walk, published to the store
## as telemetry for the mesh (`q6_mass`) and a dump (`pacing_state`). The
## body itself has had exactly one writer since W8c -- the homeostat, through
## a Body message -- and stays that way: this cube never writes the store's
## body, only its own bookkeeping.
var _pacing: Pacing = Pacing.new()

## THE ADD-ONS, IF ANY ARE ON DISK. The loader scans
## `res://addons/hexy_*/addon.gd` and nothing in base names one, so a phone
## built without them boots exactly the same app with an empty doors panel.
var addons: HexyAddons = null

## THE ONE TOPIC BUS. Every Sense in, every Body and Phase out.
var topic: HexyTopic = null
## THE ONE GAUGE: this app's whole interpretation layer, on disk as
## user://gauge.json, fitting itself slowly off "/sense" and READ (never
## written) by every page of the glass.
var gauge: HexyGauge = null
## THE ONE BROKER, for the add-ons' doors.
var broker: Broker = null
## THE BASE ORGANS AS SENSE SOURCES: light, IMU, touch, and the aar doors.
var organs: HexySenses = null
## THE OUT HALF OF THE SAME BUS: one subscriber on "/act" that owns the
## speaker, the haptic motor, and the two doors that are no-ops by design.
var acts: HexyActs = null

## THE GAUGE'S TWO THROTTLES. A Sense arrives far faster than a body clock
## moves and far faster than a disk wants writing, so the gauge is fitted at
## most once a minute PER ORGAN and written at most once every five minutes
## (and once more on the way out).
const GAUGE_FIT_EVERY_MS: int = 60_000
const GAUGE_SAVE_EVERY_MS: int = 300_000

var _gauge_fit_at: Dictionary = {}
var _gauge_saved_at_ms: int = 0
var _gauge_dirty: bool = false

var _ticker: Timer = null
var _boot_line: String = ""


func _ready() -> void:
	## THE BUS FIRST. Everything built after this line is handed it, and
	## nothing built after this line reaches sideways for anything else.
	topic = HexyTopic.new()
	gauge = HexyGauge.new()
	gauge.load()
	## The APP owns the disk throttle, not the gauge -- see _on_bus_sense.
	gauge.autosave = false
	broker = Broker.new()
	broker.name = "Broker"
	add_child(broker)

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

	organs = HexySenses.new()
	organs.name = "Organs"
	## THE BROKER GOES IN WITH THE BUS. Every contended read the organs make
	## -- the camera behind IxBody/IxLens, the mic behind IxVoice -- asks the
	## door table first and is abandoned when an add-on already holds it.
	organs.bind(topic, broker)
	add_child(organs)

	acts = HexyActs.new()
	acts.name = "Acts"
	add_child(acts)
	acts.bind(topic, broker)

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
	## THE ORACLE SPEAKS ON THE BUS, not into the organism, and W10a left it
	## with ONE thing to say: its two substrate punishments, as tarsi Senses.
	## The halteres are `organs.poll()`'s alone -- two producers reading the
	## same accelerometer on two clocks was one producer too many.
	oracle.topic = topic
	wmn.bind(store)
	_pacing.reset(store.body_bits())
	if store.has_signal("seat_landed") and not store.seat_landed.is_connected(_on_seat_landed_pacing):
		store.seat_landed.connect(_on_seat_landed_pacing)
	if store.has_signal("restored") and not store.restored.is_connected(_on_restored_pacing):
		store.restored.connect(_on_restored_pacing)

	## THE SIX OBJECTS, IN ONE CALL. The front takes what the third glass took
	## in four calls -- plus the bus and the gauge -- and hands the
	## same six on to the dials page when a finger asks for it. `pressure` is
	## the dead fifth slot since W8e (see front.bind/dashboard.bind).
	front.bind(store, mnn, wmn, senses, null, qwen, topic, gauge)
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

	## EVERY SUBSCRIBER ON THE ONE TOPIC, in the order the traffic flows: the
	## organism takes "/sense" and answers with "/body" and "/phase", the
	## store follows "/body", and the gauge fits itself slowly off "/sense".
	var organism: Variant = store.get_character()
	if organism != null and organism.has_method("attach_bus"):
		organism.attach_bus(topic)
	store.attach_bus(topic)
	## FIX 1: wmn latches /body for the bw wire Body shape and publishes
	## pheromone Senses on receive, but nothing was calling attach_bus on it --
	## it sat on the mesh deaf to the one topic every other part hears.
	if wmn.has_method("attach_bus"):
		wmn.attach_bus(topic)
	topic.subscribe(HexyTopic.TOPIC_SENSE, Callable(self, "_on_bus_sense"))
	## THE TWO ACT PRODUCERS. Both live here rather than in scripts/brain: the
	## brain is canon and owns no doors, so the ROOT -- which already holds
	## every part -- reads the body it publishes and answers with an Act.
	topic.subscribe(HexyTopic.TOPIC_BODY, Callable(self, "_on_bus_body"))
	topic.subscribe(HexyTopic.TOPIC_SENSE, Callable(self, "_on_bus_sense_act"))

	front.set_who(_identity_name())
	wmn.start(front.who())

	## THE ADD-ONS, LAST, AFTER EVERY CORE OBJECT IS BOUND. An add-on may only
	## write through the seat bus, the homeostat and the registry, so it must
	## find all three already standing. One call; the loader does the rest.
	addons = HexyAddons.new()
	addons.name = "Addons"
	add_child(addons)
	addons.load_all({
		"topic": topic,
		"broker": broker,
		"gauge": gauge,
		"consents": Consents,
		"store": store,
	})
	if front.has_method("set_addons"):
		front.set_addons(addons)
	## AND THE BROKER WITH THEM. Panel 10 of the instrument panel names the
	## holder standing on each door, and the only object that knows one is this
	## broker -- built here at boot and, until now, handed to nobody on the glass.
	if front.has_method("set_broker"):
		front.set_broker(broker)

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
	## THE ORGANS ARE POLLED FIRST, so the Senses this beat spends are this
	## beat's. Each door keeps its own rate inside poll(): imu every tick,
	## lux once a second, the aar doors twice a second, touch never (a tap is
	## an event -- see _unhandled_input).
	if organs != null:
		organs.poll(Clock.now_ns())
	senses.tick(now, senses.telemetry_from_input())
	## THE HOMEOSTAT DECAYS ON THE SAME CLOCK. Needs fall, the conductance
	## matrix couples them, and lines open or close; the oracle feeds the fly
	## between these ticks, this is the metabolic beat.
	var ch: Variant = store.get_character()
	if ch != null and ch.has_method("bus_tick"):
		## ONE BEAT OF THE ORGANISM: the needs decay and couple, the fly brain
		## spends what the bus handed it, and a Body and a Phase go out.
		ch.bus_tick(now, _period_s())
	elif ch != null and ch.has_method("tick"):
		ch.tick(now)
	_beat_pacing(now)
	## AND THE GLASS BEATS ON THE SAME CLOCK. One call: the front pushes the
	## room into the radar, samples the day, and composes its one sentence.
	if front != null:
		front.beat()


## ---------------------------------------------------------- the acts ----
##
## TWO PRODUCERS, AND THE ROOT IS BOTH OF THEM. `scripts/brain` is canon and
## owns no doors, so the only place that may read the body and answer with an
## Act is the one object that already holds every part.
##
## THE THROTTLE IS ONE PER TENTH OF A SECOND, PER DOOR. A startle can fire on
## consecutive frames and a swarm can put several conspecifics in phase at
## once; a door that answered every one of them would be a buzz that never
## stops rather than a signal.
const ACT_EVERY_MS: int = 100

var _act_at: Dictionary = {}  # door -> Clock.now_ms() of the last Act sent
var _was_startled: bool = false


## True when `door` may act now; records the stamp when it may.
func _act_due(door: String) -> bool:
	var now: int = Clock.now_ms()
	var last: int = int(_act_at.get(door, -ACT_EVERY_MS - 1))
	if now - last < ACT_EVERY_MS:
		return false
	_act_at[door] = now
	return true


func _send_act(door: String, value, meta: Dictionary = {}) -> bool:
	if topic == null or not _act_due(door):
		return false
	return topic.publish(HexyTopic.TOPIC_ACT, HexyMsg.act(door, Clock.now_ns(), value, meta))


## A BODY WENT OUT, SO THE GIANT FIBER HAS ALREADY FIRED OR NOT FIRED. The
## Body message carries no startle slot of its own (see msg.gd's note on
## `is_startled`), so the flag is read from the state the same tick produced
## -- the message is the CLOCK here, the character is the value.
##
## EDGE, NOT LEVEL. A startle lasts several frames; the buzz is the moment it
## begins.
func _on_bus_body(_msg: Dictionary) -> void:
	var ch: Variant = store.get_character() if store != null else null
	if ch == null or not ch.has_method("get_fly_state"):
		return
	var startled: bool = bool((ch.get_fly_state() as Dictionary).get("is_startled", false))
	if startled and not _was_startled:
		_send_act("haptic", 20, {"why": "giant_fiber"})
	_was_startled = startled


## A CONSPECIFIC, IN PHASE, IS ANSWERED WITH A WING SONG. `in_phase` is the
## peer row's own word (see sentence.gd and the radar) and the only thing that
## separates a fly that happens to be near from one that is keeping the same
## hours.
func _on_bus_sense_act(msg: Dictionary) -> void:
	if String(msg.get("organ", "")) != "pheromone":
		return
	if not bool((msg.get("meta", {}) as Dictionary).get("in_phase", false)):
		return
	_send_act("speaker", HexyActs.SONG_HZ, {"why": "in_phase"})


## A TAP IS AN EVENT, NOT A SAMPLE, so it never rides `organs.poll()`. Only
## what the whole glass left unhandled reaches here: a finger on a dial is
## that dial's business and is consumed long before this.
func _unhandled_input(event: InputEvent) -> void:
	if organs == null:
		return
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	else:
		return
	if not pressed:
		return
	## THE BODY LINE, because a tap on nothing in particular is contact with
	## the creature itself, and a tarsal contact is evidence, not a refill.
	organs.sample_touch(Clock.now_ns(), 0, 0.05)


## ONE BEAT OF THE CUBE. Pacing walks toward the target the senses ask for
## and the store gets the mass and the journal tail, published only -- the
## body itself is never written from here (see `_pacing` above).
func _beat_pacing(now: int) -> void:
	if store == null or senses == null:
		return
	_pacing.tick(now, senses.target_bits(), senses.stillness(),
		senses.excitation(), senses.machine_margin(), senses.human_margin())
	if store.has_method("set_q6_mass"):
		store.set_q6_mass(_pacing.cube.state())
	if store.has_method("set_pacing_state"):
		var tail: Dictionary = {}
		if not _pacing.journal.is_empty():
			tail = (_pacing.journal[_pacing.journal.size() - 1] as Dictionary).duplicate(true)
		store.set_pacing_state(int(_pacing.bits), tail)
	## THE CUBE'S OWN VOLUME KNOB, folded from the deleted alchemy.gd. Off by
	## default (see Q6Core.PRIOR_MAX / prior_weight_for); when `HexyConfig`
	## has `prior.follows_stillness` on, this is the one and only writer.
	var cfg: Object = HexyConfig.peek()
	if cfg != null and cfg.has_method("get_value") and bool(cfg.get_value("prior.follows_stillness")):
		var ceiling: float = float(cfg.get_value("prior.max"))
		var unit: float = Q6Core.prior_weight_for(senses.stillness(), _pacing.cube.tension()) / Q6Core.PRIOR_MAX
		Q6Core.set_prior_weight(clampf(ceiling, 0.0, 1.0) * unit)


## A FIGURE LANDED IN THE BODY SEAT. The cube re-anchors on it and locks both
## fires out for a breath, exactly as a cast always has -- only the body
## itself, which this never touched, is now the homeostat's alone.
func _on_seat_landed_pacing(seat: int, c: Dictionary) -> void:
	if seat != HexyStore.Seat.BODY or store == null:
		return
	_pacing.inject(int(c.get("bits", 0)) & 63, int(c.get("when", 0)))
	if store.has_method("set_q6_mass"):
		store.set_q6_mass(_pacing.cube.state())
	if store.has_method("set_pacing_state"):
		var tail: Dictionary = {}
		if not _pacing.journal.is_empty():
			tail = (_pacing.journal[_pacing.journal.size() - 1] as Dictionary).duplicate(true)
		store.set_pacing_state(int(_pacing.bits), tail)


## THE WHOLE STATE CAME BACK. A restored body is not a body that walked
## there, so the cube re-anchors on it whole rather than left where it stood.
func _on_restored_pacing() -> void:
	if store == null:
		return
	_pacing.reset(store.body_bits(), Clock.now_ms())


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


## ---------------------------------------------------------- the gauge ----

## EVERY SENSE, SEEN BY THE GAUGE, SLOWLY. The bus is the fast path and the
## gauge is the slow one: one fit per organ per minute is already far more
## evidence than a body clock that moves in hours can use, and the file is
## written on a five-minute throttle so a day of sensing is a handful of
## writes rather than a million.
func _on_bus_sense(msg: Dictionary) -> void:
	if gauge == null:
		return
	var organ: String = String(msg.get("organ", ""))
	if organ == "":
		return
	var now: int = Clock.now_ms()
	var last: int = int(_gauge_fit_at.get(organ, 0))
	if last > 0 and now - last < GAUGE_FIT_EVERY_MS:
		return
	_gauge_fit_at[organ] = now
	## THE HOUR AND THE DAY ARE THE HOST'S BUSINESS: the gauge reads no
	## clock of its own, so the app stamps every Sense it forwards.
	var m: Dictionary = (msg.get("meta", {}) as Dictionary).duplicate()
	if not m.has("wall_hour"):
		m["wall_hour"] = _wall_hour()
	if not m.has("day"):
		m["day"] = int(floor(float(Time.get_unix_time_from_system()) / 86400.0))
	var fitted: Dictionary = msg.duplicate()
	fitted["meta"] = m
	gauge.fit(fitted)
	_gauge_dirty = true
	if _gauge_saved_at_ms <= 0 or now - _gauge_saved_at_ms >= GAUGE_SAVE_EVERY_MS:
		save_gauge()


## THE GAUGE, WRITTEN. Called by the throttle above and once more on the way
## out, so a phone killed between two throttle windows still wakes up on the
## clock it went to sleep with.
func save_gauge() -> void:
	if gauge == null or not _gauge_dirty:
		return
	gauge.save()
	_gauge_dirty = false
	_gauge_saved_at_ms = Clock.now_ms()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_gauge()


static func _wall_hour() -> float:
	var t: Dictionary = Time.get_datetime_dict_from_system()
	return float(t.get("hour", 0)) + float(t.get("minute", 0)) / 60.0
