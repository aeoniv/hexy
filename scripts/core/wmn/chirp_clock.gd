class_name ChirpClock
extends RefCounted

## A tiny NTP for a room full of phones.
##
## Two phones cannot compare figures cast "at the same moment" unless they
## agree what the moment was, and `Time.get_ticks_msec()` is boot-relative, so
## two devices in the same room differ by hours. This holds the single integer
## that reconciles them: `now_ms() == get_ticks_msec() + offset_ms()`.
##
## Each sample is the classic four-timestamp exchange:
##   t1 my_send_ms            (my clock, when I chirped)
##   t2 peer_recv_of_mine_ms  (their clock, when they heard it)
##   t3 peer_send_ms          (their clock, when they chirped back)
##   t4 local_recv_ms         (my clock, when I heard that)
## offset = ((t2 - t1) + (t3 - t4)) / 2, which cancels the flight time exactly
## when the path is symmetric. With only (t3, t4) the honest estimate is
## t3 - t4, biased by one flight; it is kept because a peer that only beacons
## is still better than no peer, and the MEDIAN is what survives to the answer.
##
## Median, not mean, on purpose: one phone whose radio stalled for 400 ms
## produces one wild sample, and a mean would hand that stall to the whole room.
## Deterministic and network-free: every number comes in through note().

const MAX_SAMPLES := 32

var _samples: Array[int] = ([] as Array[int])
var _offset := 0
var _dirty := false


## One observation. Pass all four timestamps when a round trip completed;
## pass the first two alone for a one-way beacon.
func note(peer_send_ms: int, local_recv_ms: int,
		peer_recv_of_mine_ms: int = -1, my_send_ms: int = -1) -> int:
	var est := 0
	if peer_recv_of_mine_ms >= 0 and my_send_ms >= 0:
		est = int(round(((peer_recv_of_mine_ms - my_send_ms) + (peer_send_ms - local_recv_ms)) / 2.0))
	else:
		est = peer_send_ms - local_recv_ms
	_samples.append(est)
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()
	_dirty = true
	return est


func sample_count() -> int:
	return _samples.size()


func clear() -> void:
	_samples.clear()
	_offset = 0
	_dirty = false


func offset_ms() -> int:
	if _dirty:
		_offset = _median(_samples)
		_dirty = false
	return _offset


## The room's clock. This is the number every cast is stamped with.
func now_ms() -> int:
	return Time.get_ticks_msec() + offset_ms()


## How far apart the samples are — a rough confidence. 0 with fewer than two.
func spread_ms() -> int:
	if _samples.size() < 2:
		return 0
	var lo: int = _samples[0]
	var hi: int = _samples[0]
	for s in _samples:
		lo = mini(lo, s)
		hi = maxi(hi, s)
	return hi - lo


static func _median(xs: Array[int]) -> int:
	if xs.is_empty():
		return 0
	var sorted: Array[int] = xs.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return sorted[n / 2]
	return int(round((sorted[n / 2 - 1] + sorted[n / 2]) / 2.0))
