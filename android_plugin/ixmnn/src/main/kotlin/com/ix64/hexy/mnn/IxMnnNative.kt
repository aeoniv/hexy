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
	external fun nativeChat(handle: Long, prompt: String, maxTokens: Int): String
	external fun nativeChatStream(handle: Long, prompt: String, maxTokens: Int): ByteArray

	@Volatile
	@JvmStatic
	var tokenSink: ((String) -> Unit)? = null

	@JvmStatic
	fun onChatToken(utf8: ByteArray) {
		if (utf8.isEmpty()) return
		tokenSink?.invoke(String(utf8, Charsets.UTF_8))
	}

	external fun nativeLlmRelease(handle: Long)
}
