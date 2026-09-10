extends SceneTree
## Comprehensive Benchmark Suite comparing Pure I-Ching Persona vs Enhanced Structural Cybernetics

const MnnRuntime = preload("res://scripts/brain/mnn_runtime.gd")
const CreatureBall3D = preload("res://scripts/creature_ball_3d.gd")
const MandalaDial2D = preload("res://scripts/mandala_dial_2d.gd")

const ITERATIONS := 5000

func _initialize() -> void:
	print("\n=======================================================")
	print("       IX64 HEXY BENCHMARK SUITE: PURE vs ENHANCED      ")
	print("=======================================================\n")
	
	var mnn := MnnRuntime.new()
	mnn.chat_start()
	var embed_dim := mnn.embed_start()
	
	print("[SYSTEM SPECS]")
	print("Godot Engine: ", Engine.get_version_info()["string"])
	print("MNN Backend:  ", mnn.backend_name())
	print("Embed Dim:    ", embed_dim)
	print("Iterations:   ", ITERATIONS)
	print("-------------------------------------------------------\n")
	
	# ----------------------------------------------------
	# TEST 1: State Mutation & Math Calculation Throughput
	# ----------------------------------------------------
	print("TEST 1: State Mutation & Math Calculation (5,000 cycles)")
	
	# Pure Mode: Classical reading lookup
	var t0 := Time.get_ticks_usec()
	for i in range(ITERATIONS):
		var wen: int = (i % 64) + 1
		var name_str: String = "Hexagram_%d" % wen
		var reading: String = "Classical Reading for #%d %s" % [wen, name_str]
	var t_pure_state := Time.get_ticks_usec() - t0
	
	# Enhanced Mode: 6-bit binary unpacking, moving lines, tensegrity struts
	var creature := CreatureBall3D.new()
	t0 = Time.get_ticks_usec()
	for i in range(ITERATIONS):
		var wen: int = (i % 64) + 1
		var bits: int = i & 0x3F
		var moving: int = (wen % 6)
		var lower_trigram: int = bits & 7
		var upper_trigram: int = (bits >> 3) & 7
		var inverted_bits: int = (~bits) & 0x3F
		var mutating_bits: int = bits ^ (1 << moving)
		# Tensegrity structural equilibrium calculation
		creature.set_hexagram(mutating_bits, moving)
	var t_enh_state := Time.get_ticks_usec() - t0
	creature.queue_free()
	
	print("  -> Pure Mode State Time:     %10d us  (%.3f us/op)" % [t_pure_state, float(t_pure_state) / ITERATIONS])
	print("  -> Enhanced Mode State Time: %10d us  (%.3f us/op)" % [t_enh_state, float(t_enh_state) / ITERATIONS])
	print("  -> Computational Delta:      %.2fx factor" % [float(t_enh_state) / max(1.0, float(t_pure_state))])
	print("-------------------------------------------------------\n")
	
	# ----------------------------------------------------
	# TEST 2: Neural Prompt Construction & Token Payload
	# ----------------------------------------------------
	print("TEST 2: Prompt Payload & Construction Throughput (5,000 cycles)")
	
	t0 = Time.get_ticks_usec()
	var pure_sample_prompt := ""
	for i in range(ITERATIONS):
		var wen: int = (i % 64) + 1
		pure_sample_prompt = "You are the ancient I-Ching oracle. In character as the Book of Changes, speak poetically and provide concise wisdom on Hexagram #%d." % wen
	var t_pure_prompt := Time.get_ticks_usec() - t0
	
	t0 = Time.get_ticks_usec()
	var enh_sample_prompt := ""
	for i in range(ITERATIONS):
		var wen: int = (i % 64) + 1
		var bits: int = i & 0x3F
		enh_sample_prompt = "Explain I-Ching Hexagram #%d: Binary 0b%06s. Moving line %d mutating structure. Analyze polarity balance and structural guidance." % [
			wen, String.num_int64(bits, 2).pad_zeros(6), (wen % 6) + 1
		]
	var t_enh_prompt := Time.get_ticks_usec() - t0
	
	print("  -> Pure Prompt Time:         %10d us  (Bytes: %d)" % [t_pure_prompt, pure_sample_prompt.length()])
	print("  -> Enhanced Prompt Time:     %10d us  (Bytes: %d)" % [t_enh_prompt, enh_sample_prompt.length()])
	print("  -> Pure Prompt Sample:       \"%s\"" % pure_sample_prompt)
	print("  -> Enhanced Prompt Sample:   \"%s\"" % enh_sample_prompt)
	print("-------------------------------------------------------\n")
	
	# ----------------------------------------------------
	# TEST 3: Semantic Embedding Clustering & Vector Distances
	# ----------------------------------------------------
	print("TEST 3: Semantic Vector Clustering (GTE-MNN Dimension: %d)" % embed_dim)
	
	var pure_terms := [
		"ancient wisdom sage",
		"classical divination oracle",
		"poetic philosophy balance",
		"book of changes moral virtue"
	]
	var enh_terms := [
		"icosahedron tensegrity equilibrium",
		"6-bit binary state mutation",
		"cybernetic strut tension dynamics",
		"phase space vector attractor"
	]
	
	var pure_vecs: Array[PackedFloat32Array] = []
	for term in pure_terms:
		pure_vecs.append(mnn.embed(term))
		
	var enh_vecs: Array[PackedFloat32Array] = []
	for term in enh_terms:
		enh_vecs.append(mnn.embed(term))
		
	var pure_internal_sim := 0.0
	var enh_internal_sim := 0.0
	var cross_sim := 0.0
	var pairs := 0
	
	for i in range(pure_vecs.size()):
		for j in range(i + 1, pure_vecs.size()):
			pure_internal_sim += MnnRuntime.cosine(pure_vecs[i], pure_vecs[j])
			enh_internal_sim += MnnRuntime.cosine(enh_vecs[i], enh_vecs[j])
			pairs += 1
			
	var cross_pairs := 0
	for i in range(pure_vecs.size()):
		for j in range(enh_vecs.size()):
			cross_sim += MnnRuntime.cosine(pure_vecs[i], enh_vecs[j])
			cross_pairs += 1
			
	pure_internal_sim /= max(1, pairs)
	enh_internal_sim /= max(1, pairs)
	cross_sim /= max(1, cross_pairs)
	
	print("  -> Pure Persona Semantic Cohesion:    %.4f" % pure_internal_sim)
	print("  -> Enhanced Structural Cohesion:      %.4f" % enh_internal_sim)
	print("  -> Pure vs Enhanced Orthogonality:    %.4f (Cross-similarity)" % cross_sim)
	print("  -> Semantic Separation:               %.4f" % (1.0 - cross_sim))
	print("-------------------------------------------------------\n")
	
	# ----------------------------------------------------
	# TEST 4: MNN Qwen Chat Response Generation
	# ----------------------------------------------------
	print("TEST 4: MNN Qwen Chat Consultation Test")
	t0 = Time.get_ticks_usec()
	var pure_reply: String = mnn.chat(pure_sample_prompt)
	var t_pure_chat := Time.get_ticks_usec() - t0
	
	t0 = Time.get_ticks_usec()
	var enh_reply: String = mnn.chat(enh_sample_prompt)
	var t_enh_chat := Time.get_ticks_usec() - t0
	
	print("  -> Pure Mode Latency:        %10d us (Len: %d chars)" % [t_pure_chat, pure_reply.length()])
	print("  -> Enhanced Mode Latency:    %10d us (Len: %d chars)" % [t_enh_chat, enh_reply.length()])
	print("  -> Pure Mode Response:       \"%s\"" % pure_reply)
	print("  -> Enhanced Mode Response:   \"%s\"" % enh_reply)
	print("\n=======================================================")
	print("                BENCHMARK COMPLETE                     ")
	print("=======================================================\n")
	
	quit(0)
