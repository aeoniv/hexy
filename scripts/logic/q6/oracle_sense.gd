class_name OracleSense
extends RefCounted

## N12 step 1 — hexagram_from_window. Six channels are six lines, a window is
## a hexagram, a channel that moved is a moving line. Pure measurement: never
## touches score(), teach() or the reward path.
##
## window: {length: T, channels: C (<=6 used), sd_floor: {i: float},
##          circular: {i: scale-to-radians}, band?: int}
##   (or `manifest` — then sd_floor / circular come from the injected
##   `manifest_reader`, see below.)
## values / prev: channel-major, values[c * T + t] (dtw_ruler layout).
## state: caller-held; this writes state["median"][i] (EMA running median).
## Line i = bit i (0-based, line 1 = bit 0, core order).

const DtwRuler = preload("res://scripts/logic/q6/dtw_ruler.gd")

## THE MANIFEST READER, HANDED IN. Q6 is pure: it loads nothing outside
## scripts/logic/q6/, so it does not load the brain's FlySkillMemory to turn a
## skill_window channel manifest into sd_floor / circular. Whoever owns that
## (the brain/senses side) hands in an object -- the FlySkillMemory script
## itself will do -- answering `sd_floor_from_manifest(manifest) -> Dictionary`
## and `circular_map_from_manifest(manifest) -> Dictionary`. A window that
## carries its own sd_floor / circular never asks it. Null -- the default -- is
## "no reader": a manifest-only window gets {} for both, i.e. SD_FLOOR_DEFAULT
## on every channel and no circular channel.
static var manifest_reader: Object = null

const LINES: int = 6
const EMA_ALPHA: float = 0.1
const SD_FLOOR_DEFAULT: float = 0.1
const BAND_FRACTION: float = 0.1


static func cast(window: Dictionary, values: PackedFloat32Array, prev: PackedFloat32Array,
		state: Dictionary) -> Dictionary:
	var t_len: int = int(window.get("length", 0))
	var manifest: Array = window.get("manifest", []) as Array
	var c_all: int = int(window.get("channels", manifest.size()))
	if t_len <= 0 and c_all > 0:
		t_len = int(round(float(values.size()) / float(c_all)))
	var c: int = mini(LINES, c_all)
	var sd_floor: Dictionary = window.get("sd_floor", _from_manifest("sd_floor_from_manifest", manifest)) as Dictionary
	var circular: Dictionary = window.get("circular", _from_manifest("circular_map_from_manifest", manifest)) as Dictionary
	var band: int = int(window.get("band", maxi(1, int(round(BAND_FRACTION * float(t_len))))))
	var median: Dictionary = state.get("median", {}) as Dictionary
	var have_prev: bool = prev.size() >= c_all * t_len and t_len > 0

	var lines: int = 0
	var moving: int = 0
	var present: Array[int] = []
	for i in c:
		present.append(i)
		var ch := values.slice(i * t_len, (i + 1) * t_len)
		var scale: float = float(circular.get(i, 0.0))
		var m: float = _circ_mean(ch, scale) if scale > 0.0 else _mean(ch)
		var med: float = float(median.get(i, m))
		var dev: float = _wrap(m - med, scale) if scale > 0.0 else m - med
		if dev >= 0.0:
			lines |= 1 << i
		median[i] = med + EMA_ALPHA * dev
		if have_prev:
			var p := prev.slice(i * t_len, (i + 1) * t_len)
			if scale > 0.0:  # angular metric: prev unwrapped onto ch, in radians
				var a := PackedFloat32Array()
				var b := PackedFloat32Array()
				a.resize(t_len)
				b.resize(t_len)
				for t in t_len:
					a[t] = ch[t] * scale
					b[t] = a[t] + _wrap((p[t] - ch[t]) * scale, 1.0)
				ch = a
				p = b
			var d: float = DtwRuler.dtw_distance(ch, p, 1, t_len, band) / float(t_len)
			if d > 2.0 * float(sd_floor.get(i, SD_FLOOR_DEFAULT)):
				moving |= 1 << i
	state["median"] = median

	# Thin: fewer than six channels — copy the nearest present line (no T yet).
	var thin: bool = c < LINES
	if thin and not present.is_empty():
		for i in range(c, LINES):
			var src: int = present[present.size() - 1]  # nearest present = last one below
			if (lines >> src) & 1 == 1:
				lines |= 1 << i
	var n_moving: int = 0
	for i in LINES:
		n_moving += (moving >> i) & 1
	var novelty: float = float(n_moving) / float(maxi(1, c))
	return {"h": lines, "king_wen": KingWen.number(lines), "lines": lines, "moving": moving,
		"novelty": novelty, "thin": thin}


## Ask the injected manifest reader, or {} when none was handed in.
static func _from_manifest(method: String, manifest: Array) -> Dictionary:
	if manifest_reader == null:
		return {}
	var out: Variant = manifest_reader.call(method, manifest)
	return out as Dictionary if out is Dictionary else {}


static func _mean(x: PackedFloat32Array) -> float:
	if x.is_empty():
		return 0.0
	var s: float = 0.0
	for v in x:
		s += v
	return s / float(x.size())


## Angular mean, returned in the channel's own units.
static func _circ_mean(x: PackedFloat32Array, scale: float) -> float:
	var sx: float = 0.0
	var sy: float = 0.0
	for v in x:
		sx += cos(v * scale)
		sy += sin(v * scale)
	return atan2(sy, sx) / scale


## Wrap a difference into (-period/2, period/2], period = TAU / scale.
static func _wrap(d: float, scale: float) -> float:
	var period: float = TAU / scale
	return fposmod(d + 0.5 * period, period) - 0.5 * period
