# Q6, native: one cube, three readers

Q6 is the six-dimensional hypercube whose 64 corners are the 64 hexagrams. Two
figures are neighbours exactly when one line differs. A state `p[64]` over those
corners moved by two forces — heat along the edges, and a Gibbs pull toward the
corners six line-biases agree with — used to exist only as GDScript with one
caller. It is now ONE implementation per platform, living inside the ixmnn
plugin on device, with GDScript as a thin client over it.

## The diagram, in words

```
                      G O D O T
   Alchemy -> Pacing ---- holds ----> Q6Core          scripts/core/iching/q6.gd
      (senses)   |                      |
                 |                      +-- native? --> IxMnn (Godot plugin)
                 |                      |                     Kotlin, @UsedByGodot
                 |                      |                       q6_reset / q6_inject
                 |                      |                       q6_uniform / q6_anchor
                 |                      |                       q6_step / q6_state
                 |                      |                       q6_argmax / q6_tension
                 |                      |                       q6_best_neighbour
                 |                      |                       q6_embed
                 |                      |                       q6_set_prior_weight
                 |                      |                       q6_set_figure_words
                 |                      |                            |
                 |                      |                         IxMnnNative
                 |                      |                         external fun ...
                 |                      |                            |  JNI
                 |                      |                            v
                 |                      |                    ixmnn_jni.cpp
                 |                      |              +---------------------------+
                 |                      |              |  gQ6  (ONE ix64::q6::Q6)  |
                 |                      |              |  q6/q6.cpp  q6/q6.hpp     |
                 |                      |              |    pure C++17, no MNN     |
                 |                      |              +------------+--------------+
                 |                      |                           |  read as a prior,
                 |                      |                           |  once per token
                 |                      |              +------------v--------------+
                 |                      |              |  generateWithPrior()      |
                 |                      |              |   forward -> applyPrior   |
                 |                      |              |     -> sample -> decode   |
                 |                      |              +------------+--------------+
                 |                      |                           |
                 |                      |              +------------v--------------+
                 |                      |              |  MNN runtime (libMNN,     |
                 |                      |              |  libllm) - Qwen weights   |
                 |                      |              +---------------------------+
                 |                      |
                 |                      +-- else -----> q6_lattice.gd (desktop)
                 |                                       the owner's original
                 |                                       arithmetic, untouched
                 |
                 +-- Pacing.mass, best_neighbour(), the line that turns

   Q6Embed.cloud(cube) -> 32 floats -> WMN room / mesh
   MockLlm             -> the desktop answer when no weights are on the device
```

Three readers, one state:

1. **Pacing** moves it every tick and asks it which line of the BODY figure
   turns.
2. **The Qwen decode loop** reads it as a prior, once per token, inside the
   plugin — no round trip to Godot.
3. **Q6Embed.cloud()** turns it into a point in R^32 for the room and the mesh.

## Where the arithmetic lives

| | |
|---|---|
| `android_plugin/ixmnn/src/main/cpp/q6/q6.hpp` `q6.cpp` | the cube, pure C++17, no MNN, no JNI |
| `scripts/core/iching/q6_lattice.gd` | the desktop cube, untouched, still the owner's |
| `scripts/core/iching/q6.gd` (`Q6Core`) | the thin client that picks one of the two |

`Q6Core` dispatches to the plugin when `Engine.has_singleton("IxMnn")` **and**
that singleton actually answers `q6_state` — a plugin built before this change
does not, and that is a fallback, not an error.

**The native lease.** There is exactly one `gQ6` in the plugin, so exactly one
`Q6Core` may speak to it: the first instance built takes the lease and every
later one runs the desktop arithmetic. Pacing is built first and holds it.
`is_native()` says which side a given object is on; both sides answer the same
numbers, so nothing upstream branches.

## Held to the same numbers

`tools/q6_golden.gd` replays eight fixed cases through the GDScript and writes
every number it saw to `tests/golden/q6_golden.json`: the whole 64-vector, the
argmax, the tension, the line that turns, and all 32 Walsh coefficients.

- `tests/q6_core.gd` checks the Godot client against that file.
- `tests/native/q6_test.cpp` checks the C++ against the **same** file.

Neither side can drift without a suite going red. Regenerate only when the
arithmetic is meant to change:

```
godot --headless --path . -s tools/q6_golden.gd
```

Build and run the native side (no MNN, no NDK, no Android needed):

```
cl /std:c++17 /EHsc /O2 /I android_plugin\ixmnn\src\main\cpp ^
   tests\native\q6_test.cpp android_plugin\ixmnn\src\main\cpp\q6\q6.cpp
q6_test.exe tests\golden\q6_golden.json
```

## The embedding

`embed()` runs the unnormalised FWHT over `p`, walks `k` from 0 to 63 in
**ascending k**, keeps every `k` whose popcount is 3 or less, and takes the
first 32. 42 of the 64 indices qualify and the cut falls at `k = 37`, so the 32
kept are, by popcount, `1 + 6 + 13 + 12`.

`k = 0` is the total mass, so `out[0]` is 1 for any normalised state; the rest
are the cube's own low-frequency harmonics. Nothing here is learned, so it is
the same on every device and in every build.

## What the prior does

Godot hands the plugin 64 ASCII figure words indexed by hexagram **bits** — the
King Wen pinyin straight out of `scripts/core/iching/king_wen.gd`, so the native
side keeps no second copy of that table to drift. On the first decode each word
is tokenized once and its **first** token id is kept (with a leading space, so
the id is the mid-sentence one a BPE tokenizer would actually emit).

Then, once per token, between `forward` and `sample`:

```
logits[token_of(h)] += w * p[h] * 64      for h in 0..63
```

The `* 64` is what makes the weight mean something fixed:

- A cube that has **made up its mind** (`p[h] = 1`) pushes its own figure word
  by `w * 64` and no other word at all.
- A cube with **nothing to say** (uniform, `p[h] = 1/64`) pushes all 64 words by
  exactly `w` — the same for every one of them, so it changes no ranking.

The prior leans; it never decides. Everything else is MNN's: its module, its KV
cache, its sampler, its tokenizer, its stop tokens.

`w` defaults to **0**, which is the old behaviour byte for byte:
`generateWithPrior` returns false immediately and `Llm::response()` runs.
`Mnn.set_prior_weight(w)` turns it on; `Mnn.info()["q6_prior_weight"]` reports
it, and is 0 anywhere the plugin is not.

## What was not possible, and what was done instead

**`llm/llm.hpp` exposes no logit-processor hook and no sampler callback.**
`Llm::response()` runs prefill, sampling and the stop check behind one call with
nothing in the middle. `Llm::sample()` is `virtual` and public, but
`Llm::createLLM()` hands back a concrete subclass already constructed, so it
cannot be overridden after the fact.

What the header **does** expose publicly is every step of the loop separately:

```
Express::VARP forward(const std::vector<int>& input_ids, bool is_prefill);
virtual int   sample(Express::VARP logits, int offset = 0, int size = 0);
bool          is_stop(int token);
std::string   tokenizer_decode(int token);
std::vector<int> tokenizer_encode(const std::string& query);
std::string   apply_chat_template(const std::string& user_content) const;
void          generate_init(std::ostream* os, const char* end_with);
```

So `generateWithPrior()` in `ixmnn_jni.cpp` runs exactly those steps itself and
adds the cube's lean in the one place it belongs — between `forward` and
`sample`. This is the real thing, not a post-hoc rescoring of finished text and
not a prompt trick.

### Open, and honest about it

- **Not yet run on a device.** The APK was not exported as part of this change,
  so `generateWithPrior` has been reviewed against `llm.hpp` but never executed
  against a loaded Qwen. The two risks are (a) KV-cache bookkeeping that
  `Llm::generate()` may do around `forward()` that this loop does not, and (b)
  the exact rank of the logits tensor. `applyPrior` handles the second by
  reading `getInfo()->dim.back()` as the vocab and biasing only the last row.
  The first is guarded the only way it can be until a device run: the whole loop
  is inside a `try`, any throw returns false, and the caller falls back to
  `Llm::response()`. **Next step on device: set the weight to 0.2, watch one
  answer, then compare against weight 0.**
- The prior biases the **first token** of a figure word only. Biasing a whole
  multi-token word would need per-step state about which word is in progress;
  the first token is where the choice is actually made, and it is the honest
  cheap version.
- `Q6Core.set_state()` crosses JNI as `float32`, so a cloud saved and restored
  through the native path is float32-accurate, not float64. The desktop path is
  exact. Nothing currently saves clouds.
- `tools/q6_golden.gd` is a generator, not a suite. It is not in the test run;
  it is run by hand when the arithmetic changes.
