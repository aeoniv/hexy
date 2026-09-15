# Add-on Plan -- base + four hardware add-ons

Survey 2026-09-15. Origin `D:\GitHub\ix64-hexy` (v8.4). Base `apps/hexy`.
Rule: an add-on exists only if it opens a hardware door AND drives a fly circuit
or one of the six need lines (Character LINE_BODY..LINE_CONNECTION).

## How to write one

Extend `HexyAddon` (`scripts/core/addon.gd`) in `addons/hexy_<name>/addon.gd`.
Override the four contract methods:

- `doors() -> PackedStringArray` -- every broker door this add-on may ever
  `acquire()`. Anything not listed here is refused by the `GuardedBroker`
  the loader wraps around the real broker.
- `reads() -> PackedStringArray` -- topics subscribed to. Advisory only (the
  loader does not enforce a subscribe), but a manifest that lies here draws a
  wrong panel.
- `writes() -> PackedStringArray` -- topics published on. Only `/sense`,
  `/sense/<door>` and `/act` are ever valid; anything else fails
  `writes_valid()` and the add-on is refused at attach.
- `view() -> Control` -- optional dashboard face, or `null`.
- `attach(bus: Dictionary) -> void` / `detach() -> void` -- take/release the bus.
  `bus` is `{topic: HexyTopic, broker: Broker (wrapped), gauge: HexyGauge,
  consents: Consents, store: HexyStore (read only)}`.

`addon_name()` defaults to the folder name (`hexy_<name>` -> `<name>`); base
never learns an add-on's name any other way. `version()` returns a version
string for a loud mismatch. `manifest()` bundles all four so it can never
drift from what `attach()` actually does.

## The four planned functions

| add-on | doors | reads | writes | view |
| --- | --- | --- | --- | --- |
| rig camera | camera, IMU | -- | `/sense` (posture, light -> senses) | capture files, not a take strip |
| mesh dj | speaker, radio | peers' phase | `/act` (wing song / tempo) | none |
| eco location | GPS, baro | `/body` (sunrise -> circadian) | `/sense` (place) | place on radar; peer sheet gains place |
| csi sensors | wifi CSI | `/body` | `/sense/wifi` (presence, breathing -> homeostat) | dashboard row |

None of the four are implemented in `addons/` today -- only the origin ports
named in `plugin.cfg`/`bin/VERSION` under `ixbody`, `ixlens`, `ixloc`, `ixmesh`,
`ixmnn`, `ixvoice` exist as base singletons, and `addons/hexy_example` (below)
is the one worked contract example.

## What the loader refuses

`HexyAddons.load_all()` scans `res://addons/hexy_*/addon.gd` and, per add-on:

1. `addon.valid()` false -> refused. That means: no name (`addon_name()` empty),
   or neither a door nor a write declared (a folder that touches nothing), or
   `writes_valid()` false (a write topic outside `/sense`, `/sense/<door>`,
   `/act`).
2. Same `addon_name()` as one already attached -> refused, second one freed.
3. A declared door already held by a live organ or an earlier add-on
   (`_broker.holder(door)` non-empty and not this add-on) -> refused up front,
   before the add-on ever calls `acquire()`.
4. At runtime, `GuardedBroker.acquire()` on a door not in this add-on's own
   `doors()` list -> refused and pushed loudly (`push_warning`), same failure
   mode as an undeclared write.

A refused add-on is `queue_free()`d and never reaches `attach()`.

## dump() invariant

`store.dump()` must be byte-identical before an add-on's `attach()` and after
its matching `detach()` -- `tests/test_addon_bus.gd` asserts this directly.
This is enforceable because an add-on never touches the store: everything it
does crosses the bus as a Sense or an Act, and store state changes only
through `store.set_body`/`attach_bus`'s own `/body` subscriber. "Off means base
unchanged" is not a convention here, it is what the contract makes impossible
to violate silently.

## hexy_example walkthrough

`addons/hexy_example/addon.gd` -- a tiny "csi sensors"-style mock, and the
add-on `tests/test_addon_bus.gd` drives end to end:

- `doors()` -> `["wifi"]`.
- `reads()` -> `["/body"]` (keeps `_last_body` so a real add-on could shape its
  guess around what the body is already doing; unused by the mock reading).
- `writes()` -> `["/sense/wifi"]`.
- `attach(bus)` acquires `wifi` from the broker under its own `addon_name()`
  and subscribes `/body`.
- `sample(t_ns, crowding)` publishes one antenna-organ Sense on `/sense` with
  door `"wifi"` and a made-up 0..1 "how crowded the wifi looks" number -- the
  mushroom body listens to antenna, so this is what a test sees reach the
  brain and change a Body on `/body`.
- `detach()` unsubscribes, releases the `wifi` door, and clears `_last_body` --
  the state `dump()` checks against is restored exactly.
- `view()` returns a `Label` showing a sample count, for the dashboard's
  add-on panel.

This is the minimum shape a real csi-sensors add-on above would grow into: one
door, one read for context, one write of a Sense, no state the store can see
directly.
