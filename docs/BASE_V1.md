# BASE v1.0.0 — one page for the export agent

What a phone gets when `res://addons/hexy_*/` is empty. No add-on is required,
and with none present the base is byte-identical to this page (`tests/test_addon_bus.gd`).

## Boot

- Main scene: `res://scenes/hexy.tscn` → `scripts/glass/app.gd` (`HexyApp`).
- Autoload: **`Config`** = `res://scripts/core/config.gd`. It is the only one.
- App version: **1.0.0** — `project.godot [application] config/version`,
  `export_presets.cfg version/name` (`version/code=1`). No `VERSION` const exists
  in `scripts/`; these two files are the whole story.
- Orientation portrait, 720×1280 viewport, `canvas_items` stretch, Mobile renderer.

## The nine objects the root builds (`scripts/glass/app.gd:67-140`)

| object | file | what it is |
|---|---|---|
| `store` | `scripts/core/store.gd` | the one state: head / body / earth / room |
| `mnn` | `scripts/core/mnn/mnn.gd` + `scripts/brain/mnn_runtime.gd` | on-device Qwen through the `ixmnn` aar, mock off-phone |
| `qwen` | `scripts/core/qwen/qwen.gd` | judgements, prompt shaping |
| `wmn` | `scripts/core/wmn/wmn.gd` | the fabric: presence, chirp clock, envelope6, ledger |
| `senses` | `scripts/senses/senses.gd` | the sixteen (8 human + 8 machine) |
| `alchemy` | `scripts/core/alchemy.gd` | the ONE body writer; nothing else turns a body line |
| `oracle` | `scripts/sensor_oracle.gd` | raw accel/gyro/light → the fly's per-frame sample |
| `mic` | `scripts/core/mic.gd` | Android recogniser, desktop mock |
| `heading` | `scripts/core/heading.gd` | the compass — `Input.get_magnetometer()`, engine API, no plugin |
| `creature` | `scripts/creature/creature.gd` | the solid in the body ring |
| `hud` | `scripts/glass/hud3.gd` | the third glass |
| `addons` | `scripts/core/addons.gd` | scans `res://addons/hexy_*/addon.gd`; empty here |

The fly brain (`scripts/brain/fly_*.gd`) is native GDScript, not a plugin:
central complex, mushroom body, giant fiber, circadian clock, conductance,
hash, recall.

The I Ching (`scripts/core/iching/`) is King Wen 64, the Q6 lattice and the
versioned Q6 prior, casting, pacing and debounce.

## Surfaces a finger can reach

1. **The glass** — `scripts/glass/hud3.gd`: status line, HEAD dial, BODY dial
   with the creature inside it, EARTH dial, composer. Tap only.
2. **The bubble** — every reply, six seconds, beside whatever said it.
3. **The dashboard** — `scripts/glass/dashboard.gd`, opened from the status
   strip: ten panels on one scrolling column — identity/device, engine,
   figures, the sixteen as an 8×8, fires & pacing, **fly (with the radar)**,
   mesh, tunables, controls, doors.
4. **The radar** — `scripts/brain/fly_calcium_radar_2d.gd`. Two placements:
   - a fold that is open gets its own left column on the glass (`dual_pane`);
   - **a slab phone reads it in dashboard panel 6 · FLY**, which is where the
     tap-to-guide gesture lives on a normal phone. The glass's own pane is not
     drawn in `tall_slab` (`hud3.gd:444-452`), so panel 6 is the page.
   Both radars get the compass and both lose a peer when `Wmn.peer_gone` fires.
5. **The doors panel (10)** — the six need lines and the four circuits, each
   naming the add-on feeding it. With no add-ons every row reads `—`.

## Android plugins

| plugin | script seam | `REQUIRES` | aar in `addons/` |
|---|---|---|---|
| `ixmnn` | `scripts/brain/mnn_runtime.gd:28` | `ixmnn/2` | debug = `ixmnn/2`, **release = `ixmnn/1` (stale)** |
| `ixmesh` | `scripts/net/mesh_peer.gd` | `ixmesh/1` | debug and release both `ixmesh/1`, both carry `peer_proximity` |

The handshake is `scripts/seam.gd`: at attach the aar's `plugin_version()` is
compared with the seam's `REQUIRES`, and a mismatch drops the singleton and
runs the mock with one loud line. **A RELEASE APK MUST NOT BE CUT UNTIL
`android_plugin/ixmnn` is rebuilt** — `./gradlew exportAllAars` — or MNN falls
back to the mock on the phone.

Neither plugin is required for the app to boot: no aar means the desktop mock
and a LAN mesh instead of Nearby.

## Invariants

- one state: everything is written through the store / seat bus / `Config`;
- one body writer: `scripts/core/alchemy.gd`;
- one clock: `scripts/core/clock.gd` (the surviving `Time.get_ticks_msec()`
  calls are per-widget animation phase in the older 2D dials, not app time);
- one door per plugin, and a missing aar is a loud fallback, never a silent one;
- add-ons off = base unchanged.

## Tests

47 scripts in `tests/`. Run them with

```
Godot_v4.7.1-stable_win64_console.exe --headless --path . --import
Godot_v4.7.1-stable_win64_console.exe --headless --path . -s tests/<name>.gd
```

Known flake: `tests/device_facts_smoke.gd:72` compares two live
`ModelStore.free_storage_bytes()` readings and can disagree on a desktop where
`df` moves between the two calls. It is an environment flake, not a code fault.
