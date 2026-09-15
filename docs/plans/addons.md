# Add-on Plan — base + four hardware add-ons

Survey 2026-09-14. Origin `D:\GitHub\ix64-hexy` (v8.4). Base `apps/hexy`.
Rule: an add-on exists only if it opens a hardware door AND drives a fly circuit
or one of the six need lines (Character LINE_BODY..LINE_CONNECTION).

## 1. Map

| hardware door | circuit / line | add-on | plugin |
|---|---|---|---|
| front camera | LINE_BODY 0, posture | hexy_body | ixbody |
| mic + speaker | LINE_BREATH 2, mushroom body (FlyHash words) | hexy_voice | ixvoice |
| GPS + ARCore | FlyCentralComplex compass | hexy_compass | ixloc + ixlens |
| Nearby radio | LINE_CONNECTION 5, reward_event | hexy_connection | ixmesh (base wmn) |
| touch, IMU, lux, battery, clock | base senses + seat bus | base | ixmnn |

## 2. Cut

| origin feature | reason |
|---|---|
| oracle surface, signed cast | touch already lands via tap_cast; signature has no circuit |
| mandala, mandala_words | drawing only; hud3 dials show the state |
| agent_loop, notes, tools | no door; turn_machine → base qwen, notes → FlyRecall |
| hexcam, chirp clock, takes, splat | capture tooling, stays in ix64-hexy |
| tangle, ledger receipts | only peer_minds + receipt-as-reward_event survive, in hexy_connection |
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
| M3 | hexy_connection: peer_minds, presence, identity → line 5 | mesh_live, fabric_smoke |
| M4 | hexy_voice: voice_sense, stage_voice → line 2 | voice_smoke |
| M5 | hexy_body: pose_sense, kp_live → line 0 | body_smoke, one APK |
| M6 | hexy_compass: geo, lens_sense, radar → central complex | find_smoke, one APK |

## 6. Invariants

- add-on → base only; graphify gate: 0 cycles, no addon→addon edge
- one state: write via note_seat / Character.feed / Config.set_value
- one clock; one door per plugin; missing aar = loud fallback
- add-on off = base unchanged
