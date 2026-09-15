# BASE v1.0.0 — one page for the export agent

What a phone gets when `res://addons/hexy_*/` is empty. No add-on is required,
and with none present the base is byte-identical to this page (`tests/test_addon_bus.gd`).

## One organism (canon, immutable, heuristic-free)

| part | role | owns | never |
| --- | --- | --- | --- |
| mnn | runtime, the one clock | inference, ns time | a second clock |
| ffbrain | circadian clock, central complex, mushroom body, giant fiber, homeostat | the six lines | a heuristic; an external writer |
| i-ching | reads six lines as hexagram, keeps the path | King Wen number, path | writing lines; stage rules |
| qwen | language over the reading | words | writing state |
| wmn | shows body to peers, brings peers in as a sense | presence, phase, stage on the wire | its own state |

Flow: you -> senses -> ffbrain -> body -> iching -> qwen -> you; body <-> wmn; ffbrain+qwen inside mnn.

## Gauge -- the one mutable thing

`scripts/core/gauge.gd` + `user://gauge.json`. Reads canon output, never writes it.
Two mutation paths only: `fit()` (slow self-fit from senses) and `correct()` (glass
correction, clamped by `HexyGauge.clamps()`).

| field group | source it replaces | default |
| --- | --- | --- |
| clock_offset_h, confidence | entrain.gd (deleted) | 0, 0 |
| line_lean[6], lean_step | alchemy.gd (deleted) | 0, 0.25 |
| lean_threshold | alchemy.gd flip_days logic | 0.6 |
| chapter_rules | journey.gd's stage table, as data | ten stages |
| words | sentence.gd word tables | current |

## Senses by fly organ

| organ | door | circuit | driver | poll rate |
| --- | --- | --- | --- | --- |
| ocelli | lux | circadian clock | engine (`ixmnn.get_ambient_lux`) | 1/s |
| halteres | imu (accel, gyro) | central complex, giant fiber | engine | every tick |
| tarsi | touch | homeostat | engine (event-driven) | on tap |
| compound eye | camera (posture), gaze | central complex, mushroom body | aar (ixbody/2, ixlens/2) | 2/s |
| antenna | voice, place | mushroom body, central complex | aar (ixvoice/2, ixloc/1) | 2/s |
| pheromone | peers over radio | circadian (social zeitgeber), homeostat | base wmn | per figure cast |
| words | typed/spoken | mushroom body | base qwen | event-driven |

Consent keys (`scripts/core/consents.gd`, gated in `HexySenses.CONSENT_OF`): lux/imu/touch/place ->
`Consents.BODY`; camera/gaze -> `Consents.VISION`; voice -> `Consents.VOICE`. A consent
off reads nothing and releases any broker door held.

REQUIRES_* aar versions checked at the singleton handshake (`scripts/seam.gd` pattern):
`ixbody/2`, `ixlens/2`, `ixloc/1`, `ixvoice/2`.

## Doors -- direction is the paradigm

- in: camera -> compound eye, mic -> antenna, lux/IMU/touch -> ocelli/halteres/tarsi, radio in -> pheromone
- out: speaker -> wing song, creature on screen -> fly body, haptic -> leg twitch, radio out -> pheromone
- glass (looks only): radar, dials, sheets, dashboard

One broker per contended door. `scripts/core/broker.gd` carries two tables: the
four-law resource policy (`front_lens`, `back_lens`, `mic`, `speaker` -- priority,
seize, exclusion, steal; origin holders `rig/lens/pose/deck/find/look/face/ear/mouth/chirp`
kept as pure policy, only `chirp` wired in base today for the wing song) and a flat
W8d door table (`acquire`/`release_door`/`holder`) for organ/add-on doors --
`camera`->compound_eye, `voice`->antenna. First asker keeps a flat door; an add-on
asking for a door an organ already holds is refused, loudly.

Creature is efferent: HEAD tiller (`hud3.gd` `DOOR_HEAD_TILLER = "head_tiller"`) is
a tarsi Sense the brain may follow or refuse, not a direct write. Vision (optic
lobe) circuit is missing from ffbrain -- belongs in canon, not built.

## Acts (out doors)

`scripts/core/acts.gd` subscribes `/act`, one door does one thing, no state kept.

| door | behaviour |
| --- | --- |
| speaker | wing song: generated tone via `AudioStreamGenerator`, broker-acquired per act (`chirp`) and released immediately |
| haptic | `Input.vibrate_handheld`, clamped to 250ms |
| screen | no-op -- the creature IS the screen, drawn off `/body`/`/phase` |
| radio | no-op -- wmn owns the wire and broadcasts its own body |

## Topics + Body shape

`scripts/core/msg.gd` (HexyMsg): four kinds, all plain Dictionaries (JSON-safe) --
Sense `{kind, organ, door, t_ns, value, meta}`, Body `{kind, t_ns, bits, lines[6],
heading_rad, activity[8], glow, phase, stage}`, Phase `{kind, t_ns, seconds, day,
weeks, life, together}`, Act `{kind, door, t_ns, value, meta}`.

Body is THE ONE shape for store, wire and radar -- `body_from_fly_state()`,
`body_to_radar_state()`, `body_to_wire()`, `body_from_wire()` all round-trip it.
`stage` has no first-person writer yet (see Gaps). `activity[8]` is the calcium-bump
cosine-hill, duplicated locally in msg.gd so it never preloads scripts/brain.

`scripts/core/topic.gd` (HexyTopic): publish/subscribe only, no timers, latched
delivery (last message per topic retained), synchronous in subscription order.
`/sense` fans out to `/sense/<door>` when the msg carries a door. Canonical topics:
`/sense`, `/body`, `/phase`, `/act`.

`tests/bag/*.json` + `bag_replay.gd`: a recorded day (quiet_day/busy_day, 1440 ticks
at 60s/tick) replays deterministically through ffbrain + gauge with no wall clock.

Not ROS: one process, one clock, Godot signals -- not a second transport.

## Glass pages

| page | reads | publishes |
| --- | --- | --- |
| front | `/body` `/phase` `/peers`, radar quiet, creature, one sentence, hexagram | nothing directly; swipe up -> dashboard |
| dials | `/body` for BODY; HEAD ring drag -> tarsi Sense (head_tiller); EARTH ring drag -> gauge preview only, no write | Sense only, never state |
| peer sheet | tap blip -> who/band/in-phase/chapter; guide -> rim arrow | view state only |
| reading | tap hexagram -> glyph/six bars/chapter title (`/body` + gauge captions) | nothing |
| dashboard | radar loud, panel 11 four clocks (seconds/day/weeks/life/together), panel 10 doors | nothing |

Rule (`tests/test_glass_wall.gd`): every page a subscriber, none a writer. Banned
names checked as text in `scripts/glass/*`: `Entrain`, `Journey`, `Alchemy`,
`set_target_heading`, `reward_event`, `note_seat(`, `note_cast(`, `broadcast(`.

## Add-ons contract

`doors() reads() writes() view() attach(bus) detach()`. Loader (`HexyAddons`)
refuses a write outside `/sense`, `/sense/<door>`, `/act`, and refuses an
undeclared door via a `GuardedBroker`. `store.dump()` is equal before attach and
after detach. Folder `addons/hexy_<name>/addon.gd` + `bin/` aar. See
`docs/plans/addons.md` for the four planned functions and the worked example.

## Bag + replay

`scripts/core/bag.gd` (HexyBag): records every `/sense` publish relative to the
first one seen, saves `{version, name, dt_ms, tick, senses}` JSON. Replay
(`HexyBag.play`) republishes at each message's own `t_ns` and calls a tick
callback on simulated time only -- no timer, no Engine clock. See
`tests/bag/README.md`.

## Invariants (the two walls)

`tests/test_glass_wall.gd`: glass/creature never import `scripts/senses`,
`scripts/net`, `scripts/brain`; no `Engine.has_singleton`/`get_singleton` or
`IxMnn`/`IxMesh`/`IxSensors` names; senses never import glass/creature; and the
BANNED-name write check above. Confirms `glass.gd`, `mobile_hud_store.gd`,
`hud_bridge.gd` are gone and stay gone.

`tests/test_gauge_wall.gd`: nothing under `scripts/brain` names an interpreter
(`HexyGauge`, `Alchemy`, `Entrain`, `Journey`, `Sentence`, `Front`, `Dashboard`, or
their file paths) -- the gauge never preloads the brain and the brain never reads
the gauge back. `store.set_body` is the one writer of body bits; every other path
reaches the body by publishing on `/body`.

## Numbers

- Tests: 62 `.gd` files under `tests/` (`ls tests/*.gd`).
- Config: 25 schema rows (`HexyConfig._schema_rows()`), confirming "expect 25".
- Aar `REQUIRES_*` versions used by senses.gd: `ixbody/2`, `ixlens/2`, `ixloc/1`,
  `ixvoice/2`. Plugin `bin/VERSION` on disk: `ixbody/2`, `ixlens/2`, `ixloc/1`,
  `ixmesh/1`, `ixmnn/2`, `ixvoice/2` -- ixmesh has no REQUIRES_ constant here.
- `project.godot [editor_plugins]` enables all six: ixbody, ixlens, ixloc, ixmesh,
  ixmnn, ixvoice.
- `hud.status_mode` config key: absent from the repo (grep finds nothing), confirmed removed.

## Gaps (known, stated rather than hidden)

- `acetylcholine` and `is_startled` (read by `hud3.gd`'s status line) are polled
  off `Character.get_fly_state()` / `FlyBrain.state()` -- not off a Body message.
  `HexyMsg.body_to_radar_state()` documents both as absent from the Body shape
  (acetylcholine passed as 0.0, is_startled defaults false).
- First-person `stage` is empty in Body: `wmn.gd` carries a per-peer stage on the
  wire, but nothing writes the organism's own stage onto `/body` yet.
- The pacing journal on dials is empty: `hud3.gd:_journal()` always returns `[]`
  -- "W8e removed the core object that kept one"; `journal_text()` and
  `day_count()` read off that empty array.
- Journey `REFUSAL`/`REWARD` stages are unreachable: `journey.gd`'s enum still
  defines them, but `Journey.stage_of_path` never assigns either from bits alone
  (mirrored in `HexyGauge.chapter_rules.stage_gloss`). `journey.gd` itself is
  NOT deleted, unlike alchemy.gd/entrain.gd -- only its writer path was removed.
- Barometer and wifi-CSI readers are absent from base; `addons/hexy_example` is
  a mock add-on (a made-up crowding number), not a real CSI sensor.
- The optic-lobe (vision) circuit is missing from ffbrain -- camera/gaze Senses
  reach the bus, but no circuit consumes them into the six lines yet.
- Ambient lux has exactly one real reader: `ixmnn.get_ambient_lux` via
  `HexySenses._read_lux()`; there is no other lux source in base.
- `tests/device_facts_smoke.gd` is flagged flaky (a device-facts race) per the
  W8 plan; no flaky marker found in the test file's own text -- carried forward
  as reported, not independently reproduced here.
