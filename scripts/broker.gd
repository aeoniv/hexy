extends Node
## THE RESOURCE BROKER — Phase 12, M1. One door onto the camera, the microphone
## and the loudspeaker.
##
## Owner, 2026-08-25, after the field: "messy, very confusing, many bugs, one
## button calling other function, user has no idea what is going on." One of the
## reasons for all four is in this file's absence. Three devices, four
## subsystems that want them, and until now every arrangement between those
## subsystems was AD HOC and written somewhere else:
##
##   * `BodySense.hold()` existed because the finder needed the back camera and
##     the face window had the front one, and most phones will not bind both.
##     main.gd called it on the find's armed edge — one line, in a lambda, in a
##     file of two thousand.
##   * `WorldSense.look()` refuses while a find is armed, by reading its own
##     `_find_armed` flag, because there is one camera.
##   * The mouth-then-ear rule lives inside VoiceSense's queue.
##
## Each of those is right. Together they are a policy nobody can read, held in
## three files, with no record of who has what — so when the app does something
## surprising there is nothing to look at. THIS FILE IS THE THING TO LOOK AT.
##
## FOUR LAWS.
##
## 1. ONE DOOR. A hold is [take] and a release is [release], and there is no
##    third verb. `holder_of()` is the whole truth about a device at any moment,
##    and it is one dictionary lookup.
##
## 2. EVERY MOVE IS WRITTEN DOWN. Each take, release and steal emits [noted]
##    with one line — `camera -> find`, `camera -> free`, `camera -> look (was
##    face)` — and main.gd puts those lines in the transcript. The owner's
##    complaint is that a person has no idea what is going on; a device changing
##    hands is exactly the kind of thing they have no idea about, and it is now
##    on the glass with everything else that happened.
##
## 3. ORPHANED HOLDS ARE UNREPRESENTABLE. Every hold records the MODE it was
##    taken under, and leaving a mode calls [release_mode], which drops all of
##    them. A camera left running by a screen nobody is looking at cannot
##    survive a mode switch, whatever the subsystem holding it believes.
##
## 4. THE LOSER OF A STEAL IS TOLD. A higher-priority take does not silently
##    take a device out from under somebody: [stolen] fires with both names, and
##    the seam that lost it hears about it and stands down. Silent preemption is
##    how a duty cycle becomes a camera that never closes.
##
## WHAT M1 DELIBERATELY DOES NOT DO. It changes no observable behaviour. The
## priorities below are chosen to reproduce exactly what the ad-hoc holds already
## did: a find or a look beats the face window (that was `hold()`), and a look
## does not beat a find (that was `look()`'s own refusal). This file is where the
## policy now LIVES; it is not yet a different policy.

## A device changed hands. `line` is the whole of what a person is shown.
signal noted(line: String)
## Taken, released, or taken away. Three signals rather than one with a verb,
## because every subscriber this app has cares about exactly one of them.
signal taken(resource: String, holder: String)
signal released(resource: String, holder: String)
## LAW 4. `loser` had it, `winner` has it now. The loser's seam listens for its
## own name and stands down; nothing else may act on this.
signal stolen(resource: String, loser: String, winner: String)

## THE THREE DEVICES. There is no fourth, and the list is closed on purpose: a
## broker that brokered "resources" in general would be a registry, and a
## registry is a thing you can put anything in. These are the three pieces of
## hardware that can be pointed at a person.
const CAMERA := "camera"
const MIC := "mic"
const SPEAKER := "speaker"
const RESOURCES := [CAMERA, MIC, SPEAKER]

## WHO ASKS. Also closed, and also on purpose — a holder name that is not on this
## list is a subsystem nobody decided the priority of.
const HOLDER_FIND := "find"
const HOLDER_LOOK := "look"
const HOLDER_FACE := "face"
const HOLDER_EAR := "ear"
const HOLDER_MOUTH := "mouth"
## PHASE 18c — THE CHIRP CLOCK IS A HOLDER, and the field is why. The Fold 4's
## loopback self test recorded 24000 samples at an rms of 0.0017: a microphone
## that was OPEN and delivering near-silence, while the speaker demonstrably
## moved. Android 10+ gives a speech-recognition service the capture, and every
## other AudioRecord client SILENCED frames — and Hexy's own recognizer was
## armed at the time. The chirp's AudioRecord had bypassed this file entirely
## and got exactly what the OS promises. It asks now, like everything else.
const HOLDER_CHIRP := "chirp"
const HOLDERS := [HOLDER_FIND, HOLDER_LOOK, HOLDER_FACE, HOLDER_EAR,
	HOLDER_MOUTH, HOLDER_CHIRP]

## WHO WINS, AND IT IS THE POLICY THAT ALREADY EXISTED, WRITTEN DOWN.
##
##   face (0)  is the ambient one. It samples 1.5 s in every 30 and it is the
##             only holder here that nobody asked for by pressing anything, so
##             it is the only one that can be taken from. `BodySense.hold()` was
##             this number.
##   find (1)  and look (1) are EQUAL, and the equality is load-bearing: a look
##             may not interrupt a find (WorldSense.look has refused that since
##             Phase 11) and a find may not interrupt a look either. Equal
##             priority means the second one is REFUSED rather than served, which
##             is exactly what both doors already did.
##   ear (1)   and mouth (1) never contend with anything: they are the only
##             holders of their devices. They are here so that the mic and the
##             loudspeaker are on the record too — a person who wants to know
##             what has their microphone should not have to know that it is a
##             different kind of question from what has their camera.
const PRIORITY := {
	HOLDER_FACE: 0,
	HOLDER_FIND: 1,
	HOLDER_LOOK: 1,
	HOLDER_EAR: 1,
	HOLDER_MOUTH: 1,
	# chirp (2) BEATS THE EAR AND THE MOUTH, and it is the only holder in this
	# file that beats anything a person pressed for. The argument: a sync round
	# and a chirp test are also things a person pressed for, they last half a
	# second each, and they are the ONLY holders whose measurement is destroyed
	# by sharing. An ear that loses the microphone hears its steal (law 4) and
	# stands down loudly; a round that could not get the microphone refuses
	# aloud rather than recording the OS's silence and blaming the room.
	HOLDER_CHIRP: 2,
}

## PHASE 12 M2 — TWO DEVICES THAT MAY NOT BOTH BE OPEN, and the field found out
## why the hard way.
##
## The Fold's log: LOOK spoke `a keyboard` while FIND's ear was still open, the
## recognizer heard the loudspeaker, and the next line is `find refused - unknown
## word "a keyboard"`. Hexy searched for what Hexy had just said. The
## mouth-then-ear law has been in this app since Phase 7, but it was only ever
## enforced for the ONE utterance that opens an ear (`say_then_listen`); any
## OTHER speech, from any other lane, while any ear happened to be open, went
## straight into the microphone.
##
## A rule that holds for one road and not the others is not a rule, it is a
## habit. This is the rule: the microphone and the loudspeaker are MUTUALLY
## EXCLUSIVE, and it is here rather than in the voice seam because "these two
## devices may not both be open" is exactly the sentence this file exists to
## hold. VoiceSense still owns what to DO about it — queue the line and say it
## when the ear shuts — because that is a decision about speech, not about
## hardware.
##
## THE EXCLUSION IS BETWEEN TWO HOLDERS, NOT BETWEEN TWO DEVICES — Phase 18c.
## The rule exists because the recognizer must not hear the loudspeaker; it does
## NOT exist because a microphone and a speaker cannot both be open. The chirp
## clock's whole measurement is one holder emitting a sweep and recording it, and
## a rule that refused that would be refusing the fault it was written to fix,
## upside down. So: a holder that already has one of the pair may take the other,
## and nobody else may while it does. See [_excluded_holder].
const EXCLUDES := {
	MIC: SPEAKER,
	SPEAKER: MIC,
}

## The lines. One shape for a take, one for a release, one for a steal, and they
## are format strings so a test reads the same sentence a person does.
const LINE_TAKE := "%s -> %s"
const LINE_FREE := "%s -> free"
const LINE_STEAL := "%s -> %s (was %s)"


# ── the pure half ────────────────────────────────────────────────────────────
# Who beats whom, and what it reads as. Both are static so the whole policy is
# assertable with no node, no device and no clock.


static func priority_of(holder: String) -> int:
	# AN UNKNOWN HOLDER IS THE LOWEST, never the highest. A name nobody has
	# decided about must not be able to take a camera off a name somebody did.
	return int(PRIORITY.get(holder, -1))


## MAY `taker` TAKE IT FROM `owner`? Free is always yes; the same holder asking
## twice is always yes (a re-take is a no-op, not a steal); otherwise STRICTLY
## higher wins, which is what makes find/look equal mean "refused".
static func may_take(owner: String, taker: String) -> bool:
	if owner == "" or owner == taker:
		return true
	return priority_of(taker) > priority_of(owner)


static func take_line(resource: String, holder: String, was: String = "") -> String:
	if was != "" and was != holder:
		return LINE_STEAL % [resource, holder, was]
	return LINE_TAKE % [resource, holder]


static func free_line(resource: String) -> String:
	return LINE_FREE % resource


static func is_resource(r: String) -> bool:
	return RESOURCES.has(r)


## WHICH DEVICE THIS ONE MAY NOT BE OPEN BESIDE, or "" for one that stands alone.
## The camera stands alone: there is nothing about a camera that a microphone
## makes untrue.
static func excluded_by(resource: String) -> String:
	return String(EXCLUDES.get(resource, ""))


# ── the live half ────────────────────────────────────────────────────────────

## resource -> {holder, mode}. Absent means free; there is no third state and no
## "reserved".
var _held := {}
## Takes and releases this session, for the panel. A pair, like every other
## counter in this app: 40 takes and 12 releases is a leak, and one number alone
## would not say so.
var _takes := 0
var _releases := 0
var _steals := 0


## TAKE A DEVICE. Returns whether it is yours afterwards.
##
## `mode` is the screen this hold belongs to, and it is what makes law 3 work.
## An empty mode is a hold that belongs to no screen — the face window is the
## only one, because BodySense samples whatever is on screen — and such a hold
## survives a mode switch, which is the whole difference between "ambient" and
## "orphaned".
func take(resource: String, holder: String, mode: String = "") -> bool:
	if not is_resource(resource):
		push_warning("broker: no such resource " + resource)
		return false
	# THE EXCLUSION IS CHECKED BEFORE ANYTHING ELSE, including the re-take short
	# circuit: a mouth that already had the loudspeaker when an ear opened must
	# still be refused its next sentence, or the rule would hold only for the
	# first one.
	if _excluded_holder(resource, holder) != "":
		return false
	# THE PAIR MOVES TOGETHER WHEN IT MOVES AT ALL — Phase 18d. The exclusion
	# above has already ruled that this holder outranks whoever has the paired
	# device (see [_excluded_holder]); leaving that holder in place would mean a
	# chirp recording its own room while a mouth was still speaking into it, which
	# is the exact fault the exclusion exists to prevent, merely with the winner's
	# name on it. So the paired device comes across too, as a steal, with the loser
	# told (law 4) — and ChirpSense's second `take(SPEAKER)` is then a no-op.
	var against := excluded_by(resource)
	if against != "":
		var pair_owner := holder_of(against)
		if pair_owner != "" and pair_owner != holder:
			_steal_to(against, pair_owner, holder, mode)
	var owner := holder_of(resource)
	if owner == holder:
		# A RE-TAKE IS NOT AN EVENT. `_open_ear` can be reached twice for one
		# ear, and a second `mic -> ear` line would be the record saying
		# something happened that did not.
		_held[resource]["mode"] = mode
		return true
	if not may_take(owner, holder):
		return false
	if owner != "":
		_steals += 1
		_held.erase(resource)
		# THE LOSER IS TOLD FIRST, and before the winner is recorded: a seam that
		# hears it lost the camera must find the broker already believing that,
		# or its own `release` on the way down would take the winner's hold off.
		released.emit(resource, owner)
		stolen.emit(resource, owner, holder)
	_held[resource] = {"holder": holder, "mode": mode}
	_takes += 1
	taken.emit(resource, holder)
	noted.emit(take_line(resource, holder, owner))
	return true


## ONE DEVICE CHANGES HANDS AGAINST ITS HOLDER'S WILL. Factored out of [take] so
## the pair-steal above and the ordinary steal below cannot drift apart: the
## loser is told FIRST, before the winner is recorded, for the reason [take]
## already gives — a seam that hears it lost a device must find this file already
## believing that, or its own `release` on the way down frees the new holder's.
func _steal_to(resource: String, loser: String, winner: String,
		mode: String) -> void:
	_steals += 1
	_held.erase(resource)
	released.emit(resource, loser)
	stolen.emit(resource, loser, winner)
	_held[resource] = {"holder": winner, "mode": mode}
	_takes += 1
	taken.emit(resource, winner)
	noted.emit(take_line(resource, winner, loser))


## RELEASE A DEVICE. Only the holder can, and a release by anybody else is
## silently nothing — that is not politeness, it is what stops the stale
## `release` at the bottom of a stolen seam from freeing the new holder's device.
func release(resource: String, holder: String) -> void:
	if holder_of(resource) != holder:
		return
	_held.erase(resource)
	_releases += 1
	released.emit(resource, holder)
	noted.emit(free_line(resource))


## EVERYTHING THIS HOLDER HAS. Called when a seam shuts down.
func release_all(holder: String) -> void:
	for r: String in RESOURCES:
		release(r, holder)


## LAW 3, IN ONE FUNCTION. Everything held under a mode goes when the mode does.
## An empty `mode` argument releases nothing: leaving a screen must not take the
## ambient face window down with it, and "" is how a hold says it has no screen.
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


## WOULD A TAKE SUCCEED RIGHT NOW? Asked by a seam that wants to know whether to
## queue rather than to grab — the mouth asks it before every sentence. A pure
## question: it takes nothing and changes nothing.
func can_take(resource: String, holder: String) -> bool:
	if not is_resource(resource):
		return false
	if _excluded_holder(resource, holder) != "":
		return false
	var owner := holder_of(resource)
	return owner == holder or may_take(owner, holder)


## Who has it, or "" for free. THE WHOLE TRUTH about a device, in one lookup.
func holder_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary)["holder"])


## Which screen a hold belongs to, or "" for an ambient one.
func mode_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary)["mode"])


## WHO, IF ANYBODY, BLOCKS `holder` FROM `resource` BY THE EXCLUSION RULE. "" is
## a clear road: either the paired device is free, or `holder` is the one that
## has it, which is the same holder using two devices and not two holders using
## one room. Named rather than inlined because [take] and [can_take] must answer
## it identically, and once they did not.
func _excluded_holder(resource: String, holder: String) -> String:
	var against := excluded_by(resource)
	if against == "":
		return ""
	var other := holder_of(against)
	if other == "" or other == holder:
		return ""
	# PHASE 18d — THE EXCLUSION IS A RULE BETWEEN EQUALS, AND THE FIELD PROVED IT
	# HAS TO BE. Two phones, one working sync round each, and then nothing: the
	# second round always refused with `the microphone is busy`, and so did the
	# other handset when it tried to answer an announce. The cause is four lines
	# up from here. A round ENDS BY SPEAKING its verdict — "clock to bee: +12.3
	# ms" — and speaking takes the loudspeaker for the mouth; the next take of the
	# MICROPHONE then hit this rule, which ran BEFORE the priority check and so
	# refused a holder that outranks the mouth by design. One direction, once
	# only, forever after: the phone that had spoken could be neither an initiator
	# nor a hearer again until its own sentence finished, and on a handset whose
	# TTS-done callback is late that is never.
	#
	# The rule was written so a RECOGNIZER would not hear a LOUDSPEAKER — two
	# holders of equal rank, neither with a claim on the other. It was never a
	# statement that the hardware cannot both be open; [EXCLUDES]' own header says
	# so, and HOLDER_CHIRP exists precisely to emit and record as one measurement.
	# So a STRICTLY higher-priority taker is not blocked here: it preempts, and
	# [take] brings the paired device across with it. Equal ranks — ear against
	# mouth, the pair this rule was written for — are refused exactly as before.
	if may_take(other, holder):
		return ""
	return other


func is_held(resource: String) -> bool:
	return _held.has(resource)


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


## One line for the instrument panel: every device and who has it, including the
## free ones. The free ones are the point — a row that only listed what was held
## would make "nothing has the camera" and "the panel is broken" look the same.
func line() -> String:
	var parts: Array = []
	for r: String in RESOURCES:
		var h := holder_of(r)
		parts.append("%s %s" % [r, h if h != "" else "-"])
	return "held  " + "  ·  ".join(PackedStringArray(parts))
