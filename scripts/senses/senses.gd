class_name Senses
extends Node

## THE SIXTEEN, AND THE TWO ELECTIONS THEY HOLD.
##
## Eight machine senses elect the lower trigram, eight human senses elect the
## upper, and together they are a figure. This node owns the sixteen, runs them
## on one clock, and writes the result through the store. It owns no sensors:
## everything arrives as one plain telemetry Dictionary, which is why the whole
## engine can be driven from a test with no device attached.
##
## THE DEBOUNCE IS NOT OPTIONAL. A raw argmax over sixteen noisy readings
## changes its mind constantly, and a figure that flickers is not a reading, it
## is a strobe. Each family has its own Debounce: a challenger must lead for two
## consecutive ticks before it may take the seat. So the one-tick spike that
## every real sensor produces never reaches the glass.
##
## THE TAP OUTRANKS THE SENSES, AND ONLY THE FIGURE. When a person has thrown
## coins in the last five minutes, that figure is theirs and the senses do not
## overwrite it -- but the machine and human lines keep updating underneath,
## because the room is still the room and the body is still the body. Silencing
## those too would be the senses sulking, and there is nothing to be gained by
## telling a person less than is true.
##
## NO PLUGIN LIVES HERE. `telemetry_from_input` reads only what Godot itself
## offers. A host with an Android plugin merges its readings into the same
## Dictionary before calling [tick]; this node cannot tell the difference and
## must not be able to.

## How long a tap's figure is protected from the senses.
const TAP_HOLD_MS: int = 300000

## Announced whenever [member period_ms] changes, so the host's clock can
## follow the one number that decides it instead of keeping a copy.
signal period_changed(ms: int)

## How often the sixteen are read, when the host ticks faster than this. This
## is the ONLY place the period lives: the app reads it for its ticker and
## listens to [signal period_changed] to follow it.
@export var period_ms: int = 3500:
	set(value):
		var v: int = maxi(1, value)
		if v == period_ms:
			return
		period_ms = v
		period_changed.emit(v)

var machine: Array[Sense] = ([] as Array[Sense])
var human: Array[Sense] = ([] as Array[Sense])

## The member names are the old ones on purpose; only the type moved.
var machine_lattice: Debounce = null
var human_lattice: Debounce = null

var _store: HexyStore = null
var _last_tick_ms: int = -1
var _prev_bits: int = -1

## The figure the senses are asking for: (human << 3) | machine.
var _target: int = 0
## Smoothed body motion, kept from tick to tick. An ABSENT telemetry key means
## no change, never an invented zero: a phone with no gyroscope is not a phone
## lying perfectly still.
var _filtered_jerk: float = 0.0
var _gyro_len: float = 0.0
## How far each family's seated winner leads its nearest rival, 0..1. A wide
## margin is an election nobody is arguing about.
var _machine_margin: float = 0.0
var _human_margin: float = 0.0
## Kinetic excitation, 0..1: it rises while the flux is above 0.25 and decays
## otherwise. Ported from SensorOracle._update_habit_line_strains.
var _excitation: float = 0.0

## Whether the app has the screen. THE ONLY HONEST ANSWER GODOT HAS: there is
## no engine API for "is the display lit", and DisplayServer.window_get_mode
## answers MODE_FULLSCREEN on Android whether the phone is on a desk face down
## or in a hand -- which is how a face-up A22 came to be called deep work.
## Focus is the thing the engine really knows: the window loses it when the
## screen goes off, when the app is backgrounded, and when another app comes
## forward, and all three mean the same thing to a sense. It starts true
## because an app that is running has just been looked at.
var _focused: bool = true


func _init() -> void:
	# THE BEAT, from the drawer when there is one. `peek` and not `instance`:
	# a Senses built in a test that never asked for a config keeps its 3500.
	var cfg: HexyConfig = HexyConfig.peek()
	if cfg != null:
		period_ms = int(cfg.get_value("senses.period_ms"))
		if not cfg.changed.is_connected(_on_config_changed):
			cfg.changed.connect(_on_config_changed)
	machine = ([
		SenseSanctuary.new(),
		SenseThermal.new(),
		SenseBattery.new(),
		SenseAcoustic.new(),
		SenseDeskRest.new(),
		SenseLight.new(),
		SenseGeomagnetic.new(),
		SenseCircadian.new(),
	] as Array[Sense])
	human = ([
		SenseSleep.new(),
		SenseLocomotion.new(),
		SenseHydration.new(),
		SenseGrip.new(),
		SenseDeepWork.new(),
		SenseGaze.new(),
		SenseBreath.new(),
		SensePosture.new(),
	] as Array[Sense])
	machine_lattice = Debounce.new(0)
	human_lattice = Debounce.new(0)


## The screen, tracked rather than guessed. These two notifications reach every
## Node in the tree, so a Senses that was added to the tree is told; one built
## bare in a test is not, and reads as focused, which is what a test wants.
## The one key Senses owns. Everything else in the drawer is somebody else's.
func _on_config_changed(key: String, value: Variant) -> void:
	if key == "senses.period_ms":
		period_ms = int(value)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false


## Whether the host believes the glass is lit. Tests may set this by hand.
func screen_on() -> bool:
	return _focused


func set_screen_on(on: bool) -> void:
	_focused = on


func bind(store: HexyStore) -> void:
	_store = store


## One reading of everything. Returns true when the sixteen actually ran; a
## call that arrives before `period_ms` has passed is a no-op, so a host may
## call this every frame without thinking about it.
func tick(now_ms: int, telemetry: Dictionary) -> bool:
	var delta_s: float = 0.0
	if _last_tick_ms >= 0:
		if (now_ms - _last_tick_ms) < period_ms:
			return false
		delta_s = minf(1.0, float(now_ms - _last_tick_ms) / 1000.0)
	_last_tick_ms = now_ms
	_update_motion(delta_s, telemetry)

	for s in machine:
		s.tick(now_ms, telemetry)
	for s in human:
		s.tick(now_ms, telemetry)

	var m_scores: Array[float] = _scores_of(machine)
	var h_scores: Array[float] = _scores_of(human)

	var m_win: int = machine_lattice.push(m_scores)
	var h_win: int = human_lattice.push(h_scores)
	_target = ((h_win << 3) | m_win) & 63
	_machine_margin = _margin_of(m_scores, m_win)
	_human_margin = _margin_of(h_scores, h_win)

	if _store == null:
		return true

	_store.set_machine({
		"trigram": m_win,
		"score": machine[m_win].score(),
		"sentence": machine[m_win].sentence(),
	})
	_store.set_human({
		"trigram": h_win,
		"score": human[h_win].score(),
		"sentence": human[h_win].sentence(),
	})

	# THE SENSES NO LONGER WRITE THE FIGURE. They elect two trigrams and stop;
	# Alchemy alone turns the body's lines, one at a time, at the pace the fire
	# allows. A sense that wrote the whole figure would jump six lines at once.
	_prev_bits = _target
	return true


# -- what the body is doing, for the fire ------------------------------------

## The figure the two elections are asking for: (human << 3) | machine.
func target_bits() -> int:
	return _target & 63


## How far the machine's seated trigram leads the runner-up, 0..1.
func machine_margin() -> float:
	return _machine_margin


## How far the human's seated trigram leads the runner-up, 0..1.
func human_margin() -> float:
	return _human_margin


## The lead of the seat-holder over the best of the rest, clamped to 0..1. The
## seat-holder is not always the leader -- the debounce may still be holding a
## challenger off -- and a seat being out-scored is a margin of nothing.
static func _margin_of(scores: Array[float], seat: int) -> float:
	if scores.is_empty() or seat < 0 or seat >= scores.size():
		return 0.0
	var rival: float = -1.0
	for i in range(scores.size()):
		if i != seat and scores[i] > rival:
			rival = scores[i]
	return clampf(scores[seat] - rival, 0.0, 1.0)


## How still the body is, 0..1. One is a phone on a table; zero is a walk.
func stillness() -> float:
	return clampf(1.0 - (_filtered_jerk / 1.6 + _gyro_len / 1.2), 0.0, 1.0)


## How shaken the body is, 0..1. At MARTIAL_THRESHOLD the martial fire takes a
## line whether the stillness ever came or not.
func excitation() -> float:
	return clampf(_excitation, 0.0, 1.0)


## The motion filter. Jerk is the accelerometer minus gravity -- what is left
## after the planet has been subtracted is what the person did.
func _update_motion(delta_s: float, telemetry: Dictionary) -> void:
	if telemetry.has("accel"):
		var acc: Vector3 = telemetry["accel"]
		var grav: Vector3 = telemetry.get("gravity", Vector3.ZERO)
		var jerk: float = (acc - grav).length()
		_filtered_jerk = lerpf(_filtered_jerk, jerk, clampf(delta_s * 3.0, 0.05, 1.0))
	if telemetry.has("gyro"):
		var gyro: Vector3 = telemetry["gyro"]
		_gyro_len = lerpf(_gyro_len, gyro.length(), clampf(delta_s * 4.0, 0.05, 1.0))
	var flux: float = (clampf(_filtered_jerk / 6.0, 0.0, 1.0)
		+ clampf(_gyro_len / 2.0, 0.0, 1.0)) * 0.4
	if flux > 0.25:
		_excitation = minf(1.0, _excitation + flux * delta_s * 0.45)
	else:
		_excitation = maxf(0.0, _excitation - delta_s * 0.40)


## Whether a person's own cast still holds the figure.
func _tap_is_fresh(now_ms: int) -> bool:
	if _store == null:
		return false
	var h: Dictionary = _store.hexagram
	if String(h.get("source", "")) != "tap":
		return false
	var when: int = int(h.get("when", 0))
	if when <= 0:
		return false
	return (now_ms - when) < TAP_HOLD_MS


# -- reading the sixteen -----------------------------------------------------

func scores() -> Dictionary:
	return {"machine": _scores_of(machine), "human": _scores_of(human)}


func sentences() -> Dictionary:
	var m: Array[String] = ([] as Array[String])
	var h: Array[String] = ([] as Array[String])
	for s in machine:
		m.append(s.sentence())
	for s in human:
		h.append(s.sentence())
	return {"machine": m, "human": h}


## Every tool the sixteen offer, each id once, in family then index order.
func tools() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for s in machine + human:
		for tool in s.tools():
			var id: String = String((tool as Dictionary).get("id", ""))
			if id == "" or seen.has(id):
				continue
			seen[id] = true
			out.append(tool)
	return out


func sense(p_family: int, p_index: int) -> Sense:
	var row: Array[Sense] = human if p_family == Sense.HUMAN else machine
	return row[clampi(p_index, 0, 7)]


func reset() -> void:
	for s in machine + human:
		s.reset()
	machine_lattice.reset(0)
	human_lattice.reset(0)
	_last_tick_ms = -1
	_prev_bits = -1
	_target = 0
	_filtered_jerk = 0.0
	_gyro_len = 0.0
	_excitation = 0.0
	_machine_margin = 0.0
	_human_margin = 0.0


static func _scores_of(row: Array[Sense]) -> Array[float]:
	var out: Array[float] = ([] as Array[float])
	for s in row:
		out.append(s.score())
	return out


static func _one_hot(index: int) -> Array[float]:
	var out: Array[float] = ([] as Array[float])
	for i in range(8):
		out.append(1.0 if i == index else 0.0)
	return out


# -- what Godot alone can tell us --------------------------------------------

## Everything the engine itself offers, and nothing it does not. A key that
## would be a guess is LEFT OUT: an absent sensor and a zero reading are
## different facts, and only the absence is honest here.
func telemetry_from_input() -> Dictionary:
	var t: Dictionary = {}

	var acc: Vector3 = Input.get_accelerometer()
	if acc.length_squared() > 0.01:
		t["accel"] = acc
	var grav: Vector3 = Input.get_gravity()
	if grav.length_squared() > 0.01:
		t["gravity"] = grav
	var gyro: Vector3 = Input.get_gyroscope()
	if gyro.length_squared() > 0.000001:
		t["gyro"] = gyro
	var mag: Vector3 = Input.get_magnetometer()
	if mag.length_squared() > 0.01:
		t["magnet"] = mag
		t["heading_deg"] = fposmod(rad_to_deg(atan2(-mag.x, -mag.y)), 360.0)

	var clock: Dictionary = Time.get_time_dict_from_system()
	t["local_hour"] = float(clock.get("hour", 12)) + float(clock.get("minute", 0)) / 60.0
	t["offset_ms"] = 0.0

	# BATTERY IS NOT IN THE ENGINE. Godot 4 removed OS.get_power_percent_left
	# and offers nothing in its place, so the key is LEFT OUT and the battery
	# and thermal senses say "needs android battery" rather than inventing a
	# hundred per cent. The guard stays in case a host patches one in.
	if OS.has_method("get_power_percent_left"):
		var pct: int = int(OS.call("get_power_percent_left"))
		if pct >= 0:
			t["battery_pct"] = float(pct)

	t["screen_on"] = _focused

	return t
