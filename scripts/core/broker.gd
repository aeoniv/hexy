class_name Broker
extends Node

## THE RESOURCE BROKER. Ported from ix64-hexy's Phase 12, M1 — one door onto
## the camera, the microphone and the loudspeaker.
##
## FOUR LAWS, unchanged from origin:
##   1. ONE DOOR. A hold is [take] and a release is [release]. `holder_of()`
##      is the whole truth about a device at any moment.
##   2. EVERY MOVE IS WRITTEN DOWN. Each take, release and steal emits
##      [noted] with one line, so a device changing hands is on the record.
##   3. ORPHANED HOLDS ARE UNREPRESENTABLE. Leaving a mode calls
##      [release_mode], which drops every hold tagged with it.
##   4. THE LOSER OF A STEAL IS TOLD. [stolen] fires with both names before
##      the winner is recorded.
##
## RESOURCES NAMED HERE, PLUGINS NOT WIRED IN BASE — origin's holders
## (`rig`, `lens`, `pose`, `deck`, `find`, `look`, `face`, `ear`, `mouth`,
## `chirp`) name origin-only seams (`ixcap`, `ixlens`, `ixloc`, `ixbody`,
## `ixvoice`) that do not exist in base yet. This port keeps the full policy
## table (it is pure and costs nothing to keep correct), but nothing in base
## calls [take] under those holder names today — they are doors, not wired
## behaviour, until the seams that would ask for them land.
##
## PERSISTENCE — mirrors [HexyConfig]'s debounce-save pattern
## (`scripts/core/config.gd`: `SAVE_DEBOUNCE_MS`, `_queue_save`/`_flush_save`).
## WHAT IS SAVED IS DELIBERATELY NOT THE LIVE HOLD TABLE: `_held` is a fact
## about what is open on THIS boot, and replaying yesterday's holds on a fresh
## start would mean the app believing a camera is open that no longer is. What
## persists is the three lifetime counters ([method takes], [method releases],
## [method steals]) — diagnostic history a person or a test may want to read
## across a restart, and nothing a wrong value here could make the broker lie
## about a device's live state.

## A device changed hands. `line` is the whole of what a person is shown.
signal noted(line: String)
## Taken, released, or taken away. Three signals rather than one with a verb,
## because every subscriber this app has cares about exactly one of them.
signal taken(resource: String, holder: String)
signal released(resource: String, holder: String)
## LAW 4. `loser` had it, `winner` has it now.
signal stolen(resource: String, loser: String, winner: String)

## THE FOUR DEVICES. Two named lenses rather than one CAMERA, because most
## phones cannot bind both at once and that exclusion is stated once (see
## [EXCLUDES]) instead of scattered across every caller that needs to know.
const FRONT_LENS := "front_lens"
const BACK_LENS := "back_lens"
const LENSES := [FRONT_LENS, BACK_LENS]
const MIC := "mic"
const SPEAKER := "speaker"
const RESOURCES := [FRONT_LENS, BACK_LENS, MIC, SPEAKER]

## WHAT A PERSON READS.
const SHOWN := {
	FRONT_LENS: "front lens",
	BACK_LENS: "back lens",
	MIC: "mic",
	SPEAKER: "speaker",
}

## WHO ASKS. Named and closed: a holder name that is not on this list is a
## subsystem nobody decided the priority of. See the file doc for which of
## these have no wired caller in base yet.
const HOLDER_FIND := "find"
const HOLDER_LOOK := "look"
const HOLDER_FACE := "face"
const HOLDER_EAR := "ear"
const HOLDER_MOUTH := "mouth"
const HOLDER_CHIRP := "chirp"
const HOLDER_RIG := "rig"
const HOLDER_LENS := "lens"
const HOLDER_POSE := "pose"
const HOLDER_DECK := "deck"
const HOLDERS := [HOLDER_RIG, HOLDER_LENS, HOLDER_POSE, HOLDER_DECK,
	HOLDER_FIND, HOLDER_LOOK, HOLDER_FACE, HOLDER_EAR,
	HOLDER_MOUTH, HOLDER_CHIRP]

## WHO WINS. face (0) is the ambient one and the only one that can be taken
## from unasked; find/look/ear/mouth (1) are equal so a same-priority take is
## a REFUSAL; chirp (2) beats ear and mouth because its whole measurement is
## destroyed by sharing; pose (0) rides the face window's frames and owns no
## camera of its own; deck (1) is equal to find/look; rig (3) beats
## everything, because a take is several people standing in a room around a
## shutter that fires in two seconds.
const PRIORITY := {
	HOLDER_FACE: 0,
	HOLDER_FIND: 1,
	HOLDER_LOOK: 1,
	HOLDER_EAR: 1,
	HOLDER_MOUTH: 1,
	HOLDER_CHIRP: 2,
	HOLDER_POSE: 0,
	HOLDER_DECK: 1,
	HOLDER_LENS: 1,
	HOLDER_RIG: 3,
}

## TWO DEVICES THAT MAY NOT BOTH BE OPEN. The exclusion is between two
## HOLDERS, not between two devices: a holder that already has one of the pair
## may take the other (see [_excluded_holder]), which is what lets
## [HOLDER_CHIRP] emit and record its own sweep as one measurement.
const EXCLUDES := {
	MIC: SPEAKER,
	SPEAKER: MIC,
	FRONT_LENS: BACK_LENS,
	BACK_LENS: FRONT_LENS,
}

## HOLDERS THAT TAKE THE WHOLE ROOM. Only the rig: nothing else may hold
## anything while a take is rolling.
const SEIZES := {
	HOLDER_RIG: RESOURCES,
}

## HOW A DEVICE IS BEING USED.
##   DUTY       — ambient. Nobody is watching; there IS no picture.
##   CONTINUOUS — a screen a person is standing in front of, watching.
const CLAIM_DUTY := "duty"
const CLAIM_CONTINUOUS := "continuous"
const CLAIMS := [CLAIM_DUTY, CLAIM_CONTINUOUS]

## The lines. Format strings so a test reads the same sentence a person does.
const LINE_TAKE := "%s -> %s"
const LINE_FREE := "%s -> free"
const LINE_STEAL := "%s -> %s (was %s)"

## Where the lifetime counters are written. See the persistence note above.
const SAVE_PATH: String = "user://broker_stats.json"
## Same debounce window as [HexyConfig], so a burst of takes/releases (a find
## arming and disarming several times a second) is one save, not dozens.
const SAVE_DEBOUNCE_MS: int = 400

## Set false by a test that does not want a file written under user://.
var autosave: bool = true
var _save_pending: bool = false


# ── the pure half ────────────────────────────────────────────────────────────
# Who beats whom, and what it reads as. Both are static so the whole policy is
# assertable with no node, no device and no clock.


static func priority_of(holder: String) -> int:
	# AN UNKNOWN HOLDER IS THE LOWEST, never the highest.
	return int(PRIORITY.get(holder, -1))


## MAY `taker` TAKE IT FROM `owner`? Free is always yes; the same holder asking
## twice is always yes; otherwise STRICTLY higher wins.
static func may_take(owner: String, taker: String) -> bool:
	if owner == "" or owner == taker:
		return true
	return priority_of(taker) > priority_of(owner)


## The word for a device, for a person.
static func shown(resource: String) -> String:
	return String(SHOWN.get(resource, resource))


## WHICH RESOURCES THIS HOLDER TAKES THE WHOLE ROOM FOR. Empty for every
## holder but the rig.
static func seizes(holder: String) -> Array:
	return SEIZES.get(holder, [])


static func take_line(resource: String, holder: String, was: String = "") -> String:
	if was != "" and was != holder:
		return LINE_STEAL % [shown(resource), holder, was]
	return LINE_TAKE % [shown(resource), holder]


static func free_line(resource: String) -> String:
	return LINE_FREE % shown(resource)


static func is_resource(r: String) -> bool:
	return RESOURCES.has(r)


## WHICH DEVICE THIS ONE MAY NOT BE OPEN BESIDE, or "" for one that stands
## alone.
static func excluded_by(resource: String) -> String:
	return String(EXCLUDES.get(resource, ""))


# ── the live half ────────────────────────────────────────────────────────────

## resource -> {holder, mode}. Absent means free; there is no third state.
var _held := {}
## Takes and releases this session, for the panel.
var _takes := 0
var _releases := 0
var _steals := 0


func _init() -> void:
	_load_stats()


## TAKE A DEVICE. Returns whether it is yours afterwards.
func take(resource: String, holder: String, mode: String = "",
		claim: String = CLAIM_DUTY, reason: String = "") -> bool:
	if not is_resource(resource):
		push_warning("broker: no such resource " + resource)
		return false
	# THE SEIZE RULE RUNS FIRST OF ALL.
	var seizer := _seizer(resource, holder)
	if seizer != "":
		return false
	# THE EXCLUSION IS CHECKED BEFORE THE RE-TAKE SHORT CIRCUIT.
	if _excluded_holder(resource, holder) != "":
		return false
	# THE PAIR MOVES TOGETHER WHEN IT MOVES AT ALL.
	var against := excluded_by(resource)
	if against != "":
		var pair_owner := holder_of(against)
		if pair_owner != "" and pair_owner != holder:
			_steal_to(against, pair_owner, holder, mode)
	var owner := holder_of(resource)
	if owner == holder:
		# A RE-TAKE IS NOT AN EVENT, but it MAY upgrade a claim.
		_held[resource]["mode"] = mode
		_held[resource]["claim"] = claim
		if reason != "":
			_held[resource]["reason"] = reason
		return true
	if not may_take(owner, holder):
		return false
	if owner != "":
		_steals += 1
		_held.erase(resource)
		# THE LOSER IS TOLD FIRST, before the winner is recorded.
		released.emit(resource, owner)
		stolen.emit(resource, owner, holder)
	_held[resource] = {"holder": holder, "mode": mode, "claim": claim,
		"reason": reason}
	_takes += 1
	taken.emit(resource, holder)
	noted.emit(take_line(resource, holder, owner))
	_queue_save()
	return true


## ONE DEVICE CHANGES HANDS AGAINST ITS HOLDER'S WILL.
func _steal_to(resource: String, loser: String, winner: String,
		mode: String) -> void:
	_steals += 1
	_held.erase(resource)
	released.emit(resource, loser)
	stolen.emit(resource, loser, winner)
	_held[resource] = {"holder": winner, "mode": mode, "claim": CLAIM_DUTY,
		"reason": ""}
	_takes += 1
	taken.emit(resource, winner)
	noted.emit(take_line(resource, winner, loser))
	_queue_save()


## RELEASE A DEVICE. Only the holder can, and a release by anybody else is
## silently nothing.
func release(resource: String, holder: String) -> void:
	if holder_of(resource) != holder:
		return
	_held.erase(resource)
	_releases += 1
	released.emit(resource, holder)
	noted.emit(free_line(resource))
	_queue_save()
	# THE PAIR MOVES TOGETHER WHEN IT MOVES AT ALL, IN BOTH DIRECTIONS.
	var against := excluded_by(resource)
	if against != "" and holder_of(against) == holder:
		release(against, holder)


## EVERYTHING THIS HOLDER HAS. Called when a seam shuts down.
func release_all(holder: String) -> void:
	for r: String in RESOURCES:
		release(r, holder)


## LAW 3, IN ONE FUNCTION. Everything held under a mode goes when the mode
## does. An empty `mode` argument releases nothing.
func release_mode(mode: String) -> Array:
	if mode == "":
		return []
	var gone: Array = []
	for r: String in RESOURCES:
		var e: Variant = _held.get(r, null)
		if e == null or String((e as Dictionary)["mode"]) != mode:
			continue
		gone.append(r)
		release(r, String((e as Dictionary)["holder"]))
	return gone


## WOULD A TAKE SUCCEED RIGHT NOW? A pure question: it takes nothing and
## changes nothing.
func can_take(resource: String, holder: String) -> bool:
	if not is_resource(resource):
		return false
	if _seizer(resource, holder) != "":
		return false
	if _excluded_holder(resource, holder) != "":
		return false
	var owner := holder_of(resource)
	return owner == holder or may_take(owner, holder)


## THE ONE "WHY NOT", IN ONE SENTENCE. Empty when the road is clear.
func why_not(resource: String, holder: String) -> String:
	if not is_resource(resource):
		return "there is no such thing as a %s" % resource
	var seizer := _seizer(resource, holder)
	if seizer == HOLDER_RIG:
		return "the rig has the camera - it waits for CUT"
	if seizer != "":
		return "%s has the whole room" % seizer
	var blocked := _excluded_holder(resource, holder)
	if blocked != "":
		return "%s has the %s, and both cannot be open" % [
			blocked, shown(excluded_by(resource))]
	var owner := holder_of(resource)
	if owner != "" and owner != holder and not may_take(owner, holder):
		return "%s has the %s" % [owner, shown(resource)]
	return ""


## IS THIS DEVICE BEING WATCHED, rather than merely sampled?
func continuous(resource: String) -> bool:
	var e: Variant = _held.get(resource, null)
	return e != null and String((e as Dictionary).get("claim", CLAIM_DUTY)) \
		== CLAIM_CONTINUOUS


func claim_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary).get("claim", CLAIM_DUTY))


## THE NAME ON A CLAIM, for the panel and for a leak hunt.
func reason_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary).get("reason", ""))


## WHO, IF ANYBODY, HAS TAKEN THE WHOLE ROOM AND SHUT `holder` OUT OF IT.
func _seizer(resource: String, holder: String) -> String:
	for other: String in SEIZES.keys():
		if other == holder:
			continue
		if not (SEIZES[other] as Array).has(resource):
			continue
		if not held_by(other).is_empty():
			return other
	return ""


## Who has it, or "" for free. THE WHOLE TRUTH about a device, in one lookup.
func holder_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary)["holder"])


## Which screen a hold belongs to, or "" for an ambient one.
func mode_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary)["mode"])


## WHO, IF ANYBODY, BLOCKS `holder` FROM `resource` BY THE EXCLUSION RULE.
func _excluded_holder(resource: String, holder: String) -> String:
	var against := excluded_by(resource)
	if against == "":
		return ""
	var other := holder_of(against)
	if other == "" or other == holder:
		return ""
	if may_take(other, holder):
		return ""
	return other


func is_held(resource: String) -> bool:
	return _held.has(resource)


## HOW MANY DEVICES ARE OUT RIGHT NOW.
func held_now() -> int:
	return _held.size()


func held_by(holder: String) -> Array:
	var out: Array = []
	for r: String in RESOURCES:
		if holder_of(r) == holder:
			out.append(r)
	return out


func takes() -> int:
	return _takes


func releases() -> int:
	return _releases


func steals() -> int:
	return _steals


## One line for the instrument panel: every device and who has it, including
## the free ones.
func line() -> String:
	var parts: Array = []
	for r: String in RESOURCES:
		var h := holder_of(r)
		if h == "":
			parts.append("%s -" % shown(r))
			continue
		parts.append("%s %s%s" % [shown(r), h,
			"*" if continuous(r) else ""])
	return "held  " + "  ·  ".join(PackedStringArray(parts))


# ── persistence (lifetime counters only — see the file doc) ────────────────


func _queue_save() -> void:
	if not autosave or _save_pending:
		return
	_save_pending = true
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		var t: SceneTreeTimer = (loop as SceneTree).create_timer(
			float(SAVE_DEBOUNCE_MS) / 1000.0)
		t.timeout.connect(_flush_save)
	else:
		_flush_save.call_deferred()


func _flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	save_stats()


## Write the counters now, debounce or no debounce.
func save_stats() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"takes": _takes, "releases": _releases, "steals": _steals,
	}))
	f.close()


# ── W8d: contended doors for organs and add-ons ─────────────────────────────
#
# ONE HOLDER PER DOOR. This is a SEPARATE, simpler table from `_held` above:
# `_held`/`take`/`release` is the four-law resource policy (priority, seize,
# exclusion, steal) for the four named devices; `acquire`/`release`/`holder`
# below is the flat "first asker keeps it" rule W8d's add-on contract needs
# for an arbitrary door name (`"camera"`, `"mic"`, `"speaker"`, `"radio"`,
# or an add-on's own `"wifi"`). Organs go through `acquire` first, so an
# add-on asking for a door an organ already holds gets `false`, loudly.

var _acquired: Dictionary = {}  # door:String -> holder:String


## TAKE A CONTENDED DOOR. True if `who` now holds it (already holding it is
## still true); false, loudly, when somebody else does.
func acquire(door: String, who: String) -> bool:
	if door == "" or who == "":
		return false
	var owner: String = String(_acquired.get(door, ""))
	if owner == "" or owner == who:
		_acquired[door] = who
		return true
	push_warning("broker: %s wants door %s, %s already holds it" % [who, door, owner])
	return false


## GIVE A DOOR BACK. Only the holder may; anybody else's release is silently
## nothing, same as [method release] above.
func release_door(door: String, who: String) -> void:
	if String(_acquired.get(door, "")) == who:
		_acquired.erase(door)


## WHO HOLDS A CONTENDED DOOR, or "" for free.
func holder(door: String) -> String:
	return String(_acquired.get(door, ""))


## EVERY DOOR THIS HOLDER HAS THROUGH [method acquire], for a detach.
func release_all_doors(who: String) -> void:
	for door in _acquired.keys().duplicate():
		if String(_acquired[door]) == who:
			_acquired.erase(door)


func _load_stats() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d := parsed as Dictionary
	_takes = int(d.get("takes", 0))
	_releases = int(d.get("releases", 0))
	_steals = int(d.get("steals", 0))
