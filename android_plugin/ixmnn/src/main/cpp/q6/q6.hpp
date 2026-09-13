// q6.hpp - THE SIX-BIT CUBE, NATIVE.
//
// 64 hexagrams as the corners of Q6, the six-dimensional hypercube: two
// figures are neighbours exactly when one line differs. One state p[64] moves
// by two forces and nothing else.
//
//   DIFFUSION - a heat step along the edges, done in the Walsh basis where the
//   cube's Laplacian is diagonal. The Fast Walsh-Hadamard transform makes it
//   one multiply per coefficient, exp(-t * popcount(k)). The k = 0 coefficient
//   is the total mass and is multiplied by exp(0) = 1, so mass is preserved.
//
//   POTENTIAL - a per-line bias in [-1, 1], positive favouring yang, becomes a
//   field U over the corners, and a Gibbs reweighting exp(beta * U) pulls mass
//   toward the corners the six lines agree with.
//
// Bit i (0..5) is line i, line 0 is the BOTTOM line. A set bit is yang.
//
// This is a straight port of scripts/core/iching/q6_lattice.gd and the anchor
// and neighbour rules of scripts/core/iching/pacing.gd, constant for constant.
// Pure C++17, no MNN, no JNI, no allocation after construction, so the same
// arithmetic can be compiled into a desktop test binary.

#ifndef IXMNN_Q6_HPP
#define IXMNN_Q6_HPP

#include <cstddef>

namespace ix64 {
namespace q6 {

constexpr int kLines = 6;
constexpr int kStates = 64;
constexpr int kAllLines = 63;
constexpr int kEmbedDim = 32;

// Pacing's own constants, kept here so the cube carries its own defaults.
constexpr double kDefaultBeta = 2.5;
constexpr double kAnchor = 0.5;
constexpr double kTieEpsilon = 1e-9;

// Number of set bits in k over the six lines: the Walsh eigenvalue.
int popcount(int k);

// The sign of line i in hexagram h: +1 for yang, -1 for yin.
double lineSign(int h, int i);

// Every line inverted.
inline int flip(int h) { return h ^ kAllLines; }

// The hexagram turned upside down: bit order reversed over six lines.
int reverse(int h);

// FAST WALSH-HADAMARD, unnormalised, in place. Its own inverse up to 64.
void fwht(double* v);

struct Q6 {
    double p[kStates];

    Q6();

    // All the mass on one corner.
    void reset(int bits);

    // Same thing, said the way a cast says it.
    void inject(int bits) { reset(bits); }

    // Mass spread evenly over all 64 corners.
    void uniform();

    // The body's own corner put back under the cloud:
    //   p = p * (1 - amount), then p[bits] += amount.
    void anchor(int bits, double amount = kAnchor);

    // DIFFUSE, THEN LISTEN. One heat step of time t along the edges, then the
    // Gibbs factor exp(beta * U(bias)), renormalised to sum 1. A bias that
    // annihilates the mass falls back to uniform, exactly as the GDScript does.
    void step(const double bias[kLines], double t, double beta = kDefaultBeta);

    // The corner holding the most mass. Ties go to the lowest index.
    int argmax() const;

    // Normalised Shannon entropy in [0, 1]. 1 has nothing to say.
    double tension() const;

    // THE NEXT FIGURE IS A NEIGHBOUR, never a jump: of the six corners one
    // line from `bits`, the line index (0..5) of the one holding the most
    // mass. Ties, measured RELATIVELY because at a large beta all six sit
    // around 1e-68, go to the lowest line. Returns 0 when nothing is there.
    int bestNeighbour(int bits, double tieEps = kTieEpsilon) const;

    // A FIGURE CLOUD AS A POINT IN R^32, deterministic and learned by nothing.
    //
    // out[] receives Walsh coefficients of p: run the unnormalised FWHT, walk
    // k from 0 to 63 in ASCENDING k, keep every k whose popcount is 3 or less,
    // and take the first 32 of those. 42 of the 64 indices qualify and the cut
    // falls at k = 37, so the 32 kept are, by popcount, 1 + 6 + 13 + 12.
    //
    // k = 0 is the total mass, so out[0] is 1 for any normalised state. The
    // ordering is the cube's own: ascending k walks the six lines from the
    // bottom up, and the popcount cut keeps only the low-frequency harmonics,
    // so two clouds that differ in where their mass sits differ here too.
    void embed(float* out) const;
};

// The per-token logit bias the decode loop adds. `figureOfToken` maps a vocab
// id to a figure 0..63, or -1 when that token is not one of the 64 figure
// words. The bias for a figure h is weight * p[h] * 64, so a state that has
// made up its mind pushes its own word by `weight` and a state with nothing to
// say (uniform, p[h] = 1/64) pushes every figure word by weight/64 - which is
// the same for all 64 and therefore changes no ranking at all.
double priorLogit(const Q6& q, int figure, double weight);

}  // namespace q6
}  // namespace ix64

#endif  // IXMNN_Q6_HPP
