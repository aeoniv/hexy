class_name DtwRuler
extends RefCounted

## THE RULER, never an engine (N8 §9, HEXY.md Dropped, cut 2026-09-23).
## What survives of prototype_dtw.gd: a metric over [C,T] channel-major
## windows (values[c * T + t]), TRAIN-free normalization helpers and one banded
## DTW distance. No fit, no predict, no artifact, no verdict. Users:
## oracle_sense.gd (moving-line ruler, N12 §1) and offline scratch/replay.


## Metric presets are kept by name so a metric dictionary from an old bench or
## dump still builds; the ruler itself is the banded multichannel DTW below.
const METRIC_LEGACY := "zscore_dtw_v1"

const METRIC_DEFAULT := "zscore_dtw_v1"

const METRIC_PRESETS := ["zscore_dtw_v1", "zscore_weighted_v2", "family_rms_v2",
	"family_rms_angular_v2", "family_rms_angular_weighted_v2",
	"family_rms_angular_weighted_deriv_v2", "family_rms_angular_weighted_band20_v2",
	"family_rms_angular_weighted_deriv_band20_v2", "family_rms_angular_weighted_band25_v2"]

## BAND (10) expressed relative to the v1 motion window (T = 100).
const BAND_FRACTION_LEGACY := 0.10

## Equal trust in the level and in the shape of the signal.
const DERIVATIVE_WEIGHT_DEFAULT := 0.5

## Fallback channel names for motion.temporal.v1 when the feature manifest does
## not carry channel metadata. Mirrors LearningMotionCapture.CHANNELS (kept as a
## literal so this engine stays free of any sensor-adapter dependency).
const MOTION_CHANNEL_NAMES := ["linear_accel_x", "linear_accel_y", "linear_accel_z",
	"gyro_x", "gyro_y", "gyro_z", "gravity_unit_x", "gravity_unit_y", "gravity_unit_z"]


## Groups channels into vector families from the feature manifest's `channels`
## metadata (names like "gyro_x"/"gyro_y"/"gyro_z"). Unknown channel metadata
## falls back to one family per channel, i.e. exactly the v1 per-channel
## behaviour, so the engine stays sensor-generic.
static func _families_for(feature_manifest: Dictionary, channels: int) -> Array:
	var names: Array = []
	var names_value: Variant = feature_manifest.get("channels", null)
	if typeof(names_value) == TYPE_ARRAY and (names_value as Array).size() == channels:
		for n in (names_value as Array):
			names.append(String(n))
	elif channels == 9 and String(feature_manifest.get("schema_id", "")).begins_with("motion.temporal"):
		names = MOTION_CHANNEL_NAMES.duplicate()
	var families: Array = []
	if names.is_empty():
		for c in channels:
			families.append({"name": "channel_%d" % c, "start": c, "size": 1, "unit": false})
		return families
	var index := 0
	while index < channels:
		var base := _family_base(String(names[index]))
		var size := 1
		while index + size < channels and _family_base(String(names[index + size])) == base:
			size += 1
		families.append({"name": base, "start": index, "size": size,
			"unit": size == 3 and base.contains("gravity")})
		index += size
	return families


## Strips a trailing axis suffix ("_x"/"_y"/"_z") so the three axes of one
## vector quantity share a family name.
static func _family_base(channel_name: String) -> String:
	var lowered := channel_name.to_lower()
	for suffix in ["_x", "_y", "_z"]:
		if lowered.ends_with(suffix):
			return lowered.substr(0, lowered.length() - 2)
	return lowered


## Builds the metric configuration for a preset. `channel_weights` stays uniform.
static func build_metric(preset: String, channels: int, samples: int,
		feature_manifest: Dictionary) -> Dictionary:
	var metric_id := preset if METRIC_PRESETS.has(preset) else METRIC_DEFAULT
	var families := _families_for(feature_manifest, channels)
	var normalizer := "per_channel_zscore" if metric_id.begins_with("zscore") else "per_family_rms"
	var gravity_mode := "angular" if metric_id.contains("angular") else "linear"
	var derivative_weight := DERIVATIVE_WEIGHT_DEFAULT if metric_id.contains("deriv") else 0.0
	var band_fraction := BAND_FRACTION_LEGACY
	if metric_id.contains("band20"):
		band_fraction = 0.20
	elif metric_id.contains("band25"):
		band_fraction = 0.25
	var band := maxi(1, int(round(band_fraction * float(samples))))
	# Angular terms only exist for a unit (already normalized) 3-vector family.
	var angular_starts: Array = []
	if gravity_mode == "angular":
		for family in families:
			if bool((family as Dictionary).get("unit", false)) and int((family as Dictionary)["size"]) == 3:
				angular_starts.append(int((family as Dictionary)["start"]))
	var weights: Array = []
	for _c in channels:
		weights.append(1.0)
	var metric := {"metric_id": metric_id, "normalizer": normalizer, "gravity_mode": gravity_mode,
		"derivative_weight": derivative_weight, "band_fraction": band_fraction, "band": band,
		"families": families, "angular_starts": angular_starts, "channel_weights": weights,
		"weights_basis": "uniform", "channels": channels, "samples": samples}
	metric["term_indices"] = _term_indices(metric)
	return metric


## The distance terms of the metric, as channel indices: every scalar channel,
## plus one index (the family start) standing for each angular family. Angular
## families contribute a single geodesic term, not three scalars.
static func _term_indices(metric: Dictionary) -> Array:
	var channels := int(metric.get("channels", 0))
	var angular_starts: Array = metric.get("angular_starts", [])
	var skipped: Dictionary = {}
	for start in angular_starts:
		skipped[int(start) + 1] = true
		skipped[int(start) + 2] = true
	var out: Array = []
	for c in channels:
		if not skipped.has(c):
			out.append(c)
	return out


## Multichannel Sakoe-Chiba-banded DTW over a single shared warping path.
## Allocation-light: two reused PackedFloat32Array rows, no per-cell Dictionaries.
static func dtw_distance(a: PackedFloat32Array, b: PackedFloat32Array, channels: int,
		length: int, band: int) -> float:
	var inf := 1e30
	var prev := PackedFloat32Array()
	var curr := PackedFloat32Array()
	prev.resize(length + 1)
	curr.resize(length + 1)
	for j in length + 1:
		prev[j] = inf
	prev[0] = 0.0
	for i in range(1, length + 1):
		for j in length + 1:
			curr[j] = inf
		var lo: int = maxi(1, i - band)
		var hi: int = mini(length, i + band)
		for j in range(lo, hi + 1):
			var cost := 0.0
			var a_base := (i - 1)
			var b_base := (j - 1)
			for c in channels:
				var diff := a[c * length + a_base] - b[c * length + b_base]
				cost += diff * diff
			var best: float = minf(prev[j], minf(curr[j - 1], prev[j - 1]))
			curr[j] = cost + best
		var swap := prev
		prev = curr
		curr = swap
	return sqrt(maxf(prev[length], 0.0))


static func _fit_normalization(windows: Array, channels: int, samples: int) -> Dictionary:
	var mean := PackedFloat32Array()
	var std := PackedFloat32Array()
	mean.resize(channels)
	std.resize(channels)
	var count := 0
	for window in windows:
		var raw: PackedFloat32Array = window
		count += 1
		for c in channels:
			for t in samples:
				mean[c] += raw[c * samples + t]
	var total_samples: float = float(count) * float(samples)
	if total_samples <= 0.0:
		total_samples = 1.0
	for c in channels:
		mean[c] = mean[c] / total_samples
	for window in windows:
		var raw: PackedFloat32Array = window
		for c in channels:
			for t in samples:
				var diff := raw[c * samples + t] - mean[c]
				std[c] += diff * diff
	for c in channels:
		var variance: float = std[c] / total_samples
		std[c] = sqrt(variance) if variance > 1e-8 else 1.0
	return {"mean": mean, "std": std}


## Metric-aware TRAIN-only normalization. Both modes produce the same
## (mean[C], std[C]) pair the artifact already carries, so `_normalize` and
## `validate_artifact` are unchanged:
##  - `per_channel_zscore`: v1 behaviour, an independent mean/std per channel.
##  - `per_family_rms`: a non-unit vector family (linear acceleration, gyro) is
##    de-meaned per axis (removing each axis's sensor bias, which carries no
##    gesture information) but divided by ONE scalar: the family's RMS over all
##    of its axes and samples. Relative axis magnitudes -- i.e. the DIRECTION of
##    the acceleration/rotation in the device frame -- therefore survive
##    normalization, and a quiet axis is no longer amplified to the same
##    variance as the axis that actually carries the gesture. A unit family
##    (gravity) is already normalized by construction and is left completely
##    untouched (mean 0, std 1) so it stays on S^2.
## A family of size 1 (the unknown-channel-metadata fallback) reduces exactly to
## per-channel z-score, keeping the engine sensor-generic.
static func fit_normalization_for_metric(windows: Array, metric: Dictionary) -> Dictionary:
	var channels := int(metric["channels"])
	var samples := int(metric["samples"])
	if String(metric.get("normalizer", "per_channel_zscore")) == "per_channel_zscore":
		return _fit_normalization(windows, channels, samples)
	var base := _fit_normalization(windows, channels, samples)
	var mean: PackedFloat32Array = base["mean"]
	var std: PackedFloat32Array = base["std"]
	var out_mean := PackedFloat32Array()
	var out_std := PackedFloat32Array()
	out_mean.resize(channels)
	out_std.resize(channels)
	for family in (metric.get("families", []) as Array):
		var start := int((family as Dictionary)["start"])
		var size := int((family as Dictionary)["size"])
		if bool((family as Dictionary).get("unit", false)):
			for k in size:
				out_mean[start + k] = 0.0
				out_std[start + k] = 1.0
			continue
		var sum_sq := 0.0
		var count := 0
		for window in windows:
			var raw: PackedFloat32Array = window
			for k in size:
				var c := start + k
				for t in samples:
					var diff := raw[c * samples + t] - mean[c]
					sum_sq += diff * diff
					count += 1
		var rms := sqrt(sum_sq / float(maxi(count, 1)))
		if not is_finite(rms) or rms <= 1e-8:
			rms = 1.0
		for k in size:
			out_mean[start + k] = mean[start + k]
			out_std[start + k] = rms
	return {"mean": out_mean, "std": out_std}


static func normalize_window(raw: PackedFloat32Array, mean: PackedFloat32Array,
		std: PackedFloat32Array, channels: int, samples: int) -> PackedFloat32Array:
	return _normalize(raw, mean, std, channels, samples)


static func _normalize(raw: PackedFloat32Array, mean: PackedFloat32Array,
		std: PackedFloat32Array, channels: int, samples: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(channels * samples)
	for c in channels:
		var m := mean[c]
		var s := std[c] if std[c] > 1e-8 else 1.0
		for t in samples:
			var idx := c * samples + t
			out[idx] = (raw[idx] - m) / s
	return out
