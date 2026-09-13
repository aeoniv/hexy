class_name Room
extends RefCounted

## Who is here, and what the room as a whole is saying.
##
## A peer is a who -> {bits, moving, seen} row, `seen` being a room-clock
## millisecond (ChirpClock.now_ms), never a boot-relative tick — the whole
## point of the clock is that this number is comparable across phones.
##
## The room's figure is Cast.room_cast over every bit set present INCLUDING
## our own: a room of one is that one person's figure, which is the honest
## answer, and a room that quietly excluded itself would make the last peer to
## leave watch the room become a stranger.
##
## Drift is measured in Q6 hops, because that is the only distance the 64
## figures actually have. Two moving lines away is a room still holding one
## conversation; three is somebody talking about something else.

const SELF_KEY := "_self"
const EXPIRY_MS := 30_000
const DRIFT_HOPS := 2

var peers := {}


func clear() -> void:
	peers.clear()


## Our own figure sits in the same map as everyone else's so that `figure()`
## has exactly one code path. Order matters to Cast.room_cast (a tied line
## keeps the FIRST peer's line), so self is put in first and stays first.
func set_self(bits: int, moving: int, seen_ms: int) -> void:
	_put(SELF_KEY, bits, moving, seen_ms)


func set_peer(who: String, bits: int, moving: int, seen_ms: int) -> void:
	if who == "" or who == SELF_KEY:
		return
	_put(who, bits, moving, seen_ms)


func _put(key: String, bits: int, moving: int, seen_ms: int) -> void:
	peers[key] = {"bits": bits & 63, "moving": moving & 63, "seen": seen_ms}


func forget(who: String) -> bool:
	return peers.erase(who)


func has(who: String) -> bool:
	return peers.has(who)


## Everyone but us, by name, in a stable order.
func names() -> Array[String]:
	var out: Array[String] = ([] as Array[String])
	for k in peers:
		if String(k) != SELF_KEY:
			out.append(String(k))
	out.sort()
	return out


## Peers only — the number a person would count in the room, not counting
## themselves.
func peer_count() -> int:
	return names().size()


## Everybody, us first. The order Cast.room_cast reads ties in.
func all_bits() -> Array[int]:
	var out: Array[int] = ([] as Array[int])
	if peers.has(SELF_KEY):
		out.append(int(peers[SELF_KEY]["bits"]) & 63)
	for k in names():
		out.append(int(peers[k]["bits"]) & 63)
	return out


## {bits, moving, throws} — the room as one figure.
func figure() -> Dictionary:
	return Cast.room_cast(all_bits())


## The shape HexyStore.set_room takes.
func as_store_room() -> Dictionary:
	var f := figure()
	return {"bits": int(f["bits"]), "moving": int(f["moving"]), "peers": peer_count()}


## Peers further than DRIFT_HOPS from the room's figure. Self is never listed:
## a person cannot drift from a room they are half of.
func drifting() -> Array[String]:
	var centre := int(figure()["bits"])
	var out: Array[String] = ([] as Array[String])
	for k in names():
		if Q6.distance(int(peers[k]["bits"]), centre) > DRIFT_HOPS:
			out.append(k)
	return out


## Drops peers unheard for EXPIRY_MS and returns their names. Self never
## expires. `now_ms` is room-clock time.
func expire(now_ms: int, window_ms: int = EXPIRY_MS) -> Array[String]:
	var gone: Array[String] = ([] as Array[String])
	for k in names():
		if now_ms - int(peers[k]["seen"]) > window_ms:
			gone.append(k)
	for k in gone:
		peers.erase(k)
	return gone


## who -> age in ms, for presence banding.
func age_of(who: String, now_ms: int) -> int:
	if not peers.has(who):
		return -1
	return now_ms - int(peers[who]["seen"])


func to_dict() -> Dictionary:
	return peers.duplicate(true)
