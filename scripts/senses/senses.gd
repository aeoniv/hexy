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
## is a strobe. Each family has its own Lattice: a challenger must lead for two
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

## How often the sixteen are read, when the host ticks faster than this.
@export var period_ms: int = 3500

var machine: Array[Sense] = ([] as Array[Sense])
var human: Array[Sense] = ([] as Array[Sense])

var machine_lattice: Lattice = null
var human_lattice: Lattice = null

var _store: HexyStore = null
var _last_tick_ms: int = -1
var _prev_bits: int = -1


func _init() -> void:
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
	machine_lattice = Lattice.new(0)
	human_lattice = Lattice.new(0)


func bind(store: HexyStore) -> void:
	_store = store


## One reading of everything. Returns true when the sixteen actually ran; a
## call that arrives before `period_ms` has passed is a no-op, so a host may
## call this every frame without thinking about it.
func tick(now_ms: int, telemetry: Dictionary) -> bool:
	if _last_tick_ms >= 0 and (now_ms - _last_tick_ms) < period_ms:
		return false
	_last_tick_ms = now_ms

	for s in machine:
		s.tick(now_ms, telemetry)
	for s in human:
		s.tick(now_ms, telemetry)

	var m_scores: Array[float] = _scores_of(machine)
	var h_scores: Array[float] = _scores_of(human)

	var m_win: int = machine_lattice.push(m_scores)
	var h_win: int = human_lattice.push(h_scores)

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

	if _tap_is_fresh(now_ms):
		return true

	# The election is already decided; the one-hot arrays hand Cast the LATTICE
	# winners rather than the raw argmax it would find for itself, so the
	# debounce is not quietly undone one line after it was applied.
	var cast: Dictionary = Cast.sense_cast(
		_one_hot(m_win), _one_hot(h_win), _prev_bits)
	var bits: int = int(cast.get("bits", 0)) & 63
	_store.set_hexagram({
		"bits": bits,
		"moving": int(cast.get("moving", 0)),
		"throws": cast.get("throws", []),
		"when": now_ms,
		"who": "",
		"source": "senses",
		"sig": "",
	})
	_prev_bits = bits
	return true


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

	if OS.has_method("get_power_percent_left"):
		var pct: int = int(OS.call("get_power_percent_left"))
		if pct >= 0:
			t["battery_pct"] = float(pct)

	if DisplayServer.has_method("window_get_mode"):
		var mode: int = int(DisplayServer.window_get_mode(0))
		t["screen_on"] = mode != DisplayServer.WINDOW_MODE_MINIMIZED

	return t
