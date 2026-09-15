extends HexyAddon

## HEXY_ECOLOC -- N4: WHERE THE OTHER PHONES ARE, as honestly as the wire allows.
##
## THE ONE FACT THIS ADD-ON IS BUILT AROUND: the wmn6 wire carries NO PEER
## POSITION. `HexyMsg.body_to_wire()` puts exactly bits / heading_rad / phase /
## stage / glow on a figure's "bw" key, and `Wmn.peers()` rows add only
## receiver-side presence (rssi, band, cls, last_seen_ms). There is no lat, no
## lon, no fix, anywhere on the fabric -- and this add-on does NOT invent a
## protocol change in wmn to get one. So the rule is two-legged:
##
##   1. BOTH FIXES KNOWN -> a real bearing. Own fix comes off the antenna door
##      (`HexySenses.sample_place` publishes organ "antenna", door "place",
##      value {lat, lon}); a peer fix is used ONLY if some future wire actually
##      carries one -- we look for lat/lon on the pheromone Sense's `value`
##      (the peer Body) or its `meta`, and use it if it is there. Bearing is the
##      great-circle initial bearing, radians, 0 = north, clockwise, allocentric
##      (world heading -- the glass rotates the whole peer field itself).
##      `dist_m` is the haversine distance.
##   2. NO PEER FIX -> a COARSE RING AND NO ARROW. `bearing_rad: null`,
##      `dist_m: null`, and `band` is the proximity class wmn already put on the
##      pheromone meta ("touch"/"room"/"far" -- the same vocabulary
##      FlyCalciumRadar2D.RING_FRAC speaks), falling back to an rssi cut if a
##      backend ever fills meta.rssi in. The LAN backend's rssi is -1 by ruling
##      (see Wmn.peers), so on LAN today leg 2 is always what runs.
##
## AT MOST ONE SENSE PER PEER PER SECOND, and a peer unheard for thirty seconds
## is dropped outright rather than left standing on a stale ring.
##
## OFF MEANS BASE UNCHANGED: two subscriptions, two doors, one Sense topic, and
## not one field written anywhere else.

const DOOR_GPS := "gps"
const DOOR_MESH := "mesh"

## The door this add-on's Sense fans out on: "/sense/peer_bearing".
const BEARING_DOOR := "peer_bearing"

## THE TWO ORGANS THIS ADD-ON LISTENS FOR. See `reads()` for why the declared
## topics are organ-named while the subscription itself sits on "/sense".
const ORGAN_ANTENNA := "antenna"
const ORGAN_PHEROMONE := "pheromone"

## The antenna door that carries a gps fix (HexySenses.sample_place).
const PLACE_DOOR := "place"

## At most one bearing Sense per peer per second.
const PUBLISH_PERIOD_MS: int = 1000

## A peer unheard for this long is forgotten entirely.
const EXPIRY_MS: int = 30000

## Mean earth radius, metres -- the only constant a haversine needs.
const EARTH_R_M: float = 6371000.0

## Bands, when there is nothing but signal strength to go on. Named in the
## radar's own ring vocabulary (FlyCalciumRadar2D.RING_FRAC) so a ring this
## add-on names is a ring the glass can already draw.
const BAND_TOUCH := "touch"
const BAND_ROOM := "room"
const BAND_FAR := "far"
const BANDS := [BAND_TOUCH, BAND_ROOM, BAND_FAR]

## rssi cuts, used ONLY when a backend actually reports one. -1 means "no
## radio here" (Wmn.peers' own ruling) and never reaches these.
const RSSI_TOUCH: int = -55
const RSSI_ROOM: int = -75

var _topic: RefCounted = null
var _broker = null
var _sense_sub: int = -1

## {lat: float, lon: float} once the antenna has ever reported a place, else {}.
var _own_fix: Dictionary = {}

## who -> {"band": String, "last_ms": int, "next_ms": int, "fix": Dictionary}
var _peers: Dictionary = {}

## Every bearing Sense this add-on has published, counted for the view.
var _published: int = 0


# -- the contract -------------------------------------------------------------

func doors() -> PackedStringArray:
	return PackedStringArray([DOOR_GPS, DOOR_MESH])


## THE TWO ORGANS, NAMED AS TOPICS. The bus fans a Sense out by DOOR, not by
## organ ("/sense/place", "/sense/radio"), so there is no literal "/sense/
## antenna" or "/sense/pheromone" traffic to subscribe to -- the subscription
## below sits on "/sense" itself and drops everything that is not one of these
## two organs. These names are therefore the honest description of what is
## read (organ antenna, organ pheromone) and the filter enforces exactly them.
func reads() -> PackedStringArray:
	return PackedStringArray([
		"%s/%s" % [HexyTopic.TOPIC_SENSE, ORGAN_ANTENNA],
		"%s/%s" % [HexyTopic.TOPIC_SENSE, ORGAN_PHEROMONE],
	])


func writes() -> PackedStringArray:
	return PackedStringArray(["%s/%s" % [HexyTopic.TOPIC_SENSE, BEARING_DOOR]])


func version() -> String:
	return "1"


## NOTHING TO DRAW. A bearing is a thing the radar shows, not a panel.
func view() -> Control:
	return null


func attach(bus: Dictionary) -> void:
	_topic = bus.get("topic", null) as RefCounted
	_broker = bus.get("broker", null)
	if _broker != null:
		_broker.acquire(DOOR_GPS, addon_name())
		_broker.acquire(DOOR_MESH, addon_name())
	if _topic != null:
		_sense_sub = int(_topic.subscribe(HexyTopic.TOPIC_SENSE, Callable(self, "_on_sense")))
		var last: Dictionary = _topic.last(HexyTopic.TOPIC_SENSE)
		if not last.is_empty():
			_on_sense(last)


func detach() -> void:
	if _topic != null and _sense_sub >= 0:
		_topic.unsubscribe(_sense_sub)
	_sense_sub = -1
	if _broker != null:
		_broker.release_door(DOOR_GPS)
		_broker.release_door(DOOR_MESH)
	_broker = null
	_topic = null
	_own_fix = {}
	_peers = {}


# -- hearing ------------------------------------------------------------------

func _process(_delta: float) -> void:
	expire()


## ONE DOOR IN, both organs. Anything that is not antenna/place or pheromone
## falls straight through.
func _on_sense(msg: Dictionary) -> void:
	var organ: String = String(msg.get("organ", ""))
	if organ == ORGAN_ANTENNA:
		if String(msg.get("door", "")) == PLACE_DOOR:
			_take_own_fix(msg.get("value", null))
		return
	if organ == ORGAN_PHEROMONE:
		## NOT OUR OWN VOICE. A bearing Sense is published on the pheromone
		## organ too (that is the organ a peer IS), so without this the
		## add-on hears itself and every bearing feeds the next one.
		if String(msg.get("door", "")) == BEARING_DOOR:
			return
		_take_peer(msg)


## THE OWN FIX, straight off the antenna's place Sense: {lat, lon}.
func _take_own_fix(value) -> void:
	var fix: Dictionary = _fix_of(value)
	if not fix.is_empty():
		_own_fix = fix


## ONE PHEROMONE SENSE, HEARD, with the clock handed in. The public door a
## test drives; `_on_sense` is the same door the bus drives.
func hear(msg: Dictionary, now_ms: int = -1) -> void:
	_take_peer(msg, now_ms)


func _take_peer(msg: Dictionary, now_ms: int = -1) -> void:
	var meta: Dictionary = msg.get("meta", {}) as Dictionary
	var who: String = String(meta.get("who", ""))
	if who == "":
		return
	var now: int = _now_ms(now_ms)
	var row: Dictionary = _peers.get(who, {
		"band": "", "last_ms": 0, "next_ms": 0, "fix": {},
	})
	row["last_ms"] = now
	row["band"] = _band_of(meta)
	## A PEER FIX ONLY IF ONE ACTUALLY ARRIVED. Checked on the Body first, then
	## on the meta, so the day a wire does carry a place this file needs no
	## edit -- and until then it stays empty and leg 2 runs.
	var fix: Dictionary = _fix_of(msg.get("value", null))
	if fix.is_empty():
		fix = _fix_of(meta)
	if not fix.is_empty():
		row["fix"] = fix
	_peers[who] = row
	expire(now)
	_emit(who, now)


# -- the rule -----------------------------------------------------------------

## ONE BEARING SENSE FOR ONE PEER, throttled. False when the throttle held it
## back, the peer is unknown, or there is no bus to say it on.
func _emit(who: String, now_ms: int = -1) -> bool:
	if _topic == null or not _peers.has(who):
		return false
	var now: int = _now_ms(now_ms)
	var row: Dictionary = _peers[who]
	if now < int(row.get("next_ms", 0)):
		return false
	row["next_ms"] = now + PUBLISH_PERIOD_MS
	_peers[who] = row
	var peer_fix: Dictionary = row.get("fix", {}) as Dictionary
	var bearing_rad = null
	var dist_m = null
	if not _own_fix.is_empty() and not peer_fix.is_empty():
		bearing_rad = bearing_of(_own_fix, peer_fix)
		dist_m = distance_of(_own_fix, peer_fix)
	var t_ns: int = now * 1000000
	var value: Dictionary = {
		"who": who,
		"bearing_rad": bearing_rad,
		"dist_m": dist_m,
		"band": String(row.get("band", "")),
		"t_ns": t_ns,
	}
	_published += 1
	return bool(_topic.publish(HexyTopic.TOPIC_SENSE,
		HexyMsg.sense(ORGAN_PHEROMONE, BEARING_DOOR, t_ns, value, {"who": who})))


## EVERY PEER UNHEARD FOR THIRTY SECONDS, GONE. Returns how many were dropped.
func expire(now_ms: int = -1) -> int:
	var now: int = _now_ms(now_ms)
	var dropped: int = 0
	for who in _peers.keys().duplicate():
		if now - int((_peers[who] as Dictionary).get("last_ms", 0)) > EXPIRY_MS:
			_peers.erase(who)
			dropped += 1
	return dropped


## WHICH PEERS THIS ADD-ON IS STILL HOLDING, for a test or a panel.
func tracked() -> PackedStringArray:
	var out := PackedStringArray()
	for who in _peers.keys():
		out.append(String(who))
	out.sort()
	return out


func published() -> int:
	return _published


## THE OWN FIX AS LAST HEARD, or {} when the antenna has never reported one.
func own_fix() -> Dictionary:
	return _own_fix.duplicate()


# -- the arithmetic -----------------------------------------------------------

## {lat, lon} out of anything shaped like a fix, or {} when it is not one. A
## Body dictionary has no lat/lon, which is exactly how leg 2 gets chosen.
static func _fix_of(v) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	if not (d.has("lat") and d.has("lon")):
		return {}
	var lat: float = float(d["lat"])
	var lon: float = float(d["lon"])
	if not (is_finite(lat) and is_finite(lon)):
		return {}
	if absf(lat) > 90.0 or absf(lon) > 180.0:
		return {}
	return {"lat": lat, "lon": lon}


## THE COARSE RING. wmn already puts the fabric's own proximity class on the
## pheromone meta ("touch"/"room"/"far"); an rssi is only consulted when a
## backend actually reported one (-1 is "no radio", never a distance).
static func _band_of(meta: Dictionary) -> String:
	var band: String = String(meta.get("band", ""))
	if BANDS.has(band):
		return band
	var rssi: int = int(meta.get("rssi", -1))
	if rssi == -1 or rssi >= 0:
		return band
	if rssi >= RSSI_TOUCH:
		return BAND_TOUCH
	if rssi >= RSSI_ROOM:
		return BAND_ROOM
	return BAND_FAR


## GREAT-CIRCLE INITIAL BEARING from `a` to `b`, radians, 0 = north, clockwise.
## Allocentric on purpose: the glass turns the whole peer field by the compass
## itself (see FlyCalciumRadar2D), so a world heading is the right gift.
static func bearing_of(a: Dictionary, b: Dictionary) -> float:
	var lat1: float = deg_to_rad(float(a.get("lat", 0.0)))
	var lat2: float = deg_to_rad(float(b.get("lat", 0.0)))
	var dlon: float = deg_to_rad(float(b.get("lon", 0.0)) - float(a.get("lon", 0.0)))
	var y: float = sin(dlon) * cos(lat2)
	var x: float = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
	return fposmod(atan2(y, x), TAU)


## HAVERSINE, metres.
static func distance_of(a: Dictionary, b: Dictionary) -> float:
	var lat1: float = deg_to_rad(float(a.get("lat", 0.0)))
	var lat2: float = deg_to_rad(float(b.get("lat", 0.0)))
	var dlat: float = lat2 - lat1
	var dlon: float = deg_to_rad(float(b.get("lon", 0.0)) - float(a.get("lon", 0.0)))
	var h: float = sin(dlat * 0.5) * sin(dlat * 0.5) \
		+ cos(lat1) * cos(lat2) * sin(dlon * 0.5) * sin(dlon * 0.5)
	return 2.0 * EARTH_R_M * asin(minf(1.0, sqrt(maxf(0.0, h))))


func _now_ms(now_ms: int = -1) -> int:
	return now_ms if now_ms >= 0 else Time.get_ticks_msec()
