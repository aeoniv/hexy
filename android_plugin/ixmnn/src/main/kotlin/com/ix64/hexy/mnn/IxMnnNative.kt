package com.ix64.hexy.mnn

/**
 * Raw JNI surface over ixmnn_jni.cpp for Alibaba MNN inference.
 */
internal object IxMnnNative {

	external fun nativeEmbeddingCreate(configPath: String): Long
	external fun nativeEmbeddingDim(handle: Long): Int
	external fun nativeEmbed(handle: Long, text: String): FloatArray
	external fun nativeEmbeddingRelease(handle: Long)

	external fun nativeLlmCreate(configPath: String): Long
	external fun nativeChat(handle: Long, prompt: String, maxTokens: Int, expectVersion: Int): String
	external fun nativeChatStream(handle: Long, prompt: String, maxTokens: Int, expectVersion: Int): ByteArray

	@Volatile
	@JvmStatic
	var tokenSink: ((String) -> Unit)? = null

	@JvmStatic
	fun onChatToken(utf8: ByteArray) {
		if (utf8.isEmpty()) return
		tokenSink?.invoke(String(utf8, Charsets.UTF_8))
	}

	external fun nativeLlmRelease(handle: Long)

	// --- THE ENGINE SURFACE ---------------------------------------------------
	//
	// MNN's own `llm.hpp`, handed straight through: tokenizer_encode/decode,
	// apply_chat_template, set_config for sampling, getContext() for the
	// counters and getCurrentHistory/eraseHistory for the kv-cache window.
	// Worker thread only, like everything else in here.

	external fun nativeTokenize(handle: Long, text: String): IntArray
	external fun nativeDetokenize(handle: Long, tokenId: Int): String
	external fun nativeGetPerf(handle: Long): String
	external fun nativeSetSampling(handle: Long, temperature: Float, topP: Float, repetitionPenalty: Float): Boolean
	external fun nativeHistoryCount(handle: Long): Int
	external fun nativeEraseHistory(handle: Long, begin: Int, end: Int): Boolean
	external fun nativeApplyTemplate(handle: Long, prompt: String): String

	// --- Q6: the six-bit cube -------------------------------------------------
	//
	// One state p[64] over the 64 hexagrams, living in q6/q6.cpp beside the Qwen
	// decode loop that reads it as a prior. No handle: there is exactly one cube.

	external fun nativeQ6Reset(bits: Int)
	external fun nativeQ6Inject(bits: Int)
	external fun nativeQ6Uniform()
	external fun nativeQ6Anchor(bits: Int, amount: Float)
	external fun nativeQ6Step(bias: FloatArray, t: Float, beta: Float)
	external fun nativeQ6State(): FloatArray
	external fun nativeQ6SetState(state: FloatArray)
	external fun nativeQ6Argmax(): Int
	external fun nativeQ6Tension(): Float
	external fun nativeQ6BestNeighbour(bits: Int): Int
	external fun nativeQ6Embed(): FloatArray
	external fun nativeQ6SetPriorWeight(w: Float)
	external fun nativeQ6PriorWeight(): Float
	external fun nativeQ6SetFigureWords(words: Array<String>, version: Int)

	// The cast version stamped on the current figure-word push, and how many
	// times a chat has asked for one the cube did not have.
	external fun nativeQ6PriorMismatches(): Int
	external fun nativeQ6FigureVersion(): Int
}
