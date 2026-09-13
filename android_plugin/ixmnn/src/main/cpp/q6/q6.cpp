// q6.cpp - the arithmetic of the six-bit cube. See q6.hpp.

#include "q6.hpp"

#include <cmath>

namespace ix64 {
namespace q6 {

int popcount(int k) {
    int n = 0;
    for (int i = 0; i < kLines; ++i) {
        if ((k & (1 << i)) != 0) ++n;
    }
    return n;
}

double lineSign(int h, int i) {
    return ((h & (1 << i)) != 0) ? 1.0 : -1.0;
}

int reverse(int h) {
    int r = 0;
    for (int i = 0; i < kLines; ++i) {
        if ((h & (1 << i)) != 0) r |= 1 << (kLines - 1 - i);
    }
    return r;
}

void fwht(double* v) {
    for (int span = 1; span < kStates; span <<= 1) {
        for (int i = 0; i < kStates; i += (span << 1)) {
            for (int j = i; j < i + span; ++j) {
                const double a = v[j];
                const double b = v[j + span];
                v[j] = a + b;
                v[j + span] = a - b;
            }
        }
    }
}

Q6::Q6() { reset(0); }

void Q6::reset(int bits) {
    for (int h = 0; h < kStates; ++h) p[h] = 0.0;
    p[bits & kAllLines] = 1.0;
}

void Q6::uniform() {
    for (int h = 0; h < kStates; ++h) p[h] = 1.0 / static_cast<double>(kStates);
}

void Q6::anchor(int bits, double amount) {
    for (int h = 0; h < kStates; ++h) p[h] *= (1.0 - amount);
    p[bits & kAllLines] += amount;
}

void Q6::step(const double bias[kLines], double t, double beta) {
    // The heat step, in the basis where it is a multiply.
    double c[kStates];
    for (int h = 0; h < kStates; ++h) c[h] = p[h];
    fwht(c);
    for (int k = 0; k < kStates; ++k) {
        c[k] *= std::exp(-t * static_cast<double>(popcount(k)));
    }
    fwht(c);
    for (int h = 0; h < kStates; ++h) c[h] /= static_cast<double>(kStates);

    // The field the six lines make over the corners, and the Gibbs pull.
    double total = 0.0;
    for (int h = 0; h < kStates; ++h) {
        double u = 0.0;
        for (int i = 0; i < kLines; ++i) u += bias[i] * lineSign(h, i);
        const double v = c[h] * std::exp(beta * u);
        c[h] = v;
        total += v;
    }
    if (!(total > 0.0)) {
        uniform();
        return;
    }
    for (int h = 0; h < kStates; ++h) p[h] = c[h] / total;
}

int Q6::argmax() const {
    int best = 0;
    for (int h = 0; h < kStates; ++h) {
        if (p[h] > p[best]) best = h;
    }
    return best;
}

double Q6::tension() const {
    double total = 0.0;
    for (int h = 0; h < kStates; ++h) total += p[h];
    if (!(total > 0.0)) return 0.0;
    double ent = 0.0;
    for (int h = 0; h < kStates; ++h) {
        const double q = p[h] / total;
        if (q > 0.0) ent -= q * std::log(q);
    }
    const double norm = ent / std::log(static_cast<double>(kStates));
    if (norm < 0.0) return 0.0;
    if (norm > 1.0) return 1.0;
    return norm;
}

int Q6::bestNeighbour(int bits, double tieEps) const {
    const int b = bits & kAllLines;
    double top = 0.0;
    for (int i = 0; i < kLines; ++i) {
        const double m = p[b ^ (1 << i)];
        if (m > top) top = m;
    }
    if (!(top > 0.0)) return 0;
    const double floorMass = top * (1.0 - tieEps);
    for (int i = 0; i < kLines; ++i) {
        if (p[b ^ (1 << i)] >= floorMass) return i;
    }
    return 0;
}

void Q6::embed(float* out) const {
    double c[kStates];
    for (int h = 0; h < kStates; ++h) c[h] = p[h];
    fwht(c);
    int n = 0;
    for (int k = 0; k < kStates && n < kEmbedDim; ++k) {
        if (popcount(k) <= 3) out[n++] = static_cast<float>(c[k]);
    }
    while (n < kEmbedDim) out[n++] = 0.0f;
}

double priorLogit(const Q6& q, int figure, double weight) {
    if (figure < 0 || figure >= kStates) return 0.0;
    return weight * q.p[figure] * static_cast<double>(kStates);
}

}  // namespace q6
}  // namespace ix64
