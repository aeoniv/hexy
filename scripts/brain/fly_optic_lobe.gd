class_name FlyOpticLobe
extends RefCounted

## N6 -- THE OPTIC LOBE. lamina -> medulla -> lobula, in that order and in one
## file, because that is the order a photon takes through a fly's head.
##
## BASE_V1 lists vision as the one ffbrain circuit that was never built: the
## compound_eye Sense reached the mushroom body as a number and nothing ever
## asked what it MEANT. A fly's eye does not report brightness; it reports
## CHANGE, and two things fall out of change alone -- which way the world is
## sliding past, and whether something is growing in front of the face.
##
## THE CHAIN, WHOLE:
##   lamina   L1/L2: temporal high-pass per cell. A cell's slow baseline is an
##            EMA over LAMINA_TAU_SEC; what the medulla sees is the cell minus
##            its own baseline, so a frame that never changes is a frame with
##            nothing in it.
##   medulla  Hassenstein-Reichardt elementary motion detectors between
##            NEIGHBOURING cells: one arm delayed by exactly one frame,
##            multiplied against its undelayed neighbour, and the mirror pair
##            subtracted. Positive is rightward (or downward); the whole field
##            averaged gives (vx, vy), the optic flow.
##   lobula   LPLC2: an expanding flow field is a thing coming at the face. The
##            divergence -- outward flow on both sides of the midline -- is the
##            looming signal, and looming that is BOTH large and still rising
##            is the only thing that drives an escape.
##
## HEURISTIC-FREE: no tuned magic beyond the two named constants below. The
## EMD responses are normalised by the frame's own contrast energy, so a dim
## scene and a bright scene of the same motion give the same flow.
##
## ONE STATE, ONE FRAME DEEP: the previous high-passed frame and three EMAs.
## Everything else on this object is a pure function of the frame handed in.
##
## WHAT THE EYE CARRIES TODAY: `HexySenses.sample_posture` publishes
## compound_eye as a SINGLE 0..1 scalar (the camera's upright/slumped reading
## from ixbody), so the live path is the 1-D, one-cell case: with no second
## cell there is no neighbour to correlate against, no flow, and the looming
## channel falls back to the lamina's own rising edge -- a thing approaching
## the one photoreceptor there is fills it. The N-cell grid path below is the
## same arithmetic and runs the moment a real luminance frame arrives.

## THE LAMINA'S ADAPTATION TIME, IN SECONDS. How long a cell takes to forget a
## steady light and go quiet again; a change slower than this is not a change.
const LAMINA_TAU_SEC: float = 0.25

## THE LOBULA'S ESCAPE THRESHOLD, DIMENSIONLESS (normalised divergence, on the
## population scale the medulla writes on: a coherent full-field slide of one
## cell per frame reads a few tenths, and this is the lower half of that).
## Below it, an expanding field is the world going by; above it, and still
## rising, it is something arriving. Twice this is a full-strength escape.
const LOOM_THRESHOLD: float = 0.12

## Guard against dividing by the contrast energy of a black frame.
const _EPS: float = 1e-6

## -- what the lobula says, read after every step ------------------------------
## Optic flow, dimensionless, ~-1..1. Positive vx = world sliding rightward.
var vx: float = 0.0
var vy: float = 0.0
## Instantaneous divergence of the flow field (outward-positive).
var expansion: float = 0.0
## The lobula's smoothed looming, 0..1.
var looming: float = 0.0
## LPLC2's output: 0..1, non-zero only while looming is over threshold AND
## still growing.
var startle_drive: float = 0.0

var _baseline: PackedFloat32Array = PackedFloat32Array()
var _hp_prev: PackedFloat32Array = PackedFloat32Array()
var _width: int = 0
var _last_looming: float = 0.0
var _seen: bool = false


## WHICH WAY THE WORLD MOVES, as a signed angle in radians (-PI/2..PI/2).
## Sign follows vx: a world drifting left reads negative.
func drift_rad() -> float:
	return asin(clampf(vx, -1.0, 1.0))


## ONE FRAME. `frame` may be an Array/PackedFloat*Array of luminance cells, a
## dict carrying one under "v"/"cells"/"grid" (with an optional "w"/"width"
## for a 2-D grid), or a bare number -- the one-cell case the live
## compound_eye Sense actually is.
func step(dt_sec: float, frame: Variant, width: int = -1) -> void:
	var dt: float = maxf(dt_sec, 0.0001)
	var cells: PackedFloat32Array = read_frame(frame)
	var n: int = cells.size()
	if n == 0:
		_decay(dt)
		return
	var w: int = width if width > 0 else _frame_width(frame, n)
	if _baseline.size() != n:
		_baseline = cells.duplicate()
		_hp_prev = PackedFloat32Array()
		_hp_prev.resize(n)
		_hp_prev.fill(0.0)
		_width = w
		_seen = false
	_width = w

	# 1. LAMINA -- temporal high-pass per cell.
	var alpha: float = clampf(dt / LAMINA_TAU_SEC, 0.0, 1.0)
	var hp: PackedFloat32Array = PackedFloat32Array()
	hp.resize(n)
	var energy: float = 0.0
	for i in range(n):
		_baseline[i] = _baseline[i] + (cells[i] - _baseline[i]) * alpha
		hp[i] = cells[i] - _baseline[i]
		energy += hp[i] * hp[i]
	energy = energy / float(n)

	if not _seen:
		_hp_prev = hp
		_seen = true
		_decay(dt)
		return

	# 2. MEDULLA -- Reichardt correlators over every neighbouring pair.
	##
	## CONTRAST NORMALISATION. A Reichardt response is a product of two
	## contrasts, so on its own it says as much about how bright the scene is
	## as about how far it moved. Every response is divided by the frame's own
	## mean contrast energy, which makes it a direction rather than a
	## brightness -- and the divisor is measured off the frame in hand, not
	## chosen by anybody. What comes out is a POPULATION mean over pairs: a
	## coherent slide of the whole field reads a few tenths, an incoherent one
	## reads nothing, and the lobula's threshold below is written on that same
	## scale.
	var norm: float = energy + _EPS
	var h: int = n / maxi(w, 1)
	var sum_x: float = 0.0
	var count_x: int = 0
	var sum_y: float = 0.0
	var count_y: int = 0
	var div: float = 0.0
	var count_d: int = 0
	var cx: float = float(w - 1) * 0.5
	var cy: float = float(h - 1) * 0.5
	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			if x + 1 < w:
				var j: int = i + 1
				var r: float = emd(hp[i], _hp_prev[i], hp[j], _hp_prev[j]) / norm
				sum_x += r
				count_x += 1
				## Outward from the midline is expansion: leftward flow on the
				## left half and rightward flow on the right half both count
				## positive, which is the divergence of the flow field.
				div += r * signf((float(x) + 0.5) - cx)
				count_d += 1
			if y + 1 < h:
				var k: int = i + w
				var rv: float = emd(hp[i], _hp_prev[i], hp[k], _hp_prev[k]) / norm
				sum_y += rv
				count_y += 1
				div += rv * signf((float(y) + 0.5) - cy)
				count_d += 1
	_hp_prev = hp

	vx = clampf(sum_x / float(count_x), -1.0, 1.0) if count_x > 0 else 0.0
	vy = clampf(sum_y / float(count_y), -1.0, 1.0) if count_y > 0 else 0.0

	# 3. LOBULA -- looming out of the divergence.
	if count_d > 0:
		expansion = clampf(div / float(count_d), -1.0, 1.0)
	else:
		## THE ONE-CELL EYE. With no neighbour there is no flow field and so no
		## divergence; what is left is the lamina itself. A single cell whose
		## light is RISING is a cell something is filling, which is the only
		## looming a one-pixel eye can report.
		expansion = clampf(hp[0] / (absf(_baseline[0]) + _EPS), -1.0, 1.0)
		vx = 0.0
		vy = 0.0

	_last_looming = looming
	var target: float = maxf(expansion, 0.0)
	looming = clampf(looming + (target - looming) * alpha, 0.0, 1.0)
	startle_drive = lplc2(looming, _last_looming)


## THE REICHARDT CORRELATOR, PURE. `a` is the earlier cell along the axis,
## `b` its neighbour; each arm is multiplied against the OTHER arm's previous
## frame and the mirror pair subtracted. Positive = motion from a toward b.
static func emd(a_now: float, a_prev: float, b_now: float, b_prev: float) -> float:
	return a_prev * b_now - a_now * b_prev


## LPLC2, PURE. Looming that is over threshold and still rising, mapped 0..1.
## A looming that has stopped growing is a thing that has stopped coming.
static func lplc2(now: float, previous: float) -> float:
	if now <= LOOM_THRESHOLD or now <= previous:
		return 0.0
	return clampf((now - LOOM_THRESHOLD) / LOOM_THRESHOLD, 0.0, 1.0)


## Luminance cells out of whatever shape the Sense came in.
static func read_frame(frame: Variant) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var src: Variant = frame
	if typeof(src) == TYPE_DICTIONARY:
		var d: Dictionary = src
		for key in ["v", "cells", "grid", "frame"]:
			if d.has(key):
				src = d[key]
				break
	if typeof(src) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY,
			TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY]:
		for f in src:
			out.append(float(f))
	elif typeof(src) in [TYPE_INT, TYPE_FLOAT]:
		out.append(float(src))
	return out


static func _frame_width(frame: Variant, n: int) -> int:
	if typeof(frame) == TYPE_DICTIONARY:
		var d: Dictionary = frame
		for key in ["w", "width"]:
			if d.has(key):
				var w: int = int(d[key])
				if w > 0 and n % w == 0:
					return w
	return n


## No frame this tick: everything relaxes on the lamina's own time constant,
## so a stale eye goes quiet rather than holding an old startle.
func _decay(dt_sec: float) -> void:
	var alpha: float = clampf(dt_sec / LAMINA_TAU_SEC, 0.0, 1.0)
	vx = lerpf(vx, 0.0, alpha)
	vy = lerpf(vy, 0.0, alpha)
	expansion = lerpf(expansion, 0.0, alpha)
	_last_looming = looming
	looming = lerpf(looming, 0.0, alpha)
	startle_drive = 0.0


## A fresh eye, remembering no frame.
func reset() -> void:
	_baseline = PackedFloat32Array()
	_hp_prev = PackedFloat32Array()
	_width = 0
	_seen = false
	vx = 0.0
	vy = 0.0
	expansion = 0.0
	looming = 0.0
	_last_looming = 0.0
	startle_drive = 0.0
