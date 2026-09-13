class_name FlyConductance
extends RefCounted

## Connectome-constrained synaptic conductance matrix for Hexy's 6 biological needs.
## Derived from FlyWire & MaleCNS synaptic connectivity between the 6 primary neuromodulatory clusters:
##   0: BODY       (Dopamine, PAM/PPL1 cluster - cuticular integrity, motor vigor)
##   1: FOOD       (Neuropeptide F, SEZ/Antennal Lobe - energy reserve, hunger/satiety)
##   2: BREATH     (Octopamine, VUM cluster - flight arousal, metabolic ventilation)
##   3: REST       (GABA/5-HT, dFB & R5 ring neurons - sleep homeostat, synaptic pruning)
##   4: FOCUS      (Acetylcholine, Central Complex EB/PB - angular heading attractor)
##   5: CONNECTION (Fruitless / pC1 cluster - pheromonal, conspecific social resonance)
##
## Pure arithmetic, zero clock calls, deterministic.

const CHANNELS := 6

# Synaptic weight matrix W[target][source]
# Positive = Excitatory (ACh, DA, OA)
# Negative = Inhibitory (GABA, Glu)
const SYNAPSE_WEIGHTS: Array = [
	# Target 0: BODY (DA)
	# Modulated by: self-damping, hunger foraging (+), flight arousal (+), sleep fatigue (-)
	[-0.05, -0.15,  0.25, -0.30,  0.10,  0.08],
	
	# Target 1: FOOD (NPF)
	# Depleted by high motor vigor (-) and flight arousal (-); restored by rest (+)
	[-0.20, -0.02, -0.25,  0.15, -0.05,  0.05],
	
	# Target 2: BREATH (OA)
	# Reciprocal inhibition with REST (-0.45); boosted by focus (+) and motor tone (+)
	[ 0.15, -0.10, -0.05, -0.45,  0.20,  0.05],
	
	# Target 3: REST (dFB)
	# Reciprocal inhibition with BREATH (-0.50); accumulated by long motor activity (+)
	[ 0.10,  0.10, -0.50, -0.02, -0.15, -0.05],
	
	# Target 4: FOCUS (CX)
	# Driven by hunger seeking (+), supported by flight arousal (+) and social cues (+)
	[ 0.10, -0.20,  0.20, -0.25, -0.05,  0.15],
	
	# Target 5: CONNECTION (fru)
	# Supported by rested focus (+); depressed by extreme hunger (-) or severe bodily fatigue (-)
	[-0.10, -0.15,  0.05,  0.10,  0.15, -0.02],
]

## Steps the 6 needs according to connectome synaptic coupling.
## Takes current needs vector in [0.0, 1.0]^6 and time delta in seconds.
## Returns updated needs vector strictly bounded to [0.0, 1.0]^6.
static func step_coupling(needs: PackedFloat64Array, dt_sec: float) -> PackedFloat64Array:
	assert(needs.size() == CHANNELS)
	var delta := PackedFloat64Array()
	delta.resize(CHANNELS)
	delta.fill(0.0)
	
	# Clamp single-step dt to avoid Euler numerical instability across multi-hour leaps
	var safe_dt: float = minf(dt_sec, 60.0) * 0.02
	
	for target in range(CHANNELS):
		var row: Array = SYNAPSE_WEIGHTS[target]
		var net_current := 0.0
		for source in range(CHANNELS):
			# Activation centered around resting setpoint 0.5
			var source_act: float = needs[source] - 0.5
			net_current += float(row[source]) * source_act
		delta[target] = net_current * safe_dt
	
	var out := PackedFloat64Array()
	out.resize(CHANNELS)
	for i in range(CHANNELS):
		out[i] = clampf(needs[i] + delta[i], 0.0, 1.0)
	return out

## Converts the 6 continuous needs into line biases in [-1.0, 1.0] for Q6Lattice.
## Line is Yang (biased > 0) when need >= 0.5; Yin (biased < 0) when need < 0.5.
static func to_q6_bias(needs: PackedFloat64Array) -> PackedFloat64Array:
	assert(needs.size() == CHANNELS)
	var bias := PackedFloat64Array()
	bias.resize(CHANNELS)
	for i in range(CHANNELS):
		bias[i] = clampf((needs[i] - 0.5) * 2.0, -1.0, 1.0)
	return bias
