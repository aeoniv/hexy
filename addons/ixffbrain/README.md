# IxFfBrain: Drosophila melanogaster Cybernetic Connectome Addon

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

## Performance Invariants
- Memory footprint: $< 1.5\text{ MB}$ RAM.
- Computation time: $< 0.04\text{ ms}$ per frame at 60 FPS.
- Zero neural network inference during continuous background operation.
- Hardware-gated for Samsung Galaxy Z Fold 4 (Tabletop Flex-Mode & 12 GB RAM) and budget devices (Galaxy A22).
