class_name Presence
extends RefCounted

## The heartbeat, and the three words a room is described in.
##
## Every HEARTBEAT_MS the local figure goes out again even if nothing changed.
## That repetition is the whole mechanism: there is no "peer left" message on a
## mesh, so absence is the only thing that can be observed, and absence is only
## observable against an expected rhythm.
##
## Bands, not metres. A number in metres off a radio is a guess dressed as a
## measurement — see LanMesh.peer_proximity for the same ruling one layer down.
##   here  heard within HERE_MS   — in the room with you
##   near  heard within NEAR_MS   — still around, gone quiet
##   gone  everything else
## An rssi, when a transport has one, can only pull a peer DOWN a band, never
## up: a recent packet proves presence, while a weak signal only suggests
## distance, and a suggestion may not overrule a proof.

const HEARTBEAT_MS := 2000
const HERE_MS := 5000
const NEAR_MS := 15_000
const BAND_HERE := "here"
const BAND_NEAR := "near"
const BAND_GONE := "gone"
## Below this the link is weak enough to demote "here" to "near". -1 means the
## transport did not say, which is the LAN backend's honest answer.
const WEAK_RSSI := -85

var _last_beat_ms := -HEARTBEAT_MS


## True once per HEARTBEAT_MS. Call it every frame; it holds its own clock so
## no caller has to.
func due(now_ms: int) -> bool:
	if now_ms - _last_beat_ms < HEARTBEAT_MS:
		return false
	_last_beat_ms = now_ms
	return true


func force_due() -> void:
	_last_beat_ms = -HEARTBEAT_MS


func last_beat_ms() -> int:
	return _last_beat_ms


static func band(age_ms: int, rssi: int = -1) -> String:
	if age_ms < 0 or age_ms > NEAR_MS:
		return BAND_GONE
	if age_ms <= HERE_MS:
		return BAND_NEAR if (rssi != -1 and rssi < WEAK_RSSI) else BAND_HERE
	return BAND_NEAR


## who -> band, over a Room. `rssi` is who -> int, empty when unknown.
static func bands(room: Room, now_ms: int, rssi: Dictionary = {}) -> Dictionary:
	var out := {}
	for who in room.names():
		out[who] = band(room.age_of(who, now_ms), int(rssi.get(who, -1)))
	return out
