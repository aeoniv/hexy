# Fly brain (native GDScript, scripts/brain/fly_*.gd)

Formerly packaged as addons/ixffbrain. It is not an Android plugin: no Kotlin, no .so, no version handshake. It lives in the tree and Character owns it.

`ixffbrain` packages the canonical **Fruit Fly (*Drosophila melanogaster*) connectome** as an editor and runtime addon for Hexy.

## Architectural Features

1. **Central Complex (EB/PB & FB)**:
   - 8-wedge compass ring attractor tracking egocentric heading with local excitation and lateral inhibition.
   - Fan-Shaped Body (FB) 2D allocentric goal vector steering toward target hexagrams.

2. **Mushroom Body Associative Memory**:
   - 256 Kenyon cells projected with Winner-Take-All sparsity (top-16 active cells).
   - Locality-Sensitive Hashing (LSH) for context-selective Hamming distance calculations.
   - Hebbian associative plasticity ($\Delta W = \eta \cdot \mathbf{x}_{KC} \cdot r_{DAN}$).

3. **Giant Fiber Escape & Drop Reflex**:
   - Sub-5ms detection of $0g$ freefall and violent mechanical shocks.
   - Overrides kinematics to curl tensegrity struts into a compact defensive ball.

4. **Circadian Clock Pacemaker**:
   - s-LNv and l-LNv pacemakers driving rhythmic Pigment-Dispersing Factor (PDF) release.
   - Morning arousal surge, evening anticipation, and night torpor.

5. **Synaptic Conductance Matrix**:
   - $6 \times 6$ neurotransmitter conductance matrix derived from FlyWire synaptic connection counts.
   - Octopamine $\leftrightarrow$ dFB sleep mutual inhibition.

6. **Live Calcium Radar 2D**:
   - GCaMP fluorescence activity visualization with 8 Bagua trigrams and 6 neuromodulator gauges.

## Performance targets

Run the measurement yourself:

```
godot --headless --path . -s res://tests/test_fly_perf.gd
```

- Device goal (documented, not yet measured on a Fold 4 or A22): $< 1.5\text{ MB}$ RAM, $< 0.04\text{ ms}$ (40 us) per `feed()` at 60 FPS.
- Measured on this x86 dev machine (headless Godot 4.5, 10 000-iteration run, `Character.feed_senses()` + `Character.get_fly_state()` per iteration, after a 500-call warmup):
  - Mean: **~365 us/frame** (`FLY_FEED_MEAN_US`), about 9x the 40 us device goal -- expected, since the goal is for on-device (mobile CPU, likely with more optimized/compiled paths) and this is an interpreted-GDScript headless desktop run.
  - p95: **~405 us/frame** (`FLY_FEED_P95_US`).
  - `get_fly_state()` alone: **~16 us/call** (`FLY_STATE_READ_MEAN_US`) -- cheap; safe to call every HUD redraw.
  - Memory delta over 10 000 feeds: **~163 KB** (`FLY_MEM_DELTA_BYTES`), well under the 1.5 MB target.
  - Per-module breakdown (10 000 calls each): giant_fiber.step ~0.4 us, central_complex.step ~2.7 us, circadian_clock.update ~0.6 us, mushroom_body.encode_context ~270 us (the dominant cost -- a 256-Kenyon-cell x 16-input projection plus top-16 winner-take-all, done once per feed), mushroom_body.decay ~45 us, fly_brain.state() ~13 us.
- `mushroom_body.encode_context()` was optimized during this measurement pass: it used to build 256 `Dictionary` objects per call and `sort_custom()` them with a lambda just to keep the top 16 (~880 us/call). It's now a running top-K insertion over a flat `PackedFloat32Array` projection matrix (previously an `Array` of `Array`s, which boxes every element as a `Variant`) -- same Winner-Take-All selection and output, ~3x faster (~270 us/call). No test's assertions or `state()` key set changed.
- Zero neural network inference during continuous background operation.
- Hardware-gated for Samsung Galaxy Z Fold 4 (Tabletop Flex-Mode & 12 GB RAM) and budget devices (Galaxy A22).
