extends SceneTree

## ORACLE SENSE SMOKE — scripts/core/iching/oracle_sense.gd (N12 step 1).
##   1. a flat window casts the same H twice with no moving lines
##   2. a step on channel 2 moves exactly line 2 (0-based bit 2)
##   3. a circular channel shifted by a full turn moves nothing
##   4. a thin window (<6 channels) is flagged and filled
## Prints === ALL PASS === or fails.

const OracleSense = preload("res://scripts/logic/q6/oracle_sense.gd")
const T: int = 32

var _fails: int = 0


func _init() -> void:
	_flat()
	_step()
	_circular()
	_thin()
	print("\n=== ALL PASS ===" if _fails == 0 else "\n=== %d FAIL ===" % _fails)
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _win(c: int) -> Dictionary:
	var floor := {}
	for i in c:
		floor[i] = 0.1
	return {"length": T, "channels": c, "sd_floor": floor, "circular": {}}


func _fill(c: int, levels: Array) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(c * T)
	for i in c:
		for t in T:
			v[i * T + t] = float(levels[i])
	return v


func _flat() -> void:
	print("\n- flat window")
	var w := _win(6)
	var st := {}
	var v := _fill(6, [0, 0, 0, 0, 0, 0])
	var a := OracleSense.cast(w, v, PackedFloat32Array(), st)
	var b := OracleSense.cast(w, v, v, st)
	_check(int(a["h"]) == int(b["h"]), "same H twice (%d)" % int(a["h"]))
	_check(int(b["moving"]) == 0 and float(b["novelty"]) == 0.0, "no moving lines")
	_check(not bool(b["thin"]), "six channels is not thin")


func _step() -> void:
	print("\n- step on channel 2")
	var w := _win(6)
	var st := {}
	var prev := _fill(6, [0, 0, 0, 0, 0, 0])
	var v := prev.duplicate()
	for t in range(T / 2, T):
		v[2 * T + t] = 5.0
	OracleSense.cast(w, prev, PackedFloat32Array(), st)
	var r := OracleSense.cast(w, v, prev, st)
	_check(int(r["moving"]) == 1 << 2, "moving == line 2 only (%d)" % int(r["moving"]))
	_check(is_equal_approx(float(r["novelty"]), 1.0 / 6.0), "novelty 1/6")


func _circular() -> void:
	print("\n- circular channel, full-turn shift")
	var w := _win(6)
	w["circular"] = {0: 1.0}
	var st := {}
	var prev := _fill(6, [1, 1, 1, 1, 1, 1])
	var v := prev.duplicate()
	for t in T:
		v[t] = 1.0 + TAU
	OracleSense.cast(w, prev, PackedFloat32Array(), st)
	var r := OracleSense.cast(w, v, prev, st)
	_check(int(r["moving"]) == 0, "nothing moves (%d)" % int(r["moving"]))
	var w2 := _win(6)
	var r2 := OracleSense.cast(w2, v, prev, {})
	_check(int(r2["moving"]) == 1, "control: same shift on a linear channel moves line 0")


func _thin() -> void:
	print("\n- thin window")
	var r := OracleSense.cast(_win(3), _fill(3, [0, 0, 0]), PackedFloat32Array(), {})
	_check(bool(r["thin"]), "3 channels flagged thin")
	_check(int(r["lines"]) == 63, "missing lines copy nearest present (%d)" % int(r["lines"]))
