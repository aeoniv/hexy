# Add-on Plan — base + four hardware add-ons

Survey 2026-09-15. Origin `D:\GitHub\ix64-hexy` (v8.4). Base `apps/hexy`.
Rule: an add-on exists only if it opens a hardware door AND drives a fly circuit
or one of the six need lines (Character LINE_BODY..LINE_CONNECTION).

## 1. Map

| plugin | door | feeds | clock | writes through |
|---|---|---|---|---|
| eye | front camera (ixbody aar) | posture → LINE_BODY | weeks | alchemy.nudge |
| voice | mic + speaker (ixvoice aar) | words → mushroom body | seconds | Character.feed |
| lens | ARCore (ixlens aar) | gaze → compass circuit | seconds | Character.feed |
| nav | GPS (ixloc aar) | place → circadian circuit | day | Entrain.sample |
| base | touch, IMU, lux, clock, radio (ixmnn, ixmesh) | all | — | inside already |

Folder names: `addons/hexy_eye`, `addons/hexy_voice`, `addons/hexy_lens`,
`addons/hexy_nav`.

**Rule:** a need-line write goes through the bus's alchemy (marks +
hysteresis); a circuit write goes through Character. peers, presence, phase
and stage are base, not an add-on — they live in `wmn` (W0/W5), and
`hexy_connection` does not exist.

## 2. Cut

| origin feature | reason |
|---|---|
| oracle surface, signed cast | touch already lands via tap_cast; signature has no circuit |
| mandala, mandala_words | drawing only; hud3 dials show the state |
| agent_loop, notes, tools | no door; turn_machine → base qwen, notes → FlyRecall |
| hexcam, chirp clock, takes, splat | capture tooling, stays in ix64-hexy |
| tangle, ledger receipts | only peer_minds + receipt-as-reward_event survive, folded into base wmn |
| `NEEDS` handshake name | collides with need lines → `REQUIRES := "ixmnn/2"` |
| refusal.gd | Character.refused exists |

## 3. Base plumbing (M1)

clock.gd (ns canonical), device_facts.gd (RAM, i8mm, thermal → rest line),
broker.gd (camera/mic/speaker arbitration), consents.gd (permission = door),
MnnRuntime: sampling, history, tokenize, perf, apply_template; `REQUIRES`.

## 4. Contract (M2)

`scripts/core/addon.gd` HexyAddon: `door() -> String` (plugin), `line() -> int`
(need index or circuit id), `attach(store, config, bus)`, `detach()`,
`config_keys()`, `panel()`. HexyApp loads `addons/hexy_*/addon.gd`.
Dashboard panel 10: six lines × which door feeds each.
`test_addon_bus`: attach/detach leaves `store.dump()` equal; no door or no line = fail.

## 5. Milestones

| M | move | proof | state |
|---|---|---|---|
| M1 | base plumbing + REQUIRES | suites + plugin_version_smoke | done (5e2fb7a) |
| M2 | HexyAddon contract | test_addon_bus | done (5e2fb7a) |
| M2b | the one radar: north-up compass, presence rows, geo math | test_circadian_radar_smoke, geo_smoke, heading_smoke | radar complete (44f8c9e) |
| M2c | phase spine (W0–W7a) | entrain_smoke, alchemy_hysteresis_smoke, journey_smoke, fabric_smoke | done |
| M4 | hexy_voice: voice_sense, stage_voice → mushroom body | voice_smoke | |
| M5 | hexy_eye: pose_sense, kp_live → LINE_BODY | body_smoke | |
| M6 | hexy_lens: lens_sense, gaze → compass circuit | find_smoke | |
| M7 | hexy_nav: geo, place sense → circadian circuit | nav_smoke | |

## 6. Invariants

- add-on → base only; graphify gate: 0 cycles, no addon→addon edge
- one state: write via note_seat / Character.feed / Config.set_value
- one clock; one door per plugin; missing aar = loud fallback
- add-on off = base unchanged
- add-on feeds exactly one clock

## 7. Provenance

AARs are built in `D:\GitHub\ix64-hexy\android_plugin` (`./gradlew
exportAllAars`) and copied into `addons/<ix*>/bin`. Each seam carries
`REQUIRES` (see `scripts/seam.gd`); a version mismatch at attach drops the
singleton and runs the mock with one loud line.
