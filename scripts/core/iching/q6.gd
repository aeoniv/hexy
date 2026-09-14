class_name Q6Core
extends RefCounted

## THE SIX-BIT CUBE, ONE IMPLEMENTATION, SEEN FROM GODOT.
##
## The arithmetic of Q6 -- 64 hexagrams as the corners of the six-dimensional
## hypercube, a mass p[64] moved by heat along the edges and pulled back by a
## six-line bias -- now lives in ONE place per platform:
##
##   ON DEVICE   android_plugin/ixmnn/src/main/cpp/q6/q6.cpp, inside the ixmnn
##               plugin, beside the Qwen decode loop that reads it as a prior.
##   ON DESKTOP  scripts/core/iching/q6_lattice.gd, untouched, called from the
##               fallback below.
##
## Those two are held to each other by tests/golden/q6_golden.json: the golden
## file is generated from the GDScript, tests/q6_core.gd checks the client
## against it, and tests/native/q6_test.cpp checks the C++ against the same
## numbers. Neither side may drift without a suite going red.
##
## THE STATE IS ONE STATE. It is the thing that chooses which line of the BODY
## figure flips (Pacing), the prior the decode loop reads every token (the
## native side), and the point in R^32 a figure cloud is (embed). One object,
## three readers.
##
## THE NATIVE LEASE. There is exactly one Q6 in the native plugin, so exactly
## one Q6Core may speak to it: the first instance built takes the lease and
## every later one runs the desktop arithmetic. Pacing is built first and holds
## it. `is_native()` says which side any given object is on, and both sides
## answer the same numbers, so nothing upstream has to branch.

const Lattice := preload("res://scripts/core/iching/q6_lattice.gd")

const LINES: int = 6
const STATES: int = 64
const EMBED_DIM: int = 32

## Pacing's constants, carried here so the cube owns its own defaults and the
## native side can be handed the same numbers.
const DEFAULT_BETA: float = 2.5
const ANCHOR: float = 0.5
const TIE_EPSILON: float = 1e-9

## Nobody holds the native lease until somebody asks for it.
static var _lease_taken: bool = false

## THE WARM-STATE STAMP. Every write of the figure words, and every cast that
## lands in the body, moves this number on. The native decode loop is handed it
## with each prompt (`chat_at`, `chat_stream_at`) and refuses to answer from a
## kv-cache that was warmed under an older cube: a stale answer is worse than a
## slow one, because it is a reading of a figure the body has already left.
## STATIC, and bumped on the pure path too, so a Q6Core.new(false) on desktop
## is testable against the same counter the phone uses.
static var _cast_version: int = 0

var _p: PackedFloat64Array = Lattice.delta(0)
var _native: bool = false
var _plugin: Object = null


func _init(want_native: bool = true) -> void:
	if want_native and not _lease_taken:
		var p: Object = _singleton()
		if p != null:
			_plugin = p
			_native = true
			_lease_taken = true
			_plugin.call("q6_reset", 0)
			_send_figure_words()


## The IxMnn singleton, but only when it actually carries the cube. A plugin
## built before this file existed answers nothing, and that is not an error.
static func _singleton() -> Object:
	if not Engine.has_singleton("IxMnn"):
		return null
	var p: Object = Engine.get_singleton("IxMnn")
	if p == null or not p.has_method("q6_state"):
		return null
	return p


## True when this object's arithmetic is happening in C++ inside ixmnn.
func is_native() -> bool:
	return _native


# --- the warm-state stamp ---------------------------------------------------

## What the cube is stamped at right now. Never decreases.
static func cast_version() -> int:
	return _cast_version


## Move the stamp on and hand back the new value, so a caller may push it into
## the same native call that made the state stale.
static func bump_cast_version() -> int:
	_cast_version += 1
	return _cast_version


## HOW OFTEN THE DECODE LOOP REACHED FOR A FIGURE WORD THE CUBE NO LONGER
## STANDS ON -- the native side's own count of prompts it had to re-warm.
## 0 on desktop, where there is no decode loop to be wrong.
static func prior_mismatches() -> int:
	var p: Object = _singleton()
	if p == null or not p.has_method("q6_prior_mismatches"):
		return 0
	return int(p.call("q6_prior_mismatches"))


## The stamp the NATIVE side last saw with its figure words. -1 off device, and
## -1 on a plugin built before the stamp existed; a gap against cast_version()
## is the honest signal that a push did not land.
static func native_figure_version() -> int:
	var p: Object = _singleton()
	if p == null or not p.has_method("q6_figure_version"):
		return -1
	return int(p.call("q6_figure_version"))


# --- moving the mass --------------------------------------------------------

## All the mass on one corner.
func reset(bits: int) -> void:
	if _native:
		_plugin.call("q6_reset", bits & 63)
		return
	_p = Lattice.delta(bits)


## Same thing, said the way a cast says it.
func inject(bits: int) -> void:
	if _native:
		_plugin.call("q6_inject", bits & 63)
		return
	_p = Lattice.delta(bits)


## Mass spread evenly over all 64 corners.
func uniform() -> void:
	if _native:
		_plugin.call("q6_uniform")
		return
	_p = Lattice.uniform()


## THE BODY'S OWN CORNER PUT BACK UNDER THE CLOUD. The mass is where the body
## STANDS, not a forecast of where it ends up; without this the Gibbs reweight
## piles every grain on the target and the six neighbours all read zero.
func anchor(bits: int, amount: float = ANCHOR) -> void:
	if _native:
		_plugin.call("q6_anchor", bits & 63, amount)
		return
	for h in range(STATES):
		_p[h] = _p[h] * (1.0 - amount)
	_p[bits & 63] += amount


## DIFFUSE, THEN LISTEN: one heat step of time `t` along the edges of the cube,
## then the Gibbs pull exp(beta * U) toward the corners the six lines agree
## with, renormalised to sum 1.
func step(bias: PackedFloat64Array, t: float, beta: float = DEFAULT_BETA) -> void:
	if _native:
		var f: PackedFloat32Array = PackedFloat32Array()
		f.resize(LINES)
		for i in range(LINES):
			f[i] = float(bias[i]) if i < bias.size() else 0.0
		_plugin.call("q6_step", f, t, beta)
		return
	_p = Lattice.step(_p, bias, t, beta)


# --- reading it -------------------------------------------------------------

## The whole 64-vector. On the native side this crosses JNI, so read it once.
func state() -> PackedFloat64Array:
	if not _native:
		return _p.duplicate()
	var raw: Variant = _plugin.call("q6_state")
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(STATES)
	if raw is PackedFloat32Array:
		var arr: PackedFloat32Array = raw
		for h in range(STATES):
			out[h] = float(arr[h]) if h < arr.size() else 0.0
	return out


## The mass on one corner.
func at(bits: int) -> float:
	if not _native:
		return _p[bits & 63]
	return state()[bits & 63]


## Overwrite the whole state. Only for a caller restoring a saved cloud.
func set_state(p: PackedFloat64Array) -> void:
	if p.size() != STATES:
		return
	if _native:
		var f: PackedFloat32Array = PackedFloat32Array()
		f.resize(STATES)
		for h in range(STATES):
			f[h] = float(p[h])
		_plugin.call("q6_set_state", f)
		return
	_p = p.duplicate()


## The corner holding the most mass. Ties go to the lowest index.
func argmax() -> int:
	if _native:
		return int(_plugin.call("q6_argmax"))
	return Lattice.argmax(_p)


## Normalised Shannon entropy in [0, 1]. 1 has nothing to say.
func tension() -> float:
	if _native:
		return float(_plugin.call("q6_tension"))
	return Lattice.tension(_p)


## THE NEXT FIGURE IS A NEIGHBOUR, never a jump: of the six corners one line
## from `bits`, the LINE INDEX of the one holding the most mass. The tie test
## is relative, because at a large beta all six sit around 1e-68 and an
## absolute epsilon would call every pair of them equal.
func best_neighbour(bits: int) -> int:
	if _native:
		return int(_plugin.call("q6_best_neighbour", bits & 63))
	var b: int = bits & 63
	var top: float = 0.0
	for i in range(LINES):
		top = maxf(top, _p[b ^ (1 << i)])
	if top <= 0.0:
		return 0
	var floor_mass: float = top * (1.0 - TIE_EPSILON)
	for i in range(LINES):
		if _p[b ^ (1 << i)] >= floor_mass:
			return i
	return 0


## A FIGURE CLOUD AS A POINT IN R^32, learned by nothing.
##
## Run the unnormalised FWHT over p, walk k from 0 to 63 in ASCENDING k, keep
## every k whose popcount is 3 or less, take the first 32 of those. 42 of the
## 64 indices qualify and the cut falls at k = 37, so the 32 kept are, by
## popcount, 1 + 6 + 13 + 12.
##
## k = 0 is the total mass, so out[0] is 1 for any normalised state. The rest
## are the cube's own low-frequency harmonics. This is `Q6::embed` in q6.cpp,
## number for number, and tests/golden/q6_golden.json holds them to it.
func embed() -> PackedFloat32Array:
	if _native:
		var raw: Variant = _plugin.call("q6_embed")
		if raw is PackedFloat32Array:
			return raw
		return _zeros()
	var c: PackedFloat64Array = Lattice.fwht(_p)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(EMBED_DIM)
	var n: int = 0
	for k in range(STATES):
		if n >= EMBED_DIM:
			break
		if Lattice.popcount(k) <= 3:
			out[n] = float(c[k])
			n += 1
	while n < EMBED_DIM:
		out[n] = 0.0
		n += 1
	return out


static func _zeros() -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(EMBED_DIM)
	out.fill(0.0)
	return out


# --- the prior the decode loop reads ----------------------------------------

## HOW HARD QWEN HEARS THE CUBE. 0 is the old behaviour exactly: the decode
## loop runs MNN's own `response()` and no logit is touched. Above 0 the
## native side runs its own decode loop and adds `w * p[h] * 64` to the logit
## of the first token of each of the 64 King Wen figure words, so the figure
## the cube is standing on is the figure Qwen reaches for first.
## STATIC, and deliberately so: the weight is a property of the ONE decode loop
## inside the plugin, not of whichever client happens to hold the native lease,
## so a reader like Mnn.info() can ask without taking the lease off Pacing.
static func set_prior_weight(w: float) -> void:
	var p: Object = _singleton()
	if p != null:
		p.call("q6_set_prior_weight", w)


## THE MANUAL DOOR ONTO THE PRIOR. Two hands may set the weight and only one at
## a time: when `prior.follows_stillness` is on, Alchemy drives it from the
## body's own stillness and tension and this call stands down; when it is off,
## the number in the drawer IS the weight, clamped to `prior.max` so a slider
## left at the top cannot deafen the decode loop. HexyConfig calls this on
## every `prior.*` write.
static func apply_manual_prior(weight: float, ceiling: float,
		follows_stillness: bool) -> bool:
	if follows_stillness:
		return false
	set_prior_weight(clampf(weight, 0.0, maxf(0.0, ceiling)))
	return true


## What the decode loop is currently doing with the cube. 0 on desktop, always:
## there is no decode loop there to lean on.
static func prior_weight() -> float:
	var p: Object = _singleton()
	if p == null:
		return 0.0
	return float(p.call("q6_prior_weight"))


## THE 64 WORDS THE PRIOR LEANS ON, indexed by hexagram bits, taken straight
## from KingWen so the native side keeps no second copy of that table. ASCII
## pinyin, because a token id is what is wanted and the tokenizer is Qwen's.
##
## THESE WORDS ARE METADATA, NEVER MASS. They are the vocabulary the prior
## projects onto -- a naming of the 64 seats, not a weight on any of them. No
## word ever moves the cube: Pacing is the one and only writer of cube mass
## (reset, inject, step, flip), and this call must stay side-effect free on it.
func _send_figure_words() -> void:
	if not _native:
		return
	var words: PackedStringArray = PackedStringArray()
	words.resize(STATES)
	for h in range(STATES):
		words[h] = KingWen.pinyin(h)
	_plugin.call("q6_set_figure_words", words, bump_cast_version())


## The six numbers a figure asks the cube for, as Pacing reads them: lines 0..2
## are the machine's (lower) trigram, 3..5 the human's, each scaled by how sure
## that election was.
static func bias_of(target_bits: int, machine_margin: float,
		human_margin: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(LINES)
	var m: float = clampf(machine_margin, 0.0, 1.0)
	var h: float = clampf(human_margin, 0.0, 1.0)
	for i in range(LINES):
		var sign: float = 1.0 if ((target_bits >> i) & 1) == 1 else -1.0
		out[i] = sign * (m if i < 3 else h)
	return out


static func popcount(k: int) -> int:
	return Lattice.popcount(k)
