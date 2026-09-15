extends SceneTree

## W8f -- GENERATES tests/bag/quiet_day.json and tests/bag/busy_day.json.
##
## A deterministic (seeded) day of senses, coarse-grained at one tick per 60
## simulated seconds (1440 ticks, 24h). Run once, by hand, whenever the bags
## need regenerating:
##
##   "C:/Users/vinic/godot47/Godot_v4.7.1-stable_win64_console.exe" --headless --path . -s tests/bag/make_bags.gd
##
## Not part of the automated suite -- it writes fixtures, it does not check
## anything.

const HexyMsgScript = preload("res://scripts/core/msg.gd")

const TICKS: int = 1440
const DT_MS: int = 60000  # 60s/tick, 1440 ticks = 24h
const PEAK_LUX: float = 10000.0


func _initialize() -> void:
	_make("quiet_day", 1001, {
		"noise_amp": 0.03, "p_imu": 0.02, "p_touch": 0.01, "p_pher": 0.005, "p_word": 0.01,
	})
	_make("busy_day", 2002, {
		"noise_amp": 0.15, "p_imu": 0.15, "p_touch": 0.08, "p_pher": 0.04, "p_word": 0.06,
	})
	print("bags written.")
	quit(0)


func _make(name: String, seed_val: int, p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var senses: Array = []

	for i in range(TICKS):
		var t_ms: int = i * DT_MS
		var t_ns: int = t_ms * 1_000_000
		var hour: float = fmod(float(t_ms) / 3600000.0, 24.0)

		var base: float = _daylight(hour)
		var noise: float = rng.randf_range(-float(p["noise_amp"]), float(p["noise_amp"]))
		var lux: float = clampf(base + noise, 0.0, 1.0) * PEAK_LUX
		senses.append(HexyMsgScript.sense("ocelli", "lux", t_ns, {"lux": snappedf(lux, 0.1)}))

		if rng.randf() < float(p["p_imu"]):
			senses.append(HexyMsgScript.sense("halteres", "imu", t_ns,
				{"mag": snappedf(rng.randf_range(0.1, 1.0), 0.001)}))

		if rng.randf() < float(p["p_touch"]):
			senses.append(HexyMsgScript.sense("tarsi", "touch", t_ns,
				{"line": rng.randi_range(0, 5), "amount": snappedf(rng.randf_range(-0.3, 0.3), 0.001)}))

		if rng.randf() < float(p["p_pher"]):
			senses.append(HexyMsgScript.sense("pheromone", "peer", t_ns,
				{"strength": snappedf(rng.randf_range(0.3, 1.0), 0.001), "solar_hour": snappedf(hour, 0.01)}))

		if rng.randf() < float(p["p_word"]):
			senses.append(HexyMsgScript.sense("words", "speech", t_ns, {"text": "hum"}))

	var out := {
		"version": 1,
		"name": name,
		"dt_ms": DT_MS,
		"tick": TICKS,
		"senses": senses,
	}
	var path: String = "res://tests/bag/%s.json" % name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("%s: %d senses, %d bytes" % [name, senses.size(), FileAccess.get_file_as_bytes(path).size()])


## 0..1 daylight fraction over 24h: near-dark night, a dawn ramp, full day,
## a dusk ramp back down. Same shape a coarse ocelli reading would see.
func _daylight(hour: float) -> float:
	if hour < 5.0 or hour > 21.0:
		return 0.02
	if hour < 7.0:
		return lerpf(0.02, 1.0, (hour - 5.0) / 2.0)
	if hour < 19.0:
		return 1.0
	return lerpf(1.0, 0.02, (hour - 19.0) / 2.0)
