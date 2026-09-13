# Q6 lattice — a cube with no callers

`scripts/core/iching/q6_lattice.gd` treats the 64 hexagrams as the corners of Q6,
the six-dimensional hypercube: bit *i* is line *i*, line 0 is the bottom line,
and two hexagrams are neighbours exactly when one line differs.

A distribution over those 64 corners moves by two forces and nothing else:

- **Diffusion** — a heat step along the cube's edges, done in the Walsh basis
  where the Laplacian is diagonal. The FWHT turns it into one multiply per
  coefficient, `exp(-t * popcount(k))`. The `k = 0` coefficient is the total
  mass and is multiplied by 1, so mass is conserved by construction.
- **Potential** — six per-line biases in `[-1, 1]`, positive favouring yang,
  summed against each corner's own lines into a field `U`, then applied as a
  Gibbs reweighting `exp(beta * U)` and renormalised.

## What the test enforces

`tests/q6_lattice_smoke.gd` — 260 checks, floor 120 — asserts only things that
are checkable without a reference table:

1. FWHT applied twice and divided by 64 is the identity on random vectors, and
   it does not scribble on its input.
2. Diffusion preserves the total mass exactly, never goes negative, is the
   identity at `t = 0`, and at large `t` drives any distribution to uniform
   (max − min < 1e-6, tension 1).
3. **Flip equivariance** — `step(perm_flip(p), -bias, t, beta)` equals
   `perm_flip(step(p, bias, t, beta))` to 1e-9, over random `p`, `bias`, `t`,
   `beta`.
4. **Reverse equivariance** — the same with the hexagram turned upside down and
   the bias reversed.
5. A zero bias from uniform stays exactly uniform, with tension exactly 1.
6. One strong line (`bias[2] = 1`, `beta = 3`) puts > 0.95 of the mass on its
   own half, lowers tension below 1, and leaves the other five lines balanced
   at 0.5 to 1e-9.
7. Twenty steps under a fixed six-line bias settle on the corner agreeing with
   all six signs, and stop moving.
8. One small diffusion from a delta gives the six one-line neighbours equal
   mass, more than any two-line neighbour, falling off monotonically with
   Hamming distance out to the opposite corner.

The two equivariances are the point: a wrong bit order, a wrong sign, or a
Laplacian that is not the cube's would break one of them.

## Exactly one caller

`scripts/core/iching/pacing.gd` is the caller the module was waiting for, and
it is the only one. Pacing walks the BODY figure one line at a time toward the
figure the sixteen senses elect, and the cube is what chooses the line:

- Pacing keeps a 64-entry mass, seeded `Q6Lattice.delta(bits)` on reset and on
  a head cast being injected.
- Every tick it builds the six-line bias from the 8x8 target — `+1` for a yang
  line, `-1` for a yin one — **scaled by the two elections' margins**, so a
  trigram that won by a hair pulls at its three lines by a hair.
- Diffusion time is the branch's: `CIVIL_T` is small, because civil fire is a
  held breath and must barely spread the mass; `MARTIAL_T` is large, because
  martial fire is a surge and throws it wide. Each is scaled by its own
  quantity, `stillness` or `excitation`.
- The next figure is the one-line neighbour of the body holding the most mass.
  Never a two-line jump; the six neighbours are the only candidates.

The timing gates are NOT the cube's: `CIVIL_FIRE_THRESHOLD`, `REARM`,
`MUTATION_COOLDOWN`, `MARTIAL_THRESHOLD` and `INJECT_LOCKOUT` are unchanged and
still decide *when* a line may turn. The lattice decides only *which*.

`tests/test_core_pacing.gd` pins the wiring at both ends. At a large `beta` the
Gibbs reweight swamps the diffusion and the chosen neighbour is exactly
`Pacing.lowest_differing_bit(current, target)` — the rule this replaced, kept
on Pacing as the reference the cube is measured against — over several hundred
random pairs. At the default `beta`, with a thin machine margin against a wide
human one, the chosen line is demonstrably NOT the lowest differing bit, so the
lattice is doing something rather than decorating something.
