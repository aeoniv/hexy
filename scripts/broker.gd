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

## THE FOUR DEVICES. The list is closed on purpose: a broker that brokered
## "resources" in general would be a registry, and a registry is a thing you can
## put anything in. These are the pieces of hardware that can be pointed at a
## person.
##
## PHASE 19 — THERE ARE TWO CAMERAS, AND PRETENDING THERE WAS ONE COST US THE
## WHOLE CONTENTION STORY. `CAMERA` was a single resource, so "the face window
## has the camera" and "a find has the camera" were the same sentence about two
## different lenses, and every lane that needed to know WHICH went and asked
## somewhere else — which is how four separate contention systems grew up
## outside this file. The front lens and the back lens are named, and the fact
## that most of these phones cannot bind both at once is stated ONCE, as an
## exclusion between them, instead of four times as an accident.
const FRONT_LENS := "front_lens"
const BACK_LENS := "back_lens"
## The two of them, in the order a person would name them.
const LENSES := [FRONT_LENS, BACK_LENS]
const MIC := "mic"
const SPEAKER := "speaker"
const RESOURCES := [FRONT_LENS, BACK_LENS, MIC, SPEAKER]

## WHAT A PERSON READS. The ids above are keys; these are the words that go in
## the transcript, because `front_lens -> deck` is a log line and "front lens ->
## deck" is a sentence.
const SHOWN := {
	FRONT_LENS: "front lens",
	BACK_LENS: "back lens",
	MIC: "mic",
	SPEAKER: "speaker",
}

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
## PHASE 19 — THE FOUR THAT USED TO ARBITRATE THEMSELVES.
##
## Each of these was a contention system of its own before this pass, and
## between them they were the reason the app's answer to "why did that not open"
## depended on which door you had pressed:
##
##   * `rig`  — a take. `main.gd` asked `cam_session.state_name()` in two
##     hand-written guards, one per deck, and `cam_session` never touched this
##     file at all. A shoot with several people standing in it is the highest
##     claim in the building and it was the only one nothing recorded.
##   * `lens` — the AR session. ARCore takes the camera for ITSELF and fights
##     CameraX on both lenses; `lens_sense.contention()` asked three subsystems
##     three duck-typed questions to work that out, and got the first one wrong
##     for a year.
##   * `pose` — the skeleton lane. It owns no camera: it rides the frames the
##     face window is already producing. It is a holder anyway, so that "what
##     is using the front lens" has one answer and not "the face window, and
##     also something else that came along with it".
##   * `deck` — a screen a person is standing in front of. `BodySense` kept its
##     own dictionary of named holds for exactly this, beside this file, with
##     its own rules about who could take one.
const HOLDER_RIG := "rig"
const HOLDER_LENS := "lens"
const HOLDER_POSE := "pose"
const HOLDER_DECK := "deck"
const HOLDERS := [HOLDER_RIG, HOLDER_LENS, HOLDER_POSE, HOLDER_DECK,
	HOLDER_FIND, HOLDER_LOOK, HOLDER_FACE, HOLDER_EAR,
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
	# PHASE 19, AND EVERY ONE OF THESE NUMBERS REPRODUCES SOMETHING THE APP
	# ALREADY DID. This file is where the policy now LIVES; it is not yet a
	# different policy, and the four additions are chosen to keep it that way.
	#
	# pose (0) rides the face window's frames and owns no camera of its own, so
	#          it ranks with the window it rides. It cannot take a lens from
	#          anything, which is exactly true of it.
	HOLDER_POSE: 0,
	# deck (1) — EQUAL to find and look, and the equality is the behaviour that
	#          already existed: `BodySense.hold_open()` refused while another
	#          lane held the camera, and equal priority is how this file spells
	#          "refused rather than served". A person opening the body screen
	#          during a hunt is told the hunt has the camera; the app does not
	#          end their hunt for them.
	HOLDER_DECK: 1,
	# lens (1) — the AR session, also equal to a find and a look, because that
	#          is what `lens_sense.contention()` already did in both directions:
	#          it refused to open over a look, and a look over an open lens is
	#          the same collision seen from the other side.
	HOLDER_LENS: 1,
	# rig (3)  BEATS EVERYTHING, and it is the only holder here that does. A
	#          take is several people standing in a room around a shutter that
	#          fires in two seconds; nothing one person is looking at on their
	#          own phone outranks that, which is what main.gd's two hand-written
	#          `state_name() == "armed"` guards were saying, badly, in two
	#          places.
	HOLDER_RIG: 3,
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
## PHASE 19 — AND THE TWO LENSES ARE A PAIR IN EXACTLY THE SAME SENSE.
##
## Most of these phones will not bind the front and the back camera at once, and
## ARCore takes the whole camera stack for itself while a session is open. That
## fact was scattered across four files as four different guards. It is one row
## in this table now, and everything the old guards did falls out of the
## machinery that was already here for the microphone and the loudspeaker:
##
##   * A find (back lens) closes the face window (front lens) — the old
##     `BodySense.hold()`, which main.gd used to call from a lambda.
##   * A strictly higher-priority taker PREEMPTS rather than being refused, and
##     [take] brings the paired device across with it, so `holder_of` says what
##     is physically true: the rig has both lenses, because the rig has the
##     camera.
##   * Equal ranks refuse each other, which is find-against-look and now
##     deck-against-find, unchanged.
const EXCLUDES := {
	MIC: SPEAKER,
	SPEAKER: MIC,
	FRONT_LENS: BACK_LENS,
	BACK_LENS: FRONT_LENS,
}

## HOLDERS THAT TAKE THE WHOLE ROOM. A resource-level exclusion says "these two
## may not both be open"; this says "while THIS holder has anything, nobody else
## may have anything on the list".
##
## There is one, and it is the rig. A take is a shutter several phones fire
## together: an ear opening halfway through, or a chirp sweep, or a face window
## waking up on its duty cycle, is a ruined clip that nobody will notice until
## the trim tool. `docs/FIELD.md`'s whole shoot procedure is people arranging
## not to touch anything, and this is that arrangement written down where the
## app can keep it.
const SEIZES := {
	HOLDER_RIG: RESOURCES,
}

## HOW A DEVICE IS BEING USED, and the difference is a battery and a promise.
##
##   DUTY       — the ambient way. `BodySense` opens the front lens for 1.5 s in
##                every 30 to notice whether somebody is there. Nobody is
##                watching the picture; there IS no picture.
##   CONTINUOUS — a screen a person is standing in front of, watching. The duty
##                cycle is suspended for as long as the claim stands, and the
##                plugin will compress frames for the glass, which it will not
##                do under a DUTY claim at all.
##
## This is what `BodySense._open_holds` was: a dictionary of named reasons, kept
## beside this file, with its own rules about who could add one. Reasons rather
## than a counter, so a claim nobody released has a NAME printed beside it —
## that part was right and is kept, as [reason_of].
const CLAIM_DUTY := "duty"
const CLAIM_CONTINUOUS := "continuous"
const CLAIMS := [CLAIM_DUTY, CLAIM_CONTINUOUS]

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


## The word for a device, for a person. Falls back to the id, which is only
## reachable by a caller asking about something that is not a resource.
static func shown(resource: String) -> String:
	return String(SHOWN.get(resource, resource))


## WHICH RESOURCES THIS HOLDER TAKES THE WHOLE ROOM FOR. Empty for every holder
## but the rig. See [SEIZES].
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
func take(resource: String, holder: String, mode: String = "",
		claim: String = CLAIM_DUTY, reason: String = "") -> bool:
	if not is_resource(resource):
		push_warning("broker: no such resource " + resource)
		return false
	# THE SEIZE RULE RUNS FIRST OF ALL, before the exclusion and before the
	# re-take short circuit. A rig that is rolling is not negotiating.
	var seizer := _seizer(resource, holder)
	if seizer != "":
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
		# A RE-TAKE MAY UPGRADE A CLAIM. A screen that opens over an ambient
		# window of its own lane says so by asking again as CONTINUOUS, and the
		# duty cycle must hear that even though nothing changed hands.
		_held[resource]["claim"] = claim
		if reason != "":
			_held[resource]["reason"] = reason
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
	_held[resource] = {"holder": holder, "mode": mode, "claim": claim,
		"reason": reason}
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
	# THE PAIR COMES ACROSS AS A DUTY CLAIM. The winner asked for the OTHER
	# device; this one is being taken away from its holder so the winner can use
	# the one it asked for, and calling that a continuous claim would suspend a
	# duty cycle on behalf of a lane that is not watching anything.
	_held[resource] = {"holder": winner, "mode": mode, "claim": CLAIM_DUTY,
		"reason": ""}
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
	# THE PAIR MOVES TOGETHER WHEN IT MOVES AT ALL, IN BOTH DIRECTIONS. [take]
	# brings the paired device across on a preempt; this is the other half, and
	# it was missing. A find takes the back lens, the front one comes with it
	# because these phones will not bind both — and a find that released only
	# what it asked for left the face window's lens held by a hunt that had
	# ended, shut forever, with nothing in any log to say why.
	var against := excluded_by(resource)
	if against != "" and holder_of(against) == holder:
		release(against, holder)


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
	if _seizer(resource, holder) != "":
		return false
	if _excluded_holder(resource, holder) != "":
		return false
	var owner := holder_of(resource)
	return owner == holder or may_take(owner, holder)


## THE ONE "WHY NOT", IN ONE SENTENCE. Empty when the road is clear; otherwise
## the line a person reads about why their door did not open.
##
## THIS IS THE FUNCTION THE FOUR SYSTEMS WERE. `lens_sense.contention()` asked
## three subsystems three duck-typed questions; main.gd asked `cam_session`
## twice, by hand, in two decks; `BodySense.hold_open` had a fourth answer of
## its own. One reader, one wording, and a test can assert the sentence a person
## will actually see.
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


## IS THIS DEVICE BEING WATCHED, rather than merely sampled? The question
## `BodySense.held_open()` used to answer out of its own dictionary.
func continuous(resource: String) -> bool:
	var e: Variant = _held.get(resource, null)
	return e != null and String((e as Dictionary).get("claim", CLAIM_DUTY)) \
		== CLAIM_CONTINUOUS


func claim_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary).get("claim", CLAIM_DUTY))


## THE NAME ON A CLAIM, for the panel and for a leak hunt. A hold nobody
## released has a name printed beside it; that was the best part of the
## dictionary this replaced.
func reason_of(resource: String) -> String:
	var e: Variant = _held.get(resource, null)
	return "" if e == null else String((e as Dictionary).get("reason", ""))


## WHO, IF ANYBODY, HAS TAKEN THE WHOLE ROOM AND SHUT `holder` OUT OF IT. "" for
## a clear road, including when `holder` is the seizer itself. See [SEIZES].
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
		if h == "":
			parts.append("%s -" % shown(r))
			continue
		# THE CLAIM IS ON THE LINE, because "the front lens is open" and "the
		# front lens is open and somebody is watching it" are different facts
		# about somebody's face and a person is owed the second one.
		parts.append("%s %s%s" % [shown(r), h,
			"*" if continuous(r) else ""])
	return "held  " + "  ·  ".join(PackedStringArray(parts))
