# ix64-hexy

A worn companion that builds discipline by sensing the body, not showing a
screen. Godot 4.7.

## What this is for

**FIND is the product (RULED 2026-08-25, Phase 11).** Hexy finds physical
objects in real time, fully offline: tap FIND, say the thing, and a detector
tracks it at frame rate while a voice steers you — left / right / up / down /
closer / got it — for minutes, on any phone. Everything else orbits that one
excellent feature: the radar finds your *people* the same way FIND finds your
*things*; the game gives the companion a reason to exist between finds.

The assistant ambition (deep talk, VLM-driven find) was field-tested and cut:
on-device 0.6-1.7b models and 17 s/glance vision are below product floor.
What remains of them is honest and small — see "What runs today".

A proposed 機 (jī) economy layer — signed receipts for mesh favors, settled on
a tangle, felt only as Hexy's vitality — is the long game. See
`docs/ROADMAP.md` for the honest built/planned/proposed breakdown.

Three docs, three jobs: `docs/ROADMAP.md` is the reasoning and every phase plan,
written before its code; `docs/SURFACE.md` is the one screen hexy shows and the
index of what Phase 12 produced; `docs/FIELD.md` is the runbook — tests, export,
install, driving a phone over adb, and asking a phone why it died.
`docs/take-format.md` documents `take.json`, the consumer-agnostic clip
manifest `tools/hexcam_take.py` produces from a take directory.

## What runs today (the two engines)

| Engine | Carries | Status |
|---|---|---|
| **MediaPipe** (`ixbody` plugin) | **FIND** — EfficientDet-Lite0 int8 (4.6 MB, embedded), continuous detector + IoU tracker + spoken guidance; **body sense** — face landmarks at 5% duty | the critical path |
| **MNN** (`ixmnn` plugin) | chat mouth (qwen3-1.7b on 8 GiB+ phones, 0.6b below — game dialogue and simple asks, streaming); memory embeddings (gte, 768-d); one-shot **LOOK** (qwen2-vl describes a frame in ~15 s, Fold only, never in the find loop) | demoted but needed |

Around them: an explicit dialog FSM (`turn_machine.gd` — idle/listening/
thinking/speaking, finding as a parallel open-ended lane, watchdogged), a
visible transcript (everything heard and said stays on glass), Android
SpeechRecognizer ears (offline packs, auto-download) and TTS mouth
(`ixvoice`), and the visible-controls law: five labelled buttons, no gestures,
consents default ON and persist.

FIND's vocabulary is the 80 COCO classes plus synonyms; an unknown word gets
one honest sentence naming what it *can* find. No pretending.

## Character

| | v1 (now) | v2 (future) |
|---|---|---|
| Body | Hexy: friendly vector hexagon, zero assets | 3DGS animal-monster creatures |
| World | flat color | 3DGS environment reconstructed from the phone camera |
| Seam | `scripts/hexy.gd` — `notice()` / `glance()` API stays | same API, new body |

## Visits

When devices mesh, their characters visit each other's screens. Presence is
place: every node shouts `presence` (name, hue, position normalized 0..1) on a
slow timer, and each shout draws a smaller, named, differently-coloured Hexy
where its owner stands in their own viewport. Silence for six seconds is a
goodbye — the visitor waves and fades. Tap a visitor and your Hexy walks over
while a `poke` crosses the mesh; theirs double-hops on their screen.

Identity is a name and a hue in `user://identity.cfg`, minted from the fabric
id on first run. `HEXY_NAME` overrides it, which is how one machine hosts two.

## Place

A visitor stands where its owner's *body* is, not where its owner's screen is.
[`Geo`](scripts/social/geo.gd) is one seam over two position sources: the
`IxLoc` Android plugin (FusedLocationProvider) on a phone, and `HEXY_LAT` /
`HEXY_LON` on a desktop, which is how the test rig walks a fake person across a
park without leaving the desk.

**Accuracy is duty-cycled, and that is the difference between a working radar
and a decorative one.** `ACCESS_FINE_LOCATION` is declared uncapped by
[`addons/ixloc`](addons/ixloc/export_plugin.gd) and requested at runtime
alongside coarse; the fused provider runs at `PRIORITY_HIGH_ACCURACY` on a 2 s
interval while the radar dial is open, and drops back to balanced power at 10 s
the moment it shuts — battery is a project law, so GNSS is held only while
somebody is looking at a bearing. Granting only *approximate* location is a
supported state, not an error: fixes stay coarse, nothing is placeable, and the
screen-relative placement below runs exactly as it did before.

On device, indoors, that ladder runs `acc 2000 m` (coarse only) → `100 m` (fine,
balanced) → `20 m` → **`6 m`** (fine, dial open, high accuracy), which is the
difference between a radar that parks everyone on the "direction unknown" ring
and one that draws them where they are standing.

> Historical note, because it cost the whole phase: `ACCESS_FINE_LOCATION` used
> to be declared only by `addons/ixmesh`, with `android:maxSdkVersion="32"`
> (Nearby needs location below API 33 and not above). The manifest merger merges
> attributes as well as names, so on any API 33+ phone the merged manifest
> carried FINE capped away, the app could only ever hold COARSE, and every fix
> was a cell-tower centroid. One attribute, and no bearing ever worked.

When both sides have a fix, the real bearing decides which side of the screen a
visitor appears on (north up, east right — the *room* is a map, only the radar
below is heads-up) and the real distance decides how big
they are: 0.8 at touching distance, the plain 0.55 visitor size at ten metres,
a dot by a hundred. Past a hundred metres they take the same fade path silence
uses. When *either* side lacks a fix — permission denied, indoors, a desktop
with no env, a peer on an older build — nothing changes and the normalized
viewport placement above runs untouched.

A fix has to be fine enough to say where *in a room* somebody stands before it
is allowed to say it. Indoors on balanced power the fused provider answers with
a cached network fix labelled `acc 2000 m`: a real position, honestly reported,
and useless here — two phones on the same table get cell-tower centroids
kilometres apart. Anything coarser than `Geo.PLACEABLE_ACC_M` (50 m, half the
room) counts as no fix at all and takes the screen-relative path, so a visitor
still appears. Believing that number instead is what made two meshed phones
draw nobody; `geo: fix acc=… placeable=…` in logcat is the line that says which
path a device is on.

Coordinates are a gift between present peers, and the code says so twice. A
heartbeat carrying `geo` goes out at `ttl=1`, so it reaches the peers in this
session and stops; and `EventEnvelope.relayed()` strips `geo` from any body it
forwards, which holds even if a future event kind forgets its ttl. Nothing is
written to disk, and nothing leaves the devices standing next to each other.

```
HEXY_LAT=52.5200 HEXY_LON=13.4050 HEXY_NAME=alpha Godot_v4.7.1 --path .
HEXY_LAT=52.5201 HEXY_LON=13.4050 HEXY_NAME=beta  Godot_v4.7.1 --path .
```

## Radar — locate the others

The visit screen answers *who is here*. The compass button in the corner swaps
it for a dial that answers *where are they*: same registry, same fixes, drawn as
a **north-up** radar with your Hexy small in the middle and one labelled blip per
peer currently in session.

A blip's angle is the real bearing from your fix to theirs
([`Geo.bearing_deg`](scripts/social/geo.gd)), **seen from where the phone is
pointing**: every peer sits at `(their bearing − your heading)`, so the top of
the screen is the way you are looking and turning the phone sweeps the other
people round the dial until the one you want is at the top. Heading comes from
the rotation-vector sensor via `IxLoc.heading_changed`. With no compass (a
desktop, a phone with no magnetometer) nothing rotates at all and the dial is a
plain north-up map — which is the truth, not "facing north".

**Your own heading is never drawn.** Not as a cone, not as a nose on your body,
not as a marker or degrees on the rim, not in the caption — *"own hexy viwer is
rotating!!!"*. All of those swept across the screen every time the phone turned,
and between them they were the rotating viewer. The heading is still *used*, to
seat the peers and to swing the four cardinal letters with them; it is simply
never an object of its own. There is no mode switch either: with the cone gone,
a dial that did not apply the heading would have nothing on it that moves.

### Your Hexy is static. Everyone else's moves.

Your own character sits upright in the middle and never rotates — it is the
fixed reference the rest of the screen is read against. There is no point in
having both you and the world turn, and there is less than none in having you
turn while the people you are looking for stand still.

What moves is **the others**. Each peer sits at `(their bearing − your heading)`,
recomputed every time the compass moves, so turning the phone sweeps them round
the screen until the one you want is at the top and you can walk at them. That
is the whole feature.

A peer may also be *rotated in place* to their own heading — that is information
about them, not their position. `hexy.gd` has a `face(deg)` which rotates the
whole creature under one transform (hexagon, eyes, pupils, mouth, and a nose on
the rim) and undoes it before the label, because a name is written for a reader
and readers do not tilt their heads. The sweep takes the short way round the
circle, so crossing north is twenty degrees and not three hundred and forty.

That works because the heading is on the wire: the presence heartbeat
carries `head: {deg, true_north}` beside `geo`. Additive, guarded on read, and a
peer who sends none is drawn **upright** — never facing a guessed north. It obeys
the same privacy law raw coordinates do: `ttl=1`, and
`EventEnvelope.PRIVATE_BODY_KEYS` strips it from anything relayed. Which way a
person is facing is a gift between peers standing in the same room.

Two phones on a desk at different angles, `docs/shots/phone_*_facing.png`: each
one draws its own Hexy at its own heading and the other's at the other's, and
each phone's log prints the number the other phone is holding.

### Uncertainty has a width, not an off switch

The point of both screens is **finding somebody**, which means their Hexy has to
sit in the direction they physically are and swing round as you turn.

It did not, and the reason was ours: `Geo.close_range()` refused to claim a
bearing whenever two people were closer together than their fixes could resolve
— which is every pair of phones in one room. A peer with no bearing was pinned
to the middle of the dial, where nothing could move it.

So the direction is now always shown when it can be computed, and how much it
can be believed is the **width** of the wedge drawn behind the peer:

```
half-angle = atan((acc_a + acc_b) / distance)      clamped to [3°, 88°]
```

100 m apart on 6 m fixes is a 7° thread; 6 m apart on 3 and 7 m fixes is a 59°
fan. Both are directions you can turn toward. Past 85° — two fixes that are
effectively the same point — it degrades to a ring that says *somewhere around
you*, which is now rare rather than the normal case. The caption always carries
the number: `hexy-fab4  ±73° · 2 m`.

Both surfaces do it, and on the dial it is drawn **on the peer's own ring**.
A shape that opens out of your own character is the universal drawing of a field
of view — *"why the cone aways point to the neighbor hexy? the cone is supposed
to represent the own user field viwer"* — and it also could not hold a crowd,
because every wedge began at the same pixel. So a peer's uncertainty is a
**band smeared along their own ring**: centred on their bearing, at their own
distance radius, the same `±` half-angle, marker at its centre, ends faded so it
reads *somewhere along here*. The middle of the dial is a keepout nothing may
enter, and past 85° the band closes into a full ring at that peer's radius.
Two peers whose bands collide in both radius and bearing are nudged apart in
**radius** — the one axis that moves without lying — so a crowd stays legible.
In the room every visitor is placed at `(bearing − heading)` and re-placed on
every heading change, so turning the phone sweeps them across the screen.
`docs/shots/radar_bands_mixed.png` has the widths in one frame;
`docs/shots/radar_bands_crowd.png` has three of them at arm's reach.

### True north, and saying which north it is — DEVICE

The sensor's azimuth is measured from **magnetic** north, and the field does not
point at the pole. `android.hardware.GeomagneticField` turns the fix `IxLoc`
already has into the local declination — +4° in Berlin, -14° in Seattle, past 20°
in plenty of inhabited places, all of it wider than the 12° window the dial calls
*straight ahead*, so it is a correction and not a rounding error. It is
recomputed when the body moves a kilometre or five minutes pass, never per fix.

The magnetic azimuth is what crosses the JNI boundary; GDScript applies the
declination, so there is exactly one place it can be wrong. **Before the first
fix there is no declination**, the heading stays magnetic, and the caption reads
`heads-up · facing 288° (magnetic — no fix yet)`. After one it reads
`heads-up · facing 292° (true) · decl +4.3°`. The dial never says one while
showing the other.

### The hold pose — why a correct-looking compass pointed wrong — DEVICE (flat), UNBUILT (upright)

The distances were always right. The **direction** was not, on a phone, held the
way a phone is held.

`getOrientation()`'s azimuth is `atan2(m[1], m[4])` — the compass direction of
the phone's **top edge**. Lying flat that edge is in the horizontal plane and its
direction *is* the heading, which is why every desk test passed. Raised to be
looked at, that edge points at the ceiling, its horizontal projection is a point,
and its compass direction is whatever noise is left over. The display-rotation
remap that was already there cannot help: it only says which edge of the screen
is up *within the plane of the screen*, and leaves z as z. It assumes flat.

Nobody holds a phone plumb, and that is what makes it a bug rather than a
curiosity. Upright, facing due north, with a **two degree** lean of the wrist,
the old path reads **315°**. At ten degrees, 281°. Not drift — a leap.

`remapCoordinateSystem(m, AXIS_X, AXIS_Z)` gives `getOrientation` a frame where
the top edge plays the part the screen normal played, so the azimuth becomes the
direction the **back of the phone** points: where the holder is looking. A wrist
roll does not move it at all. It is also the pose a necklace hangs in and the
pose a mirror is used in.

Which pose is in force comes from the screen's tilt off horizontal: **upright is
entered at 30°, left at 20°**. The 10° band is the point — a phone resting at the
switch point must not flip convention twice a second and shiver the dial.

Nothing changes meaning in silence: `IxLoc: pose=upright pitch=…` in logcat, a
`pose_changed` signal through `Geo.pose()`, and the word at the end of the dial's
caption.

Both phones classify the pose from their own rotation vector on the first
sample — `IxLoc: pose=flat pitch=3.1` and `pose=flat pitch=2.8`, which is what a
phone lying on a desk should read — and `docs/shots/radar_a22_pose_flat.png` is
the dial saying `heads-up · facing 339° (true) · decl -21.0° · flat`.

The **upright** half is UNBUILT and the split is deliberate. `geo_smoke` ports
`getOrientation` and AOSP's `remapCoordinateSystem` so the phone's own
arithmetic runs headless — pose classification, hysteresis, the bug reproduced
at three lean angles, a tilt-without-turning sweep, wraparound across north —
and `radar_smoke` pins the heads-up sign in both poses (turn right, world goes
left; it was never wrong and was never compensating). But the acceptance test
for a pose fix is *physical*: tilt a phone flat-to-upright without turning it
and watch the heading hold. The phones sit on a desk and nobody tilted them, so
no real sensor has ever printed `pose=upright`. See `docs/ROADMAP.md` item 8.

### The heading that was never delivered — DEVICE

For two releases the dial did not orient, and neither the pose remap nor the
declination was at fault. The values were correct; **they were emitted before
anything was listening, and then never repeated.**

`IxLoc.onMainResume` starts the rotation-vector listener at Activity resume.
`scripts/social/geo.gd` connects to `heading_changed` about a second and a half
later, when Godot has loaded the main scene and calls `start()`. Measured on the
A22, the gap was **1.49 s** and it swallowed three heading emits, one pose and
one accuracy level:

```
53.500  IxLoc  heading: rotation-vector listener registered
53.607  IxLoc  pose=flat pitch=5.1
53.607  IxLoc  heading: 63.0 (magnetic)
53.722  IxLoc  heading: 57.2 (magnetic)
53.825  IxLoc  heading: 56.0 (magnetic)
55.000  godot  geo: source=ixloc          <- the first listener connects
```

Then the phone lay still on the desk, the 1° delta gate in `publishHeading`
suppressed every later sample, and that was the whole session's heading: three
values, all lost, none repeatable. GDScript kept the `0.0` it was born with, the
declination handler added `-21.04` to it, and the dial sat on **339°** — a number
assembled entirely from a default and a correction, with no measurement anywhere
in it. A pose line never printed for the same reason.

Three changes, and none of them is arithmetic:

1. **`start()` is a handshake.** It is the one moment the plugin knows GDScript
   is connected, so pose, accuracy, declination and heading are all re-announced
   into it and the emit gate is reset. `onMainResume` does the same after a pause
   re-registers the listener.
2. **A one-second keepalive.** The delta gate is right about chatter and
   catastrophic as the only rule — it turns the stream into a one-shot. A still
   phone now sends one sample a second instead of none, so no listener can ever
   again hold a value that nothing will correct.
3. **`Geo` disowns a heading that stopped arriving** (`HEADING_STALE_MS`, 4 s =
   four keepalives). The radar drops out of heads-up and becomes the north-up map
   it was before the compass existed. Rotating the world by a number of unknown
   age is the one option that is actually dishonest, and it is what the dial did
   for two releases. Recovery is automatic: one sample and it is back.

`registerListener`'s **result** is now logged with the sensor's type and name —
it returns `false` when the platform declines and the old line said "registered"
either way — unregistration says so out loud, and a summary every five seconds
carries samples/s seen, samples/s sent, raw, smoothed and pose, so `sent=0` is a
sentence rather than a silence. `TYPE_GEOMAGNETIC_ROTATION_VECTOR` is a fallback
for a phone with no gyroscope; `TYPE_GAME_ROTATION_VECTOR` is deliberately
refused, because it has no magnetometer and therefore no north, and a dial
pointing confidently at nothing is worse than a dial that will not point.

**The acceptance test is that the two sides print the same number.** Fresh
install, both phones flat on a desk, ~45 s each:

```
A22 (R9WT200BA8F)
  IxLoc  heading: registerListener(TYPE_ROTATION_VECTOR "ROTATION_VECTOR") -> true
  IxLoc  pose=flat pitch=4.7 (screen tilted off horizontal)
  IxLoc  heading: announcing state to a fresh listener (start())
           pose=flat accuracy=3 heading=313.7 magnetic declination=none
  godot  geo: heading=313.7° (magnetic — no fix yet)
  IxLoc  heading: 292.7 true (313.7 magnetic -21.04 decl)
  godot  geo: heading=292.7° (true) = 313.7° magnetic -21.04° decl
  IxLoc  heading: 50.3 samples/s seen, 1.0/s sent (252/5 in 5.0s)
           raw=313.7 smoothed=313.7 pose=flat

Fold 4 (RFCT71BW9YV)
  IxLoc  heading: registerListener(TYPE_ROTATION_VECTOR "Rotation Vector  Non-wakeup") -> true
  IxLoc  heading: 343.1 true (4.2 magnetic -21.04 decl)
  godot  geo: heading=343.1° (true) = 4.2° magnetic -21.04° decl
  IxLoc  heading: 15.1 samples/s seen, 1.0/s sent (76/5 in 5.0s)
           raw=4.1 smoothed=4.1 pose=flat
```

Every GDScript receipt paired against the plugin emit before it: **88 pairs
across three captures, 0 mismatched.** Before the fix the same comparison read
`kotlin=61.9 gdscript=0.0`. The Fold happens to sit at 4° magnetic, so its true
heading is 343° — the correction crossing the 0/360 seam, right on both sides.

Sensor rates differ by hardware and the emit rate does not: the A22's
rotation vector runs at **50.3 Hz** and the Fold's at **15.1 Hz**, and both
deliver **1.0 heading/s** to GDScript on a motionless desk. The raw values jitter
by a few tenths of a degree between samples, which is itself the proof that
samples are flowing rather than one value being repeated.

Backgrounding and reopening the app is also on the log: the listener
unregisters, twelve seconds pass with no samples, and resume re-registers and
re-announces — `announcing state to a fresh listener (onMainResume) pose=flat
accuracy=3 heading=313.7 magnetic declination=-21.04`, received by GDScript
intact 45 ms later.

**UNBUILT: the stale watchdog has not fired on a phone.** Its logic is pinned by
`tests/geo_smoke.gd` and `tests/radar_smoke.gd` on an injected clock, and 90 s of
device log shows it correctly *not* firing while samples flow — but a pause does
not exercise it (Godot's `_process` is frozen while backgrounded, and the resume
handshake stamps a fresh sample before the first frame runs). What a desk has
proven is that it does not false-positive.

**UNBUILT, still: the dial's response to a real turn.** `adb` cannot rotate a
phone, and nobody lifted either one. Both readings above are a stationary desk.
That the number is delivered, matches on both sides, and keeps arriving is
proven; that the dial *follows a body turning* remains untested on hardware.

### Compass honesty — states, not crashes, applied to a sensor — DEVICE

Android reports the magnetometer's calibration through `onAccuracyChanged`
(`SENSOR_STATUS_ACCURACY_{HIGH,MEDIUM,LOW,UNRELIABLE}`), and a phone that has sat
next to a laptop says LOW long before it says anything wrong. `IxLoc` forwards
the level verbatim and the radar decides what to do with it: **at LOW or
UNRELIABLE the dial stops rotating** and goes back to being the north-up map it
was before the compass existed, the guidance arrow is not drawn at all, and one
line says `compass unreliable — wave the phone in a figure-8`. Recovery is
automatic and holds no state — the level is read fresh every frame.

Silence is trusted on purpose. `onAccuracyChanged` is not guaranteed to fire on
every vendor stack, and a dial that waited for a callback that may never come
would be a dial that never works.

### The close-range rule — right here, no bearing claimed — DEVICE

**Two 6 m fixes cannot resolve the bearing to someone 6 m away.** That is not a
tuning problem, it is geometry: each position is a disc, and when the discs
overlap the vector between their centres is dominated by their own error rather
than by where the two bodies are. It is also exactly what the two test phones
report sitting on the same desk — and the dial was drawing a confident arrow
from it.

`Geo.close_range()` gates on `distance < 1.25 * (acc_a + acc_b)`. The **sum**,
not the root-sum-square, because adding the radii is the pessimistic reading and
refusing to claim a direction is the place to take the worst case. `K = 1.25`
because 1.0 would still draw a bearing at 13 m where two overlapping discs can
give a wrong quadrant, and 1.5 refuses across a whole room; for a pair of 6 m
fixes it puts the floor at **15 m**.

Inside the floor the distance survives — a scalar degrades gracefully — and the
direction does not. The peer is pinned to an inner **"with you"** ring, captioned
`juno 6 m · right here`, and guidance refuses to draw an arrow: *within arm's
reach of what the fixes can resolve — no direction*. Above the floor nothing
changes at all. A fix that stated no accuracy has no floor, so the desktop rig
and every peer on an older build keep the bearings they always had.

Proven on both phones, six metres apart on a desk, with the numbers this rule
was written for:

```
A22   IxLoc: fix acc=7.491m placeable=true mode=high
      godot: geo: close range — 5.9 m apart inside a 16.6 m floor
               (acc 7.491 + 5.780); right here, no bearing claimed
Fold  IxLoc: declination: -21.04 deg east at -7.23621,-35.90244 alt=537m
      IxLoc: heading: 330.1 magnetic -> 309.1 true (decl -21.04)
      IxLoc: heading accuracy: high (3)
```

`docs/shots/radar_a22_right_here.png`, `docs/shots/radar_fold_right_here.png`,
and `docs/shots/radar_a22_right_here_guidance.png` — the last one is guidance
asked for and refused, with no arrow drawn.

Guidance points at a peer relative to where you are actually facing and adds the
thing a person wants — *turn left 30°* — while still printing the true bearing,
which is a fact about the two bodies and does not move when you turn.

A blip's radius is log-scaled distance, rings at **10 m / 100 m / 1 km**, because
the interesting range spans three decades and a linear dial spends every pixel on
the far half.

Tap a blip and the dial goes into guidance: a big arrow along the bearing and a
live distance that moves with each heartbeat — the radar keeps no distance of its
own, it re-reads both fixes every frame, so walking toward someone shortens the
number exactly as their walking toward you does. Tap again to cancel.

**A peer nobody can place is still on the dial.** If either fix is too coarse to
place by (`Geo.is_placeable` — indoors on balanced power that is every fix, at
`acc 2000 m`) or a peer sent none at all, they are parked on an inner *"near you
— direction unknown"* ring instead of being dropped. A radar that showed nothing
indoors would be a radar nobody trusts. Which ring depends on the proximity class
below. The whole unknown ring sits inside the 10 m hub, so it can never be
misread as a distance.

Nothing is persisted and nothing is drawn from memory: the dial renders the
presence registry as it stands, and a peer who goes quiet for six seconds takes
their blip, their guidance and their class with them.

### Proximity class — what Nearby actually gives you

`touch` / `room` / `far`, a class and never metres. ROADMAP Phase 3, ladder 1b.

Nearby Connections exposes **no RSSI, at any point in the lifecycle**.
`DiscoveredEndpointInfo` carries the service id, the endpoint name and whether
the endpoint is incoming — nothing distance-shaped. After connecting,
`ConnectionInfo` adds an auth token, and that is the end of it; Nearby picks and
upgrades the medium for you and does not report which one it landed on. The one
quantity that varies with the link is `BandwidthInfo.getQuality()` in
`onBandwidthChanged`, a *bandwidth* class — but the mediums it stands for have
very different ranges, so it is a weak, honest lower bound: `HIGH` (WiFi-class
link negotiated) → `room`, `MEDIUM`/`LOW` (BLE, plain Bluetooth) → `far`. A
connected peer that has had no bandwidth callback gets `room`, the honest default
— we are meshed, therefore within a radio's reach, and no better than that.

`touch` is **never** emitted on device. Nothing Nearby hands over can tell a
phone on the same table from a phone across the room, and a class that cannot be
earned is not guessed. The desktop `LanMesh` rig does emit it, for the one case
it can prove: a peer whose datagrams come from this machine's own loopback is not
*near* us, it *is* us.

The class travels the transport seam (`MeshPeer.peer_proximity`) and
[`MeshFabric`](scripts/net/mesh_fabric.gd) re-keys it from a transport id to the
fabric id the app knows peers by. It only ever learns that mapping from an
envelope with `hops == 0`: a link fact describes the phone that handed you the
bytes, and after a relay that is somebody else, so a peer reachable only through
a relay gets no class rather than the relay's.

```
Godot_v4.7.1 --headless --path . -s res://tests/radar_smoke.gd
Godot_v4.7.1 --path . -s res://tools/radar_shot.gd   # user://radar_shot.png
```

## Body sense

The front camera, and the shortest honest description of it: **off until you
turn it on, open five per cent of the time, and it never produces a picture.**

Consent is a labelled button in the workshop (`turn on` / `turn off`), it is
session-only and never written to disk, and nothing else in the app can reach
it — not a timer, not a peer, not a model. Turned on, `BodySense` opens a 1.5
second window every 30 seconds; between windows the camera is *unbound* and the
graph closed, so the sensor is off rather than idling. That is a 5% duty cycle,
and the number is printed on the workshop's BODY line so it can be checked
against the code without a cable.

What a window produces is one word for what it saw (`away` / `watching`) and
one for the expression (`neutral` / `smile` / `surprise` / `eyes_shut`), read
off MediaPipe blendshapes. Hexy looks up when somebody is there and answers a
smile with a hop; the counts live only on the instrument panel.

**No frame ever becomes an event.** The plugin boundary carries three signals of
words and floats — there is no bitmap, no buffer, no landmark array on this side
of it, and no camera preview anywhere in the app to screenshot. `event_is_clean`
refuses an event carrying an image-shaped key or bytes at any depth, and the
smoke test tries to smuggle both past it. The line below about events and never
frames is a property of the code rather than a promise about it.

## Stack (planned)

- **MediaPipe** models — body sense (pose, face; hands later). **Face is built**
  — `android_plugin/ixbody`, Tasks Vision rather than MNN; ROADMAP Phase 5 has
  the reasoning and the device log
- **Qwen-VL locate-anything** — world sense (necklace mode; NVIDIA/OWL-ViT retired, see Phase 6)
- **MNN** — one on-device runtime for every model
- **Wireless mesh** — device-to-device events, never frames

## Run

```
Godot_v4.7.1 --path .
```

Tap: Hexy hops to the tap. Move mouse: Hexy watches. Run two instances on one
LAN: they mesh, greet, and each one's Hexy visits the other's screen.

```
HEXY_NAME=alpha Godot_v4.7.1 --path .
HEXY_NAME=beta  Godot_v4.7.1 --path .
```

## First-run asset delivery

Hexy's mind is two MNN model dirs — `gte-embedding-mnn` (~430 MB) and
`qwen3-0.6b-mnn` (~450 MB). Neither is in the APK and neither can be: together
they are nine times what Play delivers in one package. A stranger who installs
this has no `adb`, so on first launch the app fetches them itself from a manifest
published beside the bytes:

```
https://storage.googleapis.com/ix64-havata-assets/hexy/v1/asset_manifest.json
```

Public read, hosted in the Firebase project **ix64-havata** (shared with
ix64-avatar, which publishes under `models/v1`). To republish after changing a
model — uploads what changed, re-checksums everything, rewrites the manifest:

```
./tools/publish_assets.ps1
```

[`AssetBootstrap`](scripts/net/asset_bootstrap.gd) compares that manifest to disk
and fetches only what is missing, into the same external files dir IxMnn reads
from ([`ModelStore`](scripts/net/model_store.gd) names it once for both). It
resumes an interrupted transfer from a `.part` with an HTTP Range request,
verifies every byte against the manifest's sha256 **before** renaming into place,
refuses to spend mobile data unless the user has said yes, and refuses to start a
download the device has no room for — each refusal a named state in logcat rather
than a crash. Lanes wake one at a time, so the embedder loads while the chat
weights are still coming.

`tools/push_mnn_model.ps1` still sideloads over `adb`; it is now the developer
shortcut rather than the only road onto a device.

## Test

```
Godot_v4.7.1 --headless --path . -s res://tests/mesh_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/mnn_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/fabric_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/shared_map_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/presence_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/asset_bootstrap_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/geo_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/radar_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/peer_mind_smoke.gd
Godot_v4.7.1 --headless --path . -s res://tests/probe_smoke.gd
```

Windowed proof of visits, no network needed — fakes two presence events and
saves `user://visit_shot.png`:

```
Godot_v4.7.1 --path . -s res://tools/visit_shot.gd
```

The same for the radar — fakes a peer 62 m north-east, one 400 m south, one 6 m
away with a 6 m fix (the close-range case) and one with no fix at all, opens the
dial and saves `user://radar_shot.png`. `HEXY_SHOT_UNRELIABLE=1` reports the
compass as LOW instead of HIGH:

```
Godot_v4.7.1 --path . -s res://tools/radar_shot.gd
```

A suite passes only if it prints `=== ALL PASS ===` and exits 0.
