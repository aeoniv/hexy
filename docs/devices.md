# Device Profiles

`scripts/core/device_profile.gd` (`DeviceProfile`) is a table-driven profile
so hexy can be tuned per device without touching behavior code. Samsung
Galaxy Z Fold 4 is the primary delivery target; Galaxy A22 is the floor.

## Adding a device

Add one row to the `PROFILES` const array. That's it — no other code needs
to change. Every row must carry all of `DeviceProfile.REQUIRED_KEYS`
(`tests/test_device_profile.gd` has a schema test that fails the build if a
row is missing one).

## Table

| id | RAM range | hinge | dual-pane width | chat lane hint |
|---|---|---|---|---|
| `galaxy_z_fold4` | 10–14 GiB | yes | 1200px | high |
| `galaxy_z_fold5` | 10–14 GiB (shares Fold 4 aspects until measured) | yes | 1200px | high |
| `galaxy_z_fold6` | 10–14 GiB (shares Fold 4 aspects until measured) | yes | 1200px | high |
| `galaxy_a22` | 0–5 GiB | no | 1200px | floor |
| `generic_slab` | any (fallback) | no | 1200px | mid |
| `desktop` | ≥16 GiB or non-Android | no | 1200px | high |

## What each field gates

- `min_ram_bytes` / `max_ram_bytes` — RAM band used, together with
  `screen_aspects`, to match a device during resolution.
- `screen_aspects` — list of `[min, max]` height/width aspect ratio bands
  that identify the device's screen(s) (e.g. a foldable's cover screen and
  unfolded screen are two separate bands on the same row). Fallback rows
  (`generic_slab`, `desktop`) leave this empty and are only reached once no
  row's aspect+RAM band matches.
- `has_hinge` — whether the device folds; combined with `is_dual_pane`
  this picks `layout` (`dual_pane`, `tall_slab`, or `tablet`).
- `flex_hinge_deg` — `[min, max]` hinge angle band that counts as "flex
  mode" (tabletop) for hinge-aware sensor logic.
- `dual_pane_min_width_px` — viewport width above which `is_dual_pane` is
  true and a dual-pane studio layout is used.
- `civil_fire_flex_multiplier` — per-device multiplier applied to
  civil/fire-mode flex thresholds.
- `target_fps` — the frame budget the device is tuned for.
- `chat_lane_hint` — informational hint ("high"/"mid"/"floor") for which
  `ModelStore` chat lane this device class is expected to land on; the
  actual `chat_lane` returned by `resolve()` is computed live from RAM
  using `ModelStore`'s own gates, not this hint.

## Resolution order

`DeviceProfile.resolve(ram_bytes, viewport, os_name)` resolves in this
order:

1. **Explicit override** — env var `HEXY_DEVICE` or ProjectSettings key
   `hexy/device_override`, matched against `PROFILES` ids.
2. **Aspect + RAM match** — first row (in table order) whose
   `screen_aspects` contains the viewport's aspect ratio and whose RAM
   band contains the resolved RAM.
3. **Fallback** — `desktop` if the OS isn't Android and RAM is ≥16 GiB,
   otherwise `generic_slab`.

All three parameters default to live values (`ModelStore.detect_total_ram_bytes()`,
`DisplayServer.window_get_size()`, `OS.get_name()`) when omitted, but the
function is fully deterministic and side-effect free when they're supplied
explicitly — which is what the test suite does.
