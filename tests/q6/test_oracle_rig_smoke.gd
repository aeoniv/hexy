extends SceneTree

## ORACLE RIG SMOKE — scripts/core/iching/oracle_rig.gd (N12 §4 wake, §5 ask).
##   1. still phone, 50 flat windows: never asks, never wakes
##   2. phone picked up (3+ channels, growing over 3 windows): asks exactly once
##   3. surprise spike two windows running: wake exactly once
##   4. forecast has <= 3 entries
## Prints === ALL PASS === or fails.

const OracleRig = preload("res://scripts/logic/q6/oracle_rig.gd")
const OracleTendency = preload("res://scripts/logic/q6/oracle_tendency.gd")
const T: int = 16

var _fails: int = 0


func _init() -> void:
	_still()
	_picked_up()
	_spike()
	_stats()
	print("\n=== ALL PASS ===" if _fails == 0 else "\n=== %d FAIL ===" % _fails)
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _rig() -> OracleRig:
	return OracleRig.new(OracleTendency.new("user://oracle/_smoke_rig.json"))


func _win() -> Dictionary:
	var floor := {}
	for i in 6:
		floor[i] = 0.1
	return {"length": T, "channels": 6, "sd_floor": floor, "circular": {}}


func _fill(levels: Array) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(6 * T)
	for i in 6:
		for t in T:
			v[i * T + t] = float(levels[i])
	return v


func _still() -> void:
	print("\n- still phone, 50 windows")
	var rig := _rig()
	var asks := 0
	var wakes := 0
	var fc_ok := true
	for k in 50:
		var r := rig.step(_win(), _fill([0, 0, 0, 0, 0, 0]), 12, k * 1000)
		asks += int(r["ask"])
		wakes += int(r["wake"])
		fc_ok = fc_ok and (r["forecast"] as Array).size() <= 3
	_check(asks == 0, "never asks (%d)" % asks)
	_check(wakes == 0, "never wakes (%d)" % wakes)
	_check(fc_ok, "forecast <= 3 entries")


func _picked_up() -> void:
	print("\n- phone picked up")
	var rig := _rig()
	var seq: Array = []
	for k in 10:
		seq.append([0, 0, 0, 0, 0, 0])
	seq.append([1, 0, 0, 0, 0, 0])   # 1 moving
	seq.append([2, 1, 1, 0, 0, 0])   # 3 moving
	seq.append([3, 2, 2, 1, 0, 0])   # 4 moving -> rises 3, ask
	seq.append([4, 3, 3, 2, 1, 0])   # 5 moving, asked last -> no
	for k in 10:
		seq.append([4, 3, 3, 2, 1, 0])  # held still
	var asks := 0
	var at := -1
	for k in seq.size():
		var r := rig.step(_win(), _fill(seq[k]), 12, k * 1000)
		if r["ask"]:
			asks += 1
			at = k
	_check(asks == 1, "asks exactly once (%d, at window %d)" % [asks, at])


func _spike() -> void:
	print("\n- surprise spike")
	var rig := _rig()
	var wakes := 0
	var n := 0
	var surprises: Array = []
	for k in 20:
		wakes += int(rig.step(_win(), _fill([0, 0, 0, 0, 0, 0]), 12, n * 1000)["wake"])
		n += 1
	for lv in [[-5, -5, -5, -5, -5, -5], [5, -5, 5, -5, 5, -5], [-5, 5, -5, 5, -5, 5]]:
		var r := rig.step(_win(), _fill(lv), 12, n * 1000)
		surprises.append(snappedf(float(r["surprise"]), 0.01))
		wakes += int(r["wake"])
		n += 1
	_check(wakes == 1, "wake exactly once (%d), surprises %s" % [wakes, str(surprises)])


## N15 §4: tendency_stats() is read-only and stamps today through observe().
func _stats() -> void:
	print("\n- tendency_stats")
	var rig := _rig()
	var before: Dictionary = rig.tendency_stats()
	_check(int(before["days"]) == 0 and float(before["novelty_mean"]) == 0.0, "fresh rig: 0 days, novelty 0")
	for k in 5:
		rig.step(_win(), _fill([0, 0, 0, 0, 0, 0]), 12, k * 1000)
	var st: Dictionary = rig.tendency_stats()
	_check(int(st["days"]) == 1, "five windows today -> 1 day (%d)" % int(st["days"]))
	_check(rig.tendency.last_day == OracleTendency.today(), "stamped with today's unix day")
	for key in ["regularity_mean", "novelty_mean", "dawn_cast_days_ago", "surprise_falling_weeks", "week_means"]:
		_check(st.has(key), "stats has %s" % key)
	_check(float(st["novelty_mean"]) >= 0.0 and float(st["novelty_mean"]) <= 1.0, "novelty_mean in 0..1")
