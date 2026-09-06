package com.ix64.hexy.mnn

/**
 * Raw JNI surface over `src/main/cpp/ixmnn_jni.cpp`, which in turn is a thin
 * translation of MNN's `llm.hpp` (vendored at 3.6.1 to match the prebuilt .so
 * files in `libs/mnn-jni/`).
 *
 * Nothing outside this package should touch it: the handles are naked
 * pointers, and every entry point must be called from the one worker thread
 * IxMnn owns (MNN's Executor is thread-local).
 */
internal object IxMnnNative {

	external fun nativeEmbeddingCreate(configPath: String): Long
	external fun nativeEmbeddingDim(handle: Long): Int
	external fun nativeEmbed(handle: Long, text: String): FloatArray
	external fun nativeEmbeddingRelease(handle: Long)

	external fun nativeLlmCreate(configPath: String): Long
	external fun nativeChat(handle: Long, prompt: String, maxTokens: Int): String

	/**
	 * PHASE 10c — THE SAME TURN, HANDED OVER AS IT IS PRODUCED.
	 *
	 * MNN 3.6.1's `llm.hpp` has no per-token callback; its `response(...)`
	 * writes each decoded token into an `std::ostream` as it goes. The C++ side
	 * puts a `std::streambuf` there and calls [onChatToken] from inside it — on
	 * THIS thread, inside this call — so a token reaches Godot at the moment it
	 * exists rather than at the moment the answer is finished.
	 *
	 * Returns the whole reply, the same bytes the callbacks carried, `<think>`
	 * blocks already gone. Raw UTF-8 for 9.8b's reason.
	 */
	external fun nativeChatStream(handle: Long, prompt: String, maxTokens: Int): ByteArray

	/**
	 * Where the tokens go. Set for the length of one generation by
	 * [IxMnn.chat_stream] and cleared in its `finally`; null means nobody is
	 * listening, which is the state this object is in almost all of the time.
	 *
	 * @Volatile because it is written on the Godot thread and read on the MNN
	 * worker. It is never two at once: [IxMnn.chat_stream] refuses a second
	 * stream while one is running.
	 */
	@Volatile
	@JvmStatic
	var tokenSink: ((String) -> Unit)? = null

	/**
	 * CALLED FROM C++, on the MNN worker thread, once per token-ish chunk.
	 * Bytes rather than a String because `NewStringUTF` speaks modified UTF-8
	 * and a model is under no obligation to (9.8b). The C++ side guarantees the
	 * chunk ends on a character boundary, so this decode never sees half a
	 * character.
	 */
	@JvmStatic
	fun onChatToken(utf8: ByteArray) {
		if (utf8.isEmpty()) return
		tokenSink?.invoke(String(utf8, Charsets.UTF_8))
	}

	// PHASE 11b — `nativeLook` IS DELETED, and this comment is where it stood.
	// One frame plus one question, answered as one line, through a separate
	// 1.7 GB Qwen2-VL session and a JPEG in the private cache. The eyes are a
	// MediaPipe detector in ixbody now; MNN here is chat and embeddings.

	external fun nativeLlmRelease(handle: Long)
	external fun nativeSetHexPrior(handle: Long, hexBits: Int, beta: Float): Boolean
}
