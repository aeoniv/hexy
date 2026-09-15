extends SceneTree

## N4 -- THE ECO-LOCATION ADD-ON, HEADLESS.
##
## addons/hexy_ecoloc is put on a real HexyTopic through the real HexyAddons
## loader (so the GuardedBroker, the write check and the one-holder-per-door
## rule are the ones shipping), fed FAKE PHEROMONE SENSES the way wmn feeds
## real ones, and asked four questions:
##
##   1. A pheromone Sense with no fix anywhere on it yields a bearing Sense on
##      "/sense/peer_bearing" with bearing_rad null and the band carried
##      through -- the LAN case, which is every case on the wire today.
##   2. A pheromone Sense that DOES carry a fix, with an own fix already heard
##      off the antenna's place door, yields a real bearing and a real dist_m.
##   3. AT MOST ONE PER PEER PER SECOND. Two Senses 10 ms apart is one bearing.
##   4. THIRTY SECONDS OF SILENCE IS GONE. A peer unheard that long is dropped.
##
## Plus the doors: gps and mesh are held while attached and free after detach.

const ADDON_PATH: String = "res://addons/hexy_ecoloc/addon.gd"

var failures: int = 0
var passes: int = 0

## Every Sense that landed on "/sense/peer_bearing".
var seen: Array = []


func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _initialize() -> void:
	print("\n--- TEST ADDON ECOLOC (bearings, or an honest ring) ---")
	_run()
	print("--- addon ecoloc: %d passed, %d failed ---" % [passes, failures])
	if failures == 0:
		print("--- ALL ADDON ECOLOC TESTS PASSED PERFECTLY ---\n")
		quit(0)
	else:
		print("--- ADDON ECOLOC TESTS FAILED: ", failures, " ---\n")
		quit(1)


func _on_bearing(msg: Dictionary) -> void:
	seen.append(msg)


## A pheromone Sense exactly as Wmn._publish_pheromone builds one: organ
## "pheromone", door "radio", value a Body, meta {who, kind, band, in_phase}.
func _pheromone(who: String, band: String, extra_meta: Dictionary = {},
		value: Variant = null) -> Dictionary:
	var meta: Dictionary = {
		"who": who, "kind": "cast", "band": band, "in_phase": false,
		"phase": null, "stage": null,
	}
	for k in extra_meta:
		meta[k] = extra_meta[k]
	var body: Variant = value if value != null else HexyMsg.body_from_bits(21, 0)
	return HexyMsg.sense("pheromone", "radio", 0, body, meta)


func _run() -> void:
	var topic := HexyTopic.new()
	var broker := Broker.new()
	broker.autosave = false
	topic.subscribe("/sense/peer_bearing", Callable(self, "_on_bearing"))

	var loader := HexyAddons.new()
	loader.name = "Addons"
	root.add_child(loader)
	loader._bus = {"topic": topic, "broker": broker}
	loader._broker = broker

	var script: Script = load(ADDON_PATH) as Script
	check(script != null, "addons/hexy_ecoloc/addon.gd loads")
	if script == null:
		return
	## UNTYPED ON PURPOSE: `hear`, `tracked`, `expire` and `own_fix` are this
	## add-on's own doors, not HexyAddon's, so a HexyAddon-typed local could not
	## call them.
	var addon = script.new()
	check(addon is HexyAddon, "and it extends HexyAddon")
	if not (addon is HexyAddon):
		return

	# -- the manifest ---------------------------------------------------------
	var m: Dictionary = addon.manifest()
	check(String(m["name"]) == "hexy_ecoloc", "it calls itself hexy_ecoloc")
	check(Array(m["doors"]) == ["gps", "mesh"], "it declares the gps and mesh doors")
	check(Array(m["writes"]) == ["/sense/peer_bearing"],
		"it writes one topic, /sense/peer_bearing")
	check(addon.writes_valid(), "and that write is inside Sense/Act")
	check(Array(m["reads"]) == ["/sense/antenna", "/sense/pheromone"],
		"it reads the antenna and the pheromone organs")
	check(addon.view() == null, "it brings no view")

	check(loader.attach_one(addon as HexyAddon), "the loader takes it")
	check(broker.holder("gps") == "hexy_ecoloc", "the gps door is held")
	check(broker.holder("mesh") == "hexy_ecoloc", "the mesh door is held")

	# -- 1. NO FIX ANYWHERE -> a ring, not an arrow ---------------------------
	seen.clear()
	addon.hear(_pheromone("peer_a", "room"), 1000)
	check(seen.size() == 1, "a pheromone Sense yields one bearing Sense (got %d)" % seen.size())
	if seen.size() == 1:
		var msg: Dictionary = seen[0]
		check(HexyMsg.validate(msg), "and it is a valid Sense")
		check(String(msg["organ"]) == "pheromone" and String(msg["door"]) == "peer_bearing",
			"published as pheromone/peer_bearing")
		var v: Dictionary = msg["value"]
		check(String(v["who"]) == "peer_a", "the value names the peer")
		check(v["bearing_rad"] == null, "bearing_rad is null when nothing carries a fix")
		check(v["dist_m"] == null, "and so is dist_m")
		check(String(v["band"]) == "room", "the band comes through from the wire's meta")
		check(int(v["t_ns"]) == 1000 * 1000000, "and t_ns is the moment it was heard")

	# -- rssi only when a backend actually reported one -----------------------
	seen.clear()
	addon.hear(_pheromone("peer_rssi", "", {"rssi": -50}), 2000)
	check(seen.size() == 1 and String((seen[0]["value"] as Dictionary)["band"]) == "touch",
		"a strong rssi with no class becomes the touch ring")
	seen.clear()
	addon.hear(_pheromone("peer_norssi", "", {"rssi": -1}), 2000)
	check(seen.size() == 1 and String((seen[0]["value"] as Dictionary)["band"]) == "",
		"and rssi -1 (no radio) invents no ring at all")

	# -- 2. BOTH FIXES -> a real bearing --------------------------------------
	# Own fix reaches the add-on the way HexySenses.sample_place publishes it.
	topic.publish(HexyTopic.TOPIC_SENSE,
		HexyMsg.sense("antenna", "place", 0, {"lat": 0.0, "lon": 0.0},
			{"sunrise_h": 6.0}))
	check(not addon.own_fix().is_empty(), "the antenna's place Sense becomes the own fix")
	seen.clear()
	## A peer due NORTH: same longitude, higher latitude. ~0 rad, ~111 km.
	addon.hear(_pheromone("peer_n", "far", {"lat": 1.0, "lon": 0.0}), 3000)
	check(seen.size() == 1, "a peer carrying a fix still yields one bearing Sense")
	if seen.size() == 1:
		var v2: Dictionary = seen[0]["value"]
		check(v2["bearing_rad"] != null and absf(float(v2["bearing_rad"])) < 0.01,
			"a peer due north bears ~0 rad (got %s)" % str(v2["bearing_rad"]))
		check(v2["dist_m"] != null and absf(float(v2["dist_m"]) - 111195.0) < 500.0,
			"and is ~111 km away (got %s)" % str(v2["dist_m"]))
	seen.clear()
	## A peer due EAST at the equator: ~TAU/4.
	addon.hear(_pheromone("peer_e", "far", {"lat": 0.0, "lon": 1.0}), 4000)
	check(seen.size() == 1 and absf(float((seen[0]["value"] as Dictionary)["bearing_rad"])
			- TAU * 0.25) < 0.01, "a peer due east bears ~TAU/4 rad")

	# -- 3. THE THROTTLE ------------------------------------------------------
	seen.clear()
	addon.hear(_pheromone("peer_t", "room"), 10000)
	addon.hear(_pheromone("peer_t", "room"), 10010)
	addon.hear(_pheromone("peer_t", "room"), 10900)
	check(seen.size() == 1, "three Senses inside a second are one bearing (got %d)" % seen.size())
	addon.hear(_pheromone("peer_t", "room"), 11000)
	check(seen.size() == 2, "and the next second speaks again")
	## The throttle is PER PEER, not global.
	addon.hear(_pheromone("peer_u", "room"), 11001)
	check(seen.size() == 3, "a different peer is not held back by the first one's throttle")

	# -- 4. THIRTY SECONDS OF SILENCE -----------------------------------------
	check(addon.tracked().has("peer_t"), "the peer is tracked while it speaks")
	check(addon.expire(11001 + 30001) >= 1, "silence past thirty seconds drops peers")
	check(not addon.tracked().has("peer_t"), "and the peer is gone")
	check(addon.tracked().is_empty(), "with nothing left standing on a stale ring (left: %s)" % str(addon.tracked()))

	# -- the doors go back ----------------------------------------------------
	loader.detach_all()
	check(broker.holder("gps") == "", "detach releases the gps door")
	check(broker.holder("mesh") == "", "detach releases the mesh door")
	seen.clear()
	topic.publish(HexyTopic.TOPIC_SENSE, _pheromone("peer_after", "room"))
	check(seen.is_empty(), "and a detached add-on says nothing more")
