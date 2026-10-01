extends RefCounted

## THE ONE WEDGE -> TRIGRAM TABLE. Every surface that names one of the fly's
## eight ellipsoid-body wedges with a trigram reads it from here: the radar,
## the peer sheet and dashboard (through KingWen.WEDGE_TRIGRAM), the brain
## summary and the Qwen voice. Trigram codes are KingWen's: bit i = line i+1,
## bottom line first (0 Kun 000, 1 Zhen, 2 Kan, 3 Dui, 4 Gen, 5 Li, 6 Xun,
## 7 Qian 111).
##
## Wedge i is centred at i * TAU/8 in the allocentric frame, wedge 0 = North
## (scripts/brain/fly_central_complex.gd header), angles increasing clockwise.
##
## WHY THIS ORDER: THE REFLECTED GRAY CODE, g(i) = i ^ (i >> 1).
##   * The wedges are the cyclic group Z8 (a ring C8); the trigrams are the
##     cube Q3 = Z2^3. A Gray ring is a Hamiltonian cycle of Q3, i.e. a graph
##     map C8 -> Q3 that sends every ring edge to a cube edge. So one wedge
##     step = exactly one changing line (Hamming / geodesic distance 1 on Q3):
##     the calcium bump sliding one wedge reads as ONE moving line, never two
##     or three. The previous tables (code i, bitrev3, Fu Xi) all jump 2-3
##     lines somewhere round the ring.
##   * The half turn is a constant XOR: g(i+4) = g(i) ^ 0b110 for every i, so
##     rotating the dial by PI acts on the trigram as one fixed translation of
##     Z2^3 (HALF_TURN_MASK) -- the rotation is equivariant, not ad hoc.
##   * Antipodal = complement (Fu Xi's property) cannot hold on ANY Gray ring:
##     Q3 is bipartite, a 4-step path keeps weight parity, a complement flips
##     it. Adjacency was chosen over antipodal complement.
##   * Among the Gray rings this one is the closed form (no magic list), keeps
##     Kun at wedge 0 (fly_central_complex: 0 = Earth / North) and Zhen at
##     wedge 1, as the brain summary already had.
const WEDGES := 8

## wedge -> trigram code. g(i) = i ^ (i >> 1).
const TRIGRAM: Array[int] = [0, 1, 3, 2, 6, 7, 5, 4]

## trigram code -> wedge. The inverse of TRIGRAM.
const WEDGE: Array[int] = [0, 1, 3, 2, 7, 6, 4, 5]

## g(i + 4) == g(i) ^ HALF_TURN_MASK for every wedge i.
const HALF_TURN_MASK := 0b110

## Hanzi per trigram code (simplified, as the radar has always printed them).
const HANZI: Array[String] = ["坤", "震", "坎", "兑", "艮", "离", "巽", "乾"]

## Radar perimeter labels in WEDGE order: hanzi + Unicode trigram glyph.
## Derived from TRIGRAM; tests/test_wedge_trigram_table.gd checks the glyphs
## against KingWen.trigram_glyph so the two cannot drift.
const LABELS: Array[String] = ["坤 ☷", "震 ☳", "兑 ☱", "坎 ☵", "巽 ☴", "乾 ☰", "离 ☲", "艮 ☶"]


## The trigram code on a wedge. Any integer wraps round the ring.
static func trigram(wedge: int) -> int:
	return TRIGRAM[posmod(wedge, WEDGES)]


## The wedge a trigram code sits on.
static func wedge_of_trigram(code: int) -> int:
	return WEDGE[code & 7]


## Which wedge an allocentric heading in radians falls in:
## round(heading / (TAU/8)) mod 8, the same rounding the brain uses.
static func wedge_of_heading(heading_rad: float) -> int:
	return posmod(int(round(heading_rad / (TAU / float(WEDGES)))), WEDGES)


## The trigram code an allocentric heading names.
static func trigram_of_heading(heading_rad: float) -> int:
	return trigram(wedge_of_heading(heading_rad))


## The perimeter label ("坤 ☷") for a wedge.
static func label(wedge: int) -> String:
	return LABELS[posmod(wedge, WEDGES)]
