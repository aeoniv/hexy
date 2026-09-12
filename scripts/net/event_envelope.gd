extends RefCounted
class_name EventEnvelope
## The wire shape of every fabric event. Pure data, no transport knowledge:
## the same dictionary rides LanMesh datagrams and Android IxMesh payloads.
##
##   eid  unique event id, minted once at the origin. Dedup keys on this, not
##        on transport sequence numbers — a relayed event keeps its eid while
##        its transport seq is reminted on every hop.
##   src  origin fabric id (NOT the transport peer id: after a relay the
##        transport id is the relay's, the src still names who spoke).
##   kind String tag the app matches on.
##   body Dictionary payload.
##   ttl  hops this envelope may still travel. Decremented on each relay; an
##        envelope received with ttl 1 has spent its last hop and is delivered
##        but not passed on.
##   prov "self" (the origin claims it) or "witnessed" (the origin saw someone
##        else do it). Provenance only — no scoring. Invitation, not gamification.

const KEYS := ["eid", "src", "kind", "body", "ttl", "prov"]
const PROV_SELF := "self"
const PROV_WITNESSED := "witnessed"


## Relays this envelope has already crossed. Additive and optional, exactly the
## way `geo` is: a peer on an older build sends none and `hops_of()` reads that
## as 0, which is what it was. ttl cannot answer this question — it is capped
## per event kind (a geo heartbeat leaves at ttl=1) so the same number means
## "fresh from the origin" and "one hop out" depending on the sender.
##
## The one thing that needs the answer: a transport-level fact about a peer —
## how strong the link is, how near they are — describes the phone that HANDED
## us the bytes, and only a hops=0 envelope proves that phone is also the one
## that spoke. See MeshFabric._peer_src.
static func make(eid: String, src: String, kind: String, body: Dictionary,
		ttl: int, prov: String) -> Dictionary:
	return {"eid": eid, "src": src, "kind": kind, "body": body,
		"ttl": maxi(0, ttl), "prov": prov, "hops": 0}


static func hops_of(d: Dictionary) -> int:
	return int(d.get("hops", 0))


static func is_valid(d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	for k in KEYS:
		if not d.has(k):
			return false
	if not (d["eid"] is String and d["src"] is String and d["kind"] is String):
		return false
	if not (d["body"] is Dictionary):
		return false
	# JSON round-trips ints as floats, so accept both and coerce on read.
	if not (d["ttl"] is int or d["ttl"] is float):
		return false
	return d["prov"] == PROV_SELF or d["prov"] == PROV_WITNESSED


static func ttl_of(d: Dictionary) -> int:
	return int(d.get("ttl", 0))


## Body keys a relay refuses to carry. PRIVACY LAW (docs/ROADMAP.md): raw
## coordinates are a gift between peers who are actually present with each
## other, so they cross one session and stop. Presence already caps a
## geo-bearing heartbeat at ttl=1 so it is never relayed at all — this is the
## far half of the same law, the one that holds even if a peer (or a future
## kind) forgets to set the ttl.
## `head` joined `geo` for the same reason: which way a person is facing is a
## fact about their body in a room, and it is a gift to the people standing in
## that room with them — not something a stranger's phone gets to forward on.
## `ask` and `answer` joined for a routing reason rather than a bodily one
## (Phase 4, scripts/net/peer_minds.gd): a question is addressed to ONE peer and
## is meaningless to everybody else, so a phone in the middle has no business
## carrying it onward. Both already ride at ttl=1 and are never handed to a
## relay; this is the half that holds anyway.
##
## NOT here, deliberately: `cap`. The capability beacon is an ADVERTISEMENT —
## "there is a mind over here" — and a thing whose whole purpose is to be
## findable loses nothing by being forwarded and gains the peer two hops out.
## The rule this list encodes is not "everything optional is private"; it is
## "facts about a body in a room stop in that room". A beacon is not one.
## `receipt` joined for the same routing reason `ask` and `answer` did (Phase 4
## step b, scripts/net/ledger.gd): a receipt settles ONE question between the
## two phones that asked and answered it. It names them both, it is verifiable
## only by the peer that holds the matching answer, and a phone in the middle
## that forwarded it would be spreading a record of who owed whom around a room
## that has no business holding one. Rides at ttl=1 like the ask it settles;
## this is the half that holds anyway.
##
## NOT here, and this is step (c)'s one privacy ruling rather than an oversight:
## `sync`, the tangle's summary/want/give messages (scripts/net/tangle.gd).
## A MINTED receipt stays exactly where it is on this list — that message
## settles one question between two phones and is nobody else's business. A SYNC
## message is a different thing under a different key, and it RELAYS.
##
## The argument, since a receipt travels inside one of them. A receipt's fields
## are two fabric ids, a correlation id, two parent hashes, an integer amount, a
## unix timestamp and a signature. There are no coordinates in it, no heading,
## no prompt text and no answer text. The law this list encodes is "facts about
## a body and a mind in a room stop in that room" — geo and head are the body,
## ask and answer are the mind, and a settled receipt is neither: it is a ledger
## entry saying that one favour was done. A shared ledger that stopped at one
## hop would not be shared, and being shared is the whole of what a tangle is
## for; partition merge, approval weight and re-sync between long-separated
## peers all require that a receipt outlive the two phones that made it.
## The point-to-point mint is where the privacy lives; the sync is where the
## ledger lives, and they are deliberately two different messages so that
## keeping one private does not cost the other its purpose.
##
## `witness` joined in Phase 5 step 3 (scripts/body/practice.gd), and it joined
## for BOTH reasons at once. Routing: an offer names one peer and the signature
## comes back to one peer, so a phone in the middle has nothing to do with it.
## Body: the thing being vouched for is a person practising in a room, which is
## the same class of fact as `geo` and `head` — even reduced to a hash and a
## minute count, "somebody was exercising here for twelve minutes" is not a
## sentence a stranger's phone gets to forward. Rides at ttl=1 like the ask it
## resembles; this is the half that holds anyway.
##
## `notes` joined in Phase 8 (scripts/brain/notes.gd), and it is the strictest
## entry on this list because it is the only one with no wire kind at all. A
## note is a line a person asked their own phone to keep - "gym bag in the car",
## "call back on tuesday" - and there is no message in this app that carries
## one, no peer path that could ask for one, and no relay that has ever seen
## one. It is on this list anyway, and deliberately: this list is the half of
## the privacy law that holds WHEN SOMEBODY FORGETS. A future kind that put a
## note in a body by mistake would have it stripped at the first relay, and the
## test that greps this constant is the reason that mistake gets caught in a
## suite rather than in a room.
##
## `chirp`, `arrival` and `rave` joined in Phase 18b (scripts/net/chirp_sync.gd),
## and they joined for BOTH reasons at once, like `witness` did. Routing: the
## three of them settle one question — what time is it over there — between two
## phones that are breathing the same body of air, and the arrival instant of a
## 50 ms sweep is not merely uninteresting to a phone two hops away, it is
## MEANINGLESS there: that phone could not have heard the sound, so the number
## describes a room it was never in. Body: a chirp is a measurement of two
## phones' distance from one speaker, which is the same class of fact as `geo` —
## "these two devices were close enough to hear each other" is exactly the
## co-presence proof the receipts ruling cares about, and it stops in the room
## that made it. All three already ride at ttl=1 and are never handed to a
## relay; this is the half that holds anyway.
## `track_want` and `track_chunk` joined in R4 (scripts/net/track_pool.gd), and
## they joined for the ROUTING reason alone — there is nothing bodily about a
## song. A want names ONE holder ("send me chunks 8 through 15 of this hash") and
## is meaningless to every other phone, exactly as `ask` is; a chunk is that
## holder's answer to that one asker. Both ride at ttl=1 and are never handed to
## a relay, and this is the half that holds if a future kind forgets. There is
## also a blunter argument that the other entries on this list do not need: a
## relayed chunk is the same kilobyte crossing a crowded room twice, and a
## six-megabyte track is eight thousand of them.
##
## NOT here, and it is the same ruling `cap` got: `track_offer`. An offer is an
## ADVERTISEMENT — "there is a song over here, 6 MB, here is its hash" — and a
## thing whose whole purpose is to be findable loses nothing by being forwarded
## and gains a phone two hops out a track it can then ask for and pull directly.
## It carries no coordinates, no heading and no text; it carries a hash, a size
## and a filename somebody deliberately handed to a room.
##
## `live_frame` joined in R5 (scripts/net/live_stream.gd), and it joined for BOTH
## reasons, the way `chirp` did. Routing: a frame carries the instant it is meant
## to SOUND, and a phone one relay-hop away receives it after that instant has
## passed — the datagram is not merely uninteresting there, it is USELESS, and a
## receiver would throw it away as late. Body: eight milliseconds of a room's air
## is the most literal "fact about a body in a room" on this list; it is what the
## people standing there can hear, and a stranger's phone does not get to forward
## it onward. There is also the blunt argument `track_chunk` has, multiplied by a
## hundred and twenty five: a relayed frame is the same kilobyte crossing a
## crowded room twice, every eight milliseconds, forever.
##
## NOT here, and it is the ruling `cap` and `track_offer` got: `live_start` and
## `live_stop`. They are ANNOUNCEMENTS — "there is a sound happening over here",
## "it has finished" — carrying a stream id, a sample rate, a channel count and a
## frame length. No coordinates, no heading, no text and no audio. A thing whose
## whole purpose is to be findable loses nothing by being forwarded.
const PRIVATE_BODY_KEYS := ["geo", "head", "ask", "answer", "receipt", "witness",
	"notes", "chirp", "ready", "arrival", "rave", "clock",
	"track_want", "track_chunk", "live_frame"]


## A copy of this envelope one hop further out. Everything but ttl and the
## private keys is preserved, so dedup at the far end still recognises the
## original event.
static func relayed(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["ttl"] = maxi(0, ttl_of(d) - 1)
	out["hops"] = hops_of(d) + 1
	if out.get("body") is Dictionary:
		for k in PRIVATE_BODY_KEYS:
			out["body"].erase(k)
	return out
