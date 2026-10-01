class_name OracleRig
extends RefCounted

## N12 §4 wake + §5 ask gate over OracleSense + OracleTendency.
## One step per window. Never on a clock: wake and ask are driven only by
## what the windows contain.
##
## BUS: Broker (scripts/core/broker.gd) is a resource lock (take/release/
## steal + `noted`), not a pub/sub bus — it has no publish(). Adding one would
## couple a sensing layer to device ownership, so the rig emits `cast(result)`
## instead; the result already carries the `oracle_cast` payload (kind, bits,
## novelty, surprise, wake, t_ns). Whoever owns the bus forwards it.
##
## WARM-UP: an empty tendency row always gives surprise ln(64) = 4.16 > 3.0,
## so a freshly booted still phone would wake on its 2nd window. Wake only
## counts once the table holds WARMUP transitions (an expectation exists).

signal cast(result: Dictionary)

const OracleSense = preload("res://scripts/logic/q6/oracle_sense.gd")
const OracleTendency = preload("res://scripts/logic/q6/oracle_tendency.gd")

const WAKE_SURPRISE: float = 3.0
const WAKE_RUN: int = 2
const ASK_MOVING: int = 3
const ASK_RISES: int = 3
const WARMUP: int = 8

var state: Dictionary = {}
var tendency: OracleTendency
var prev_values := PackedFloat32Array()
var prev_h: int = -1
var prev_novelty: float = 0.0
var rises: int = 0
var hot_run: int = 0
var asked_last: bool = false
var observed: int = 0
## Slow novelty EMA over windows (~64), for tendency_stats(); -1 until the first.
const NOVELTY_EMA: float = 1.0 / 64.0
var novelty_mean: float = -1.0


## N15 §4 / N12 §7 -- READ-ONLY tendency statistics, in one bundle:
## {days, regularity_mean, novelty_mean, dawn_cast_days_ago,
##  surprise_falling_weeks, week_means}. `days` and the ring are stamped by
## OracleTendency.observe() as step() feeds it; nothing here is a clock.
func tendency_stats() -> Dictionary:
	var out: Dictionary = tendency.stats()
	out["novelty_mean"] = maxf(0.0, novelty_mean)
	return out


func _init(t: OracleTendency = null) -> void:
	tendency = t if t != null else OracleTendency.new()


func step(window: Dictionary, values: PackedFloat32Array, hour: int, now_ms: int) -> Dictionary:
	var r: Dictionary = OracleSense.cast(window, values, prev_values, state)
	prev_values = values.duplicate()
	var h: int = int(r["h"])
	var moving: int = int(r["moving"])
	var novelty: float = float(r["novelty"])
	novelty_mean = novelty if novelty_mean < 0.0 else lerpf(novelty_mean, novelty, NOVELTY_EMA)

	var surprise: float = 0.0
	if prev_h >= 0:
		surprise = tendency.surprise(prev_h, h)
		tendency.observe(prev_h, h, hour)
		observed += 1
	prev_h = h

	# §4 wake: surprise > 3 two windows running; fires once on the edge.
	var hot: bool = observed > WARMUP and surprise > WAKE_SURPRISE
	hot_run = hot_run + 1 if hot else 0
	var wake: bool = hot_run == WAKE_RUN

	# §5 ask: |M| >= 3, novelty rising 3 windows, not asked last window.
	rises = rises + 1 if novelty > prev_novelty else 0
	prev_novelty = novelty
	var ask: bool = _popcount(moving) >= ASK_MOVING and rises >= ASK_RISES and not asked_last
	asked_last = ask

	var out := {"kind": "oracle_cast", "h": h, "king_wen": r["king_wen"], "lines": r["lines"],
		"moving": moving, "bits": (moving << 6) | (h & 63), "novelty": novelty,
		"surprise": surprise, "forecast": tendency.forecast(h, 3), "wake": wake, "ask": ask,
		"t_ns": now_ms * 1000000}
	cast.emit(out)
	return out


static func _popcount(x: int) -> int:
	var n := 0
	while x != 0:
		n += x & 1
		x >>= 1
	return n
