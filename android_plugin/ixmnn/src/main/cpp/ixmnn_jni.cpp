// ixmnn_jni.cpp — the only native code this project owns.
//
// MNN ships prebuilt `libllm.so` (the transformers/llm engine) in every
// android release zip, but *no* JNI layer for it: `libmnncore.so` only exports
// the old `com.taobao.android.mnn.MNNNetNative` Interpreter/Session wrapper,
// which knows nothing about tokenizers, KV cache, or chat templates. MNN's own
// Android chat app builds its own JNI on top of `llm.hpp`, so we do the same —
// minimally. Everything below is a thin translation of the C++ API in
// `include/llm/llm.hpp` (vendored at tag 3.6.1, matching the .so files in
// android_plugin/libs/mnn-jni/).
//
// Two handles, both opaque jlongs owned by IxMnn.kt:
//   Embedding — MNN::Transformer::Embedding, gives embed() a real vector.
//   Llm       — MNN::Transformer::Llm, gives chat() a real reply.
//
// Threading: MNN's Llm is not reentrant. IxMnn.kt serialises every call on a
// single worker thread; this file assumes that and does no locking.

#include <jni.h>
#include <android/log.h>

#include <sstream>
#include <streambuf>
#include <string>
#include <vector>

#include <MNN/expr/Expr.hpp>
#include <MNN/expr/ExprCreator.hpp>
#include <llm/llm.hpp>
#include "q6_spectral.hpp"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "IxMnnNative", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "IxMnnNative", __VA_ARGS__)

using MNN::Transformer::Embedding;
using MNN::Transformer::Llm;

namespace {

std::string toStd(JNIEnv* env, jstring s) {
    if (s == nullptr) return {};
    const char* raw = env->GetStringUTFChars(s, nullptr);
    std::string out(raw ? raw : "");
    if (raw) env->ReleaseStringUTFChars(s, raw);
    return out;
}

// Qwen-family models emit <think>...</think> before the answer. Hexy speaks one
// line; the reasoning is not the line.
std::string stripThink(const std::string& s) {
    const std::string open = "<think>", close = "</think>";
    auto b = s.find(open);
    auto e = s.find(close);
    std::string out;
    if (e == std::string::npos) {
        // Hit the token budget mid-thought: there is no answer in here, only
        // reasoning. Better to say nothing than to say the reasoning.
        if (b == std::string::npos) return s;
        out = s.substr(0, b);
    } else if (b == std::string::npos || b > e) {
        out = s.substr(e + close.size());
    } else {
        out = s.substr(0, b) + s.substr(e + close.size());
    }
    auto first = out.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    auto last = out.find_last_not_of(" \t\r\n");
    return out.substr(first, last - first + 1);
}

// ---------------------------------------------------------------- streaming
//
// PHASE 10c. THE ROOT OF THE SILENCE, AND IT WAS NEVER THE FSM.
//
// `Llm::response(prompt, &os, ...)` writes each decoded token into the ostream
// AS IT IS PRODUCED and returns when the whole answer is done. Until this phase
// that ostream was an `std::ostringstream` nobody read until the call returned,
// so a 0.6B model producing forty tokens at four tokens a second was ten
// seconds of a phone saying nothing while the first word had been ready in two.
//
// MNN 3.6.1's `llm.hpp` offers NO per-token callback — `setWavformCallback` is
// the audio lane and nothing else in the header takes a `std::function`. The
// stream IS the callback road, and it is the one MNN's own Android chat app
// takes (its `LlmStreamBuffer`). So: a `std::streambuf` whose `xsputn` is the
// per-token door, and the JNI worker thread calls straight back up into Kotlin
// from inside it. No thread is attached and none needs to be — this runs on the
// very Java thread that called in, inside its own call frame.
//
// TWO THINGS THE FILTER MUST DO, and both are because a token boundary is not a
// meaning boundary:
//
//   1. `<think>` MAY NOT BE SPOKEN. `stripThink` above works on a finished
//      string; a stream has to decide before it has seen the end. So the tags
//      are matched incrementally and anything that could still turn out to be
//      the beginning of one is held back — at most six bytes of latency.
//   2. A UTF-8 SEQUENCE MAY NOT BE CUT IN HALF. MNN emits bytes, and a token
//      boundary can land in the middle of a three-byte character. Kotlin
//      decodes with a real UTF-8 decoder (9.8b's lesson), and half a character
//      would decode to U+FFFD forever after. The tail of every chunk is cut on
//      a character boundary and the remainder waits for the next token.
//
// WHAT COMES BACK AT THE END is the SAME text the stream emitted, assembled
// here rather than re-derived — so "what was spoken" and "what was said" can
// never disagree, which is the one bug a streaming mouth can have that a
// blocking one cannot.

// The longest suffix of `s` that is a proper prefix of `tag`. `"i see <thi"`
// against `"<think>"` answers 4: those four bytes might be a tag and must wait.
size_t tagPrefixLen(const std::string& s, const std::string& tag) {
    const size_t max = s.size() < tag.size() - 1 ? s.size() : tag.size() - 1;
    for (size_t n = max; n > 0; --n) {
        if (s.compare(s.size() - n, n, tag, 0, n) == 0) return n;
    }
    return 0;
}

// How many bytes at the end of `s` are an INCOMPLETE UTF-8 sequence. 0 for a
// string that ends on a character boundary, which is the common case.
size_t danglingUtf8(const std::string& s) {
    const size_t n = s.size();
    for (size_t back = 1; back <= 4 && back <= n; ++back) {
        const auto b = static_cast<unsigned char>(s[n - back]);
        if ((b & 0xC0) == 0x80) continue;  // continuation byte, keep walking
        size_t need = 1;
        if ((b & 0xE0) == 0xC0) need = 2;
        else if ((b & 0xF0) == 0xE0) need = 3;
        else if ((b & 0xF8) == 0xF0) need = 4;
        return back < need ? back : 0;
    }
    return 0;
}

// The per-token door. Everything MNN writes passes through `feed`; whatever
// survives the two filters goes out through `sink_` and is also kept, so the
// caller gets the identical text back at the end.
class TokenStream : public std::streambuf {
public:
    using Sink = void (*)(void*, const std::string&);
    TokenStream(Sink sink, void* ctx) : sink_(sink), ctx_(ctx) {}

    // The last held-back bytes, once generation is over. A stream that ended
    // mid-tag was never a tag.
    void finish() {
        if (inThink_) { pending_.clear(); return; }
        emit(pending_);
        pending_.clear();
    }

    const std::string& text() const { return out_; }

protected:
    std::streamsize xsputn(const char* s, std::streamsize n) override {
        if (s != nullptr && n > 0) feed(std::string(s, static_cast<size_t>(n)));
        return n;
    }

    int_type overflow(int_type c) override {
        if (c != traits_type::eof()) {
            const char ch = static_cast<char>(c);
            feed(std::string(1, ch));
        }
        return c;
    }

private:
    static const std::string& kOpen() { static const std::string t = "<think>"; return t; }
    static const std::string& kClose() { static const std::string t = "</think>"; return t; }

    void emit(const std::string& s) {
        if (s.empty()) return;
        out_ += s;
        sink_(ctx_, s);
    }

    void feed(const std::string& chunk) {
        pending_ += chunk;
        while (true) {
            if (inThink_) {
                const auto e = pending_.find(kClose());
                if (e == std::string::npos) {
                    // Discard everything that cannot still be the closing tag.
                    const size_t keep = tagPrefixLen(pending_, kClose());
                    pending_ = pending_.substr(pending_.size() - keep);
                    return;
                }
                pending_.erase(0, e + kClose().size());
                inThink_ = false;
                continue;
            }
            const auto b = pending_.find(kOpen());
            if (b != std::string::npos) {
                emit(pending_.substr(0, b));
                pending_.erase(0, b + kOpen().size());
                inThink_ = true;
                continue;
            }
            // Hold back whatever might still become a tag, and whatever might
            // still become the rest of a character.
            size_t hold = tagPrefixLen(pending_, kOpen());
            if (hold == 0) hold = danglingUtf8(pending_);
            if (hold >= pending_.size()) return;
            emit(pending_.substr(0, pending_.size() - hold));
            pending_ = pending_.substr(pending_.size() - hold);
            return;
        }
    }

    Sink sink_;
    void* ctx_;
    std::string pending_;
    std::string out_;
    bool inThink_ = false;
};

// ── THE ONE CLASS THIS LIBRARY CALLS BACK INTO ──────────────────────────────
//
// Found by NAME rather than taken from a call's parameters, cached ONCE, and
// held as a global reference for the life of the process. See the JniSink note
// below for the abort that made this necessary.
//
// WHAT MAY AND MAY NOT BE CACHED, since this is the file that got it wrong:
//   * a jmethodID MAY be cached — it is not a reference and does not move;
//   * a jclass MAY NOT, unless it is made GLOBAL first. FindClass returns a
//     LOCAL reference, valid only inside the frame that asked for it;
//   * a JNIEnv* MAY NOT cross threads, ever. The JavaVM* may, which is why the
//     VM is what is cached and the env is fetched per thread.
const char* const kNativeClassName = "com/ix64/hexy/mnn/IxMnnNative";

JavaVM* gVm = nullptr;
jclass gNativeClass = nullptr;      // GLOBAL ref, or null if the lookup failed
jmethodID gOnChatToken = nullptr;   // IDs are safe to cache; refs are not

// THE ENV FOR *THIS* THREAD. The streaming emit runs on the ixmnn worker inside
// the same call frame that entered from Kotlin, so it already has the right env
// and this is not on that path. It exists so that a future callback arriving on
// a thread MNN owns cannot reintroduce the family of bug this file just paid
// for: `attached` tells the caller whether it must detach again.
JNIEnv* envForThread(bool* attached) {
    if (attached != nullptr) *attached = false;
    if (gVm == nullptr) return nullptr;
    JNIEnv* env = nullptr;
    const jint got = gVm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (got == JNI_OK) return env;
    if (got != JNI_EDETACHED) return nullptr;
    if (gVm->AttachCurrentThread(&env, nullptr) != JNI_OK) return nullptr;
    if (attached != nullptr) *attached = true;
    return env;
}

// What the sink needs to get back into Kotlin. Same thread, same call frame, so
// the JNIEnv here is the one that came in.
//
// PHASE 12, FIELD FAULT 3 — THERE IS NO `jclass` IN THIS STRUCT ANY MORE, and
// its absence is the fix. It used to hold the second parameter of
// `nativeChatStream`, and on 2026-08-25 that killed the Fold on the first
// streamed word of the first real conversation this app has ever had:
//
//   JNI DETECTED ERROR IN APPLICATION: jclass has wrong type:
//       com.ix64.hexy.mnn.IxMnnNative  ->  art::JavaVMExt::JniAbort
//
// `IxMnnNative` is a Kotlin `object`. Its `external fun`s are INSTANCE methods
// of that singleton — they are not `@JvmStatic` — so what JNI passes as the
// second argument is THE SINGLETON ITSELF, a `jobject`, and not the class. The
// old code declared it `jclass`, then called `GetStaticMethodID` on it. ART
// compared the types and aborted, and its message names the object it was
// handed: an INSTANCE OF IxMnnNative, where a Class was required.
//
// The class comes from [gNativeClass] now — found once by name, in JNI_OnLoad,
// and held as a GLOBAL reference. A local `jclass` is only valid inside the
// frame that produced it; a global is valid until it is deleted, on any thread.
struct JniSink {
    JNIEnv* env;
};

void jniEmit(void* ctx, const std::string& s) {
    auto* j = static_cast<JniSink*>(ctx);
    if (j == nullptr || j->env == nullptr) return;
    if (gNativeClass == nullptr || gOnChatToken == nullptr) return;
    if (j->env->ExceptionCheck()) return;
    jbyteArray arr = j->env->NewByteArray(static_cast<jsize>(s.size()));
    if (arr == nullptr) return;
    j->env->SetByteArrayRegion(arr, 0, static_cast<jsize>(s.size()),
                               reinterpret_cast<const jbyte*>(s.data()));
    j->env->CallStaticVoidMethod(gNativeClass, gOnChatToken, arr);
    j->env->DeleteLocalRef(arr);
    if (j->env->ExceptionCheck()) j->env->ExceptionClear();
}

}  // namespace

extern "C" {

// THE ONE PLACE A CLASS IS LOOKED UP, and it runs on the thread that loaded the
// library — which matters, because FindClass resolves through the CALLING
// thread's class loader. On a thread this library attached itself, that loader
// is the bootstrap one, which cannot see application classes; doing the lookup
// here, at load, is what makes the name resolve at all.
//
// The local reference FindClass returns is promoted to a GLOBAL immediately, on
// the next line, because a local is void the moment this frame returns.
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    gVm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        LOGE("JNI_OnLoad: no env at load — the token stream will be silent");
        return JNI_VERSION_1_6;
    }
    jclass local = env->FindClass(kNativeClassName);
    if (local == nullptr) {
        env->ExceptionClear();
        LOGE("JNI_OnLoad: %s not found", kNativeClassName);
        return JNI_VERSION_1_6;
    }
    gNativeClass = static_cast<jclass>(env->NewGlobalRef(local));
    env->DeleteLocalRef(local);
    if (gNativeClass == nullptr) {
        LOGE("JNI_OnLoad: could not hold %s globally", kNativeClassName);
        return JNI_VERSION_1_6;
    }
    // A method ID is not a reference: once taken off a class that is kept
    // alive, it stays valid for the life of that class.
    gOnChatToken = env->GetStaticMethodID(gNativeClass, "onChatToken", "([B)V");
    if (gOnChatToken == nullptr) {
        env->ExceptionClear();
        LOGE("JNI_OnLoad: IxMnnNative.onChatToken([B)V not found");
    }
    LOGI("JNI_OnLoad: %s cached (class=%p token=%p)", kNativeClassName,
         static_cast<void*>(gNativeClass), static_cast<void*>(gOnChatToken));
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void*) {
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return;
    if (gNativeClass != nullptr) env->DeleteGlobalRef(gNativeClass);
    gNativeClass = nullptr;
    gOnChatToken = nullptr;
    gVm = nullptr;
}

JNIEXPORT jlong JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbeddingCreate(JNIEnv* env, jobject, jstring configPath) {
    const std::string path = toStd(env, configPath);
    Embedding* e = nullptr;
    try {
        e = Embedding::createEmbedding(path, true);
    } catch (const std::exception& ex) {
        LOGE("embedding create threw: %s", ex.what());
        return 0;
    } catch (...) {
        LOGE("embedding create threw");
        return 0;
    }
    if (e == nullptr) {
        LOGE("embedding create returned null for %s", path.c_str());
        return 0;
    }
    LOGI("embedding loaded from %s, dim=%d", path.c_str(), e->dim());
    return reinterpret_cast<jlong>(e);
}

JNIEXPORT jint JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbeddingDim(JNIEnv*, jobject, jlong handle) {
    auto* e = reinterpret_cast<Embedding*>(handle);
    return e ? static_cast<jint>(e->dim()) : 0;
}

JNIEXPORT jfloatArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbed(JNIEnv* env, jobject, jlong handle, jstring text) {
    auto* e = reinterpret_cast<Embedding*>(handle);
    if (e == nullptr) return env->NewFloatArray(0);
    std::vector<float> out;
    try {
        auto var = e->txt_embedding(toStd(env, text));
        if (var == nullptr) {
            LOGE("txt_embedding returned null");
            return env->NewFloatArray(0);
        }
        auto info = var->getInfo();
        const float* p = var->readMap<float>();
        if (info == nullptr || p == nullptr) {
            LOGE("txt_embedding produced no readable map");
            return env->NewFloatArray(0);
        }
        out.assign(p, p + info->size);
    } catch (const std::exception& ex) {
        LOGE("embed threw: %s", ex.what());
        return env->NewFloatArray(0);
    } catch (...) {
        LOGE("embed threw");
        return env->NewFloatArray(0);
    }
    jfloatArray arr = env->NewFloatArray(static_cast<jsize>(out.size()));
    env->SetFloatArrayRegion(arr, 0, static_cast<jsize>(out.size()), out.data());
    return arr;
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbeddingRelease(JNIEnv*, jobject, jlong handle) {
    auto* e = reinterpret_cast<Embedding*>(handle);
    if (e) Llm::destroy(e);
}

JNIEXPORT jlong JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeLlmCreate(JNIEnv* env, jobject, jstring configPath) {
    const std::string path = toStd(env, configPath);
    Llm* llm = nullptr;
    try {
        llm = Llm::createLLM(path);
        // THE RETURN VALUE OF load() IS NOT DECORATION. Omni::load() answers
        // false when the VISUAL module is missing or will not build, and the
        // text half can come up perfectly well beside it — so a discarded false
        // here is a handle that loads, answers, and answers with nothing that
        // ever saw the picture. Phase 9.8: refuse the handle instead.
        if (llm && !llm->load()) {
            LOGE("llm load failed for %s — weights missing, corrupt, or too big for this phone",
                 path.c_str());
            Llm::destroy(llm);
            return 0;
        }
    } catch (const std::exception& ex) {
        LOGE("llm create threw: %s", ex.what());
        if (llm) Llm::destroy(llm);
        return 0;
    } catch (...) {
        LOGE("llm create threw");
        if (llm) Llm::destroy(llm);
        return 0;
    }
    if (llm == nullptr) {
        LOGE("llm create returned null for %s", path.c_str());
        return 0;
    }
    LOGI("llm loaded from %s", path.c_str());
    return reinterpret_cast<jlong>(llm);
}

JNIEXPORT jstring JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeChat(JNIEnv* env, jobject, jlong handle, jstring prompt,
                                              jint maxTokens) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (llm == nullptr) return env->NewStringUTF("");
    std::string reply;
    try {
        std::ostringstream os;
        // Fresh turn each call: v1 is stateless so a reply never depends on a
        // history the GDScript seam cannot see.
        llm->reset();
        llm->response(toStd(env, prompt), &os, nullptr, static_cast<int>(maxTokens));
        reply = stripThink(os.str());
    } catch (const std::exception& ex) {
        LOGE("chat threw: %s", ex.what());
        return env->NewStringUTF("");
    } catch (...) {
        LOGE("chat threw");
        return env->NewStringUTF("");
    }
    return env->NewStringUTF(reply.c_str());
}

// ------------------------------------------------------- the look (DELETED)
//
// PHASE 11b REMOVED THE VISION ROAD FROM THIS FILE. `nativeLook` took an
// absolute path to a JPEG and a question, built `<img>path</img>question`, and
// ran it through a separate Qwen2-VL session — the road MNN's own Android demo
// tests, arrived at in Phase 9.8 after the in-memory VARP road answered `?? ? ?`
// on the Fold for two reasons this comment used to spend forty lines on.
//
// It worked, in the end, and it was still the wrong thing: seconds per frame,
// 1.7 GB of weights, a six-gigabyte phone, and an answer that had to be steered
// into English and stripped of grounding tokens before anybody could hear it.
// The eyes are a MediaPipe object detector in ixbody now — 4.6 MB, inside the
// APK, twenty frames a second on a phone that could never hold the pack.
//
// WHAT WENT WITH IT: the only code in this app that ever read a camera frame
// off disk, and therefore the only reason one was ever written there.

// PHASE 9.8b — THE ANSWER COMES BACK AS BYTES, NOT AS A jstring.
//
// `NewStringUTF` wants MODIFIED UTF-8, which is not UTF-8: a NUL or any
// character above the BMP (emoji, rare CJK) is encoded differently and ART's
// answer to a malformed sequence is undefined — on some builds, one '?' per
// bad byte. The Fold's `288 chars back` rendering as `?? ?? ??` is exactly
// what that looks like from Godot, and it is indistinguishable from a model
// that really did emit rubbish. So the raw bytes cross unexamined and Kotlin
// decodes them with a real UTF-8 decoder; the two failure modes separate.
namespace {

jbyteArray toBytes(JNIEnv* env, const std::string& s) {
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(s.size()));
    if (arr != nullptr && !s.empty()) {
        env->SetByteArrayRegion(arr, 0, static_cast<jsize>(s.size()),
                                reinterpret_cast<const jbyte*>(s.data()));
    }
    return arr;
}

// THE FIRST BYTES, IN HEX. The one line that tells "the model emitted question
// marks" (3f 3f 3f) from "the model emitted Chinese and something downstream
// broke it" (e4 b8 ad ...) from "the model emitted nothing at all".
std::string headHex(const std::string& s, size_t n = 32) {
    static const char* kDigits = "0123456789abcdef";
    std::string out;
    const size_t take = s.size() < n ? s.size() : n;
    out.reserve(take * 3);
    for (size_t i = 0; i < take; ++i) {
        const auto b = static_cast<unsigned char>(s[i]);
        out += kDigits[b >> 4];
        out += kDigits[b & 0xF];
        out += ' ';
    }
    return out;
}

}  // namespace

// PHASE 10c — THE SAME TURN, SAID AS IT IS THOUGHT.
//
// Identical to nativeChat above in everything but the ostream: this one has a
// TokenStream under it, so every token reaches Kotlin (and a Godot signal, and
// the stage, and the loudspeaker) at the moment MNN produces it instead of at
// the moment the whole answer is finished. The return value is what was
// streamed, byte for byte.
JNIEXPORT jbyteArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeChatStream(JNIEnv* env, jobject, jlong handle,
                                                    jstring prompt, jint maxTokens) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (llm == nullptr) return toBytes(env, "");
    // THE SECOND PARAMETER IS DELIBERATELY UNNAMED AND DELIBERATELY `jobject`.
    // It is the IxMnnNative singleton, because these are instance methods of a
    // Kotlin `object`; calling GetStaticMethodID on it is what aborted the Fold.
    // The class and the method come from the cache, which JNI_OnLoad built.
    JniSink sink{env};
    if (gOnChatToken == nullptr) {
        LOGE("chat stream: IxMnnNative.onChatToken was never cached — "
             "the answer will arrive whole instead of streamed");
    }
    std::string reply;
    try {
        TokenStream buf(&jniEmit, &sink);
        std::ostream os(&buf);
        llm->reset();
        llm->response(toStd(env, prompt), &os, nullptr, static_cast<int>(maxTokens));
        os.flush();
        buf.finish();
        reply = buf.text();
        LOGI("chat stream: %d bytes; head: %s",
             static_cast<int>(reply.size()), headHex(reply).c_str());
    } catch (const std::exception& ex) {
        LOGE("chat stream threw: %s", ex.what());
        return toBytes(env, "");
    } catch (...) {
        LOGE("chat stream threw");
        return toBytes(env, "");
    }
    return toBytes(env, reply);
}


JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeLlmRelease(JNIEnv*, jobject, jlong handle) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (llm) Llm::destroy(llm);
}


JNIEXPORT jboolean JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeSetHexPrior(JNIEnv*, jobject, jlong handle, jint hexBits, jfloat beta) {
    if (hexBits < 0 || hexBits > 63) {
        return JNI_FALSE;
    }
    ix64::gdl::setActiveHexPrior(static_cast<uint8_t>(hexBits), static_cast<float>(beta));
    return JNI_TRUE;
}

}  // extern "C"
