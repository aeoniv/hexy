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

## The phase spine

PHASE runs at four timescales, each owned by one file and persisted in its own
store section:

| timescale | file | store section |
|---|---|---|
| seconds | `scripts/brain/fly_calcium_radar_2d.gd` (calcium radar, live) | `body` (read only, not persisted itself) |
| day | `scripts/core/entrain.gd` — entrained to the user, not the sun | `entrain` |
| weeks–months | `scripts/core/alchemy.gd` — marks with hysteresis, the one body writer | `alchemy` |
| life | `scripts/core/iching/journey.gd` — hero's-journey chapters over the hexagram path | `path` |

Peers carry phase + stage over the mesh (`scripts/core/wmn/wmn.gd`,
`scripts/net/mesh_fabric.gd`) as a social zeitgeber: a room's chirp clock and
Envelope6 payload are a figure, not raw sensor data, so what crosses the wire
is the same PHASE the local dials show.

## Screens and gestures

- **FRONT** (`scripts/glass/front.gd`) — sentence bar, one quiet radar (room),
  creature, hexagram, composer. This is what a person carries.
- Tap the creature → **DIALS** (`scripts/glass/hud3.gd`): HEAD ring drag is
  the tiller into `FlyCentralComplex` target heading, EARTH ring drag is the
  day scrubber preview, BODY is read-only.
- Tap a blip/dot → **PEER** sheet (`scripts/glass/peer_sheet.gd`).
- Tap the hexagram → **READING** sheet (`scripts/glass/reading_sheet.gd`).
- Swipe up → **DASHBOARD** (`scripts/glass/dashboard.gd`), which borrows the
  radar loud. Panel 11 is the four timescales; panel 10 is the doors (which
  add-on, if any, feeds each need line / circuit).
- Back unwinds DASHBOARD → sheet → DIALS → FRONT. No long press anywhere.

## The one radar

`scripts/brain/fly_calcium_radar_2d.gd` is both the room on FRONT (quiet: no
wedges, no neuromodulator bars, just disc/needle/north caption/blips) and the
loud fly panel in DASHBOARD panel 6. Both placements get the compass and both
lose a peer when `Wmn.peer_gone` fires. There is exactly one radar script; a
slab phone reads it in the dashboard, a folded phone gets it in its own left
column.

## The one body writer

`scripts/core/alchemy.gd` is the only place a body line turns. Senses elect
two trigrams and say how surely; Pacing pours that into the cube and decides
which line may turn and when; Alchemy owns no state beyond the pacing it
drives and turns lines with hysteresis (`alchemy_hysteresis_smoke.gd`). The
coupling is one way: a head cast re-anchors the body, the body never writes
back to the head.

## Persistence

`scripts/core/store.gd` (`dump()` / `load_dump()`) persists these sections:

| section | holds |
|---|---|
| `body` | the six-line body figure (head/body/earth/room live state, not itself a store key) |
| `path` | the hexagram path the life-timescale journey walks |
| `entrain` | `Entrain`'s day-phase estimate |
| `alchemy` | `Alchemy`'s marks and hysteresis state |

## Config

`scripts/core/config.gd`: **31** registered keys across groups `alchemy` (3),
`creature` (1), `entrain` (2), `hud` (6), `mesh` (2), `pacing` (10), `prior`
(3), `qwen` (3), `senses` (1). `set_value` clamps to a row's min/max or snaps
an enum; `register` is the only way a key gets added.

## Android plugins

| plugin | script seam | `REQUIRES` | aar in `addons/` |
|---|---|---|---|
| `ixmnn` | `scripts/brain/mnn_runtime.gd:28` | `ixmnn/2` | debug and release both answer `ixmnn/2` |
| `ixmesh` | `scripts/net/mesh_peer.gd:27` | `ixmesh/1` | debug and release both `ixmesh/1`, both carry `peer_proximity` |

The handshake is `scripts/seam.gd`: at attach the aar's `plugin_version()` is
compared with the seam's `REQUIRES`, and a mismatch drops the singleton and
runs the mock with one loud line — the only gate, and it fires once, at
attach.

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

57 scripts in `tests/`. Run them with

```
Godot_v4.7.1-stable_win64_console.exe --headless --path . --import
Godot_v4.7.1-stable_win64_console.exe --headless --path . -s tests/<name>.gd
```

Suites that guard each rule: `test_addon_bus.gd` (add-on off = base
unchanged), `alchemy_hysteresis_smoke.gd` (the one body writer),
`entrain_smoke.gd` (day-phase), `journey_smoke.gd` (life-phase chapters),
`test_circadian_radar_smoke.gd` / `geo_smoke.gd` / `heading_smoke.gd` (the one
radar), `fabric_smoke.gd` / `mesh_smoke.gd` / `test_mesh_live.gd` (peers
carrying phase), `plugin_version_smoke.gd` / `ixmnn_seam_smoke.gd` (the
handshake), `test_config.gd` / `test_config_schema_json.gd` (config), `clock_smoke.gd` (one clock).

Known flake: `tests/device_facts_smoke.gd:72` compares two live
`ModelStore.free_storage_bytes()` readings and can disagree on a desktop where
`df` moves between the two calls. It is an environment flake, not a code fault.

## Deliberately open

- The REFUSAL and REWARD journey stages (`scripts/core/iching/journey.gd`)
  are named but never fire: `Journey` reaches them only if a caller decides,
  elsewhere, that a CALL was ignored or answered, and nothing in the tree
  makes that call yet.
- `hud.status_mode` (`scripts/core/config.gd:159`) is a registered config key
  with no reader.
- `scripts/glass/hud3.gd` keeps its own `GlassBubble` instance (the same skin
  FRONT also instantiates) for dial captions, not one shared status line.
