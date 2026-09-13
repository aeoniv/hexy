class_name Sense
extends RefCounted

## ONE SENSE, ONE READING, ONE SENTENCE.
##
## A sense is a pure reader. It is handed a plain telemetry Dictionary every
## tick and answers three things: whether it was sensed at all, how strongly
## (0..1, smoothed), and one short ASCII line a person can read. It never
## touches the glass, never touches a plugin, never reaches for Input. That is
## the host's job; a sense only ever sees the Dictionary it is given.
##
## MISSING KEYS ARE NOT ZEROS. A sense whose telemetry keys are absent is NOT
## PRESENT, scores exactly 0.0 and says "not sensed". A zero reading and an
## absent sensor are different facts and the election must never confuse them.
##
## SMOOTHING LIVES HERE, ONCE. Every subclass returns a raw 0..1 number that is
## a pure function of (telemetry, its own rolling state). The exponential mean
## is applied above it so no subclass can get the filter subtly wrong, and so
## every rule stays testable by calling it with a hand-built Dictionary.
##
## THE FIRST SAMPLE SEEDS THE MEAN rather than dragging it up from zero: a
## sense that has just been switched on has no history to be loyal to, and a
## first reading damped to 0.3 of itself would be a lie about the world.

const MACHINE: int = 0
const HUMAN: int = 1

## Trigram names by index, ASCII, the order both families share.
const TRIGRAMS: Array[String] = [
	"Earth", "Thunder", "Water", "Lake",
	"Mountain", "Fire", "Wind", "Heaven",
]

## The exponential mean's weight on the newest reading.
const ALPHA: float = 0.3

## What a sense says when its telemetry is not there at all and it cannot
## name what it would need.
const NOT_SENSED: String = "not sensed"

## Below this score the sense is present but says NO. A sense that is being
## read and is reading nothing must describe the negative state: "day, screen
## on" is a reading, "night, dark and still" printed over an empty bar is a
## lie the bar cannot shout down.
const LOW_SCORE: float = 0.15

## Windowed senses never read zero on their first tick: the window is a
## confirmation, not a precondition. base * (FLOOR + RISE * dwell_fraction).
const WINDOW_FLOOR: float = 0.7
const WINDOW_RISE: float = 0.3

var _family: int = MACHINE
var _index: int = 0
var _label: String = ""

## True for senses that read something a person must permit (place, mic, face).
var _needs_consent: bool = false

## What this sense would need in order to be sensed at all: a plugin name
## ("ixvoice", "ixbody", "ixloc", "android battery") or a piece of hardware.
## "not sensed" and "needs ixbody" are different facts: one says the reading
## failed, the other says the reading was never wired.
var _needs: String = ""

var _present: bool = false
var _raw: float = 0.0
var _ema: float = 0.0
var _seeded: bool = false
var _consent: String = "none"
var _since_ms: int = -1


func _init(p_family: int = MACHINE, p_index: int = 0, p_label: String = "") -> void:
	_family = p_family
	_index = clampi(p_index, 0, 7)
	_label = p_label


# -- the contract ------------------------------------------------------------

func family() -> int:
	return _family


func index() -> int:
	return _index


func label() -> String:
	return _label


func trigram_name() -> String:
	return TRIGRAMS[_index]


func present() -> bool:
	return _present


func score() -> float:
	if not _present:
		return 0.0
	return clampf(_ema, 0.0, 1.0)


## What this sense would need to be sensed at all. "" when nothing is missing
## that can be named.
func needs() -> String:
	return _needs


func sentence() -> String:
	if not _present:
		if _needs == "":
			return NOT_SENSED
		return "needs %s" % _needs
	return _say(score())


func tools() -> Array:
	return []


func consent() -> String:
	return _consent


## One reading. `telemetry` is whatever the host could fill this tick.
func tick(now_ms: int, telemetry: Dictionary) -> void:
	var ok: bool = _has(telemetry)
	if _needs_consent:
		_consent = "granted" if ok else "asked"
	if not ok:
		_present = false
		_raw = 0.0
		_ema = 0.0
		_seeded = false
		_since_ms = -1
		_forget()
		return
	_present = true
	_raw = clampf(_read(now_ms, telemetry), 0.0, 1.0)
	if _seeded:
		_ema += ALPHA * (_raw - _ema)
	else:
		_ema = _raw
		_seeded = true


## Forget everything learned, including the smoothed mean.
func reset() -> void:
	_present = false
	_raw = 0.0
	_ema = 0.0
	_seeded = false
	_since_ms = -1
	_consent = "none"
	_forget()


# -- what a subclass answers -------------------------------------------------

## Whether this sense's telemetry keys are there at all.
func _has(_t: Dictionary) -> bool:
	return false


## The raw 0..1 reading. Pure in (telemetry, own rolling state).
func _read(_now_ms: int, _t: Dictionary) -> float:
	return 0.0


## The line, picked by the score. A subclass answers two sentences and never
## chooses between them: the gate lives here so no sense can forget it.
## ASCII, 60 characters or fewer, both of them.
func _say(p_score: float) -> String:
	if p_score < LOW_SCORE:
		return _low()
	return _high()


## The line when this sense reads YES.
func _high() -> String:
	return ""


## The line when this sense is present and reads NO.
func _low() -> String:
	return _high()


## Drop rolling state when the sense goes absent.
func _forget() -> void:
	pass


# -- helpers every sense shares ----------------------------------------------

static func num(t: Dictionary, key: String, fallback: float = 0.0) -> float:
	if not t.has(key):
		return fallback
	return float(t[key])


static func flag(t: Dictionary, key: String, fallback: bool = false) -> bool:
	if not t.has(key):
		return fallback
	return bool(t[key])


static func vec(t: Dictionary, key: String) -> Vector3:
	if not t.has(key):
		return Vector3.ZERO
	var v: Variant = t[key]
	if v is Vector3:
		return v as Vector3
	return Vector3.ZERO


static func has_vec(t: Dictionary, key: String) -> bool:
	return t.has(key) and (t[key] is Vector3)


## 1.0 at `peak`, falling to 0.0 `width` either side. A band, not a threshold:
## "small but not still" is a range and reads as one.
static func band(x: float, peak: float, width: float) -> float:
	if width <= 0.0:
		return 0.0
	return clampf(1.0 - absf(x - peak) / width, 0.0, 1.0)


## A ramp from `lo` (0.0) to `hi` (1.0).
static func ramp(x: float, lo: float, hi: float) -> float:
	if hi <= lo:
		return 0.0
	return clampf((x - lo) / (hi - lo), 0.0, 1.0)


## How much of `window_ms` this condition has held without a break, 0..1.
## The clock only starts on the tick the condition first holds.
func _dwell(now_ms: int, active: bool, window_ms: int) -> float:
	if not active:
		_since_ms = -1
		return 0.0
	if _since_ms < 0:
		_since_ms = now_ms
		return 0.0
	return clampf(float(now_ms - _since_ms) / float(maxi(1, window_ms)), 0.0, 1.0)


## Minutes the current dwell has run, for a sentence to quote.
func _dwell_minutes(now_ms: int) -> int:
	if _since_ms < 0:
		return 0
	return int(float(now_ms - _since_ms) / 60000.0)


## A base reading confirmed, not gated, by its window.
static func windowed(base: float, dwell_fraction: float) -> float:
	return base * (WINDOW_FLOOR + WINDOW_RISE * clampf(dwell_fraction, 0.0, 1.0))
