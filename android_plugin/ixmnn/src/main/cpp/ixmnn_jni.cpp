// ixmnn_jni.cpp — JNI Bridge for Alibaba MNN LLM (Qwen) and Embeddings (GTE).

#include <jni.h>
#include <android/log.h>

#include <sstream>
#include <streambuf>
#include <string>
#include <vector>

#include <algorithm>
#include <mutex>
#include <atomic>

#include <MNN/expr/Expr.hpp>
#include <MNN/expr/ExprCreator.hpp>
#include <llm/llm.hpp>

#include "q6/q6.hpp"

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

std::string stripThink(const std::string& s) {
    const std::string open = "<think>", close = "</think>";
    auto b = s.find(open);
    auto e = s.find(close);
    std::string out;
    if (e == std::string::npos) {
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

class TokenStream : public std::streambuf {
public:
    using Callback = void (*)(const char*, size_t, void*);
    TokenStream(Callback cb, void* user) : cb_(cb), user_(user) {}

    const std::string& text() const { return full_; }

    void finish() {
        if (!hold_.empty()) {
            if (cb_) cb_(hold_.data(), hold_.size(), user_);
            full_.append(hold_);
            hold_.clear();
        }
    }

protected:
    int_type overflow(int_type ch) override {
        if (ch != traits_type::eof()) {
            char c = static_cast<char>(ch);
            xsputn(&c, 1);
        }
        return ch;
    }

    std::streamsize xsputn(const char* s, std::streamsize count) override {
        if (count <= 0) return 0;
        hold_.append(s, static_cast<size_t>(count));
        _drain(false);
        return count;
    }

private:
    void _drain(bool flushAll) {
        while (!hold_.empty()) {
            if (inThink_) {
                auto close = hold_.find("</think>");
                if (close != std::string::npos) {
                    hold_.erase(0, close + 8);
                    inThink_ = false;
                    continue;
                }
                hold_.clear();
                return;
            }

            auto open = hold_.find("<think>");
            if (open != std::string::npos) {
                if (open > 0) {
                    _emitSafe(hold_.substr(0, open));
                }
                hold_.erase(0, open + 7);
                inThink_ = true;
                continue;
            }

            if (!flushAll && hold_.size() < 7 && std::string("<think>").rfind(hold_, 0) == 0) {
                return;
            }

            _emitSafe(hold_);
            hold_.clear();
        }
    }

    void _emitSafe(const std::string& text) {
        if (text.empty()) return;
        if (cb_) cb_(text.data(), text.size(), user_);
        full_.append(text);
    }

    Callback cb_;
    void* user_;
    std::string hold_;
    std::string full_;
    bool inThink_ = false;
};

// --- THE CUBE, AND THE PRIOR IT IS -----------------------------------------
//
// ONE Q6 lives here, beside the Qwen decode loop and the MNN runtime, and it is
// the same state Godot moves through q6_step: the mass over the 64 hexagrams
// that chooses which line of the BODY figure turns. Three readers, one state.
//
// THE PRIOR. Godot hands down 64 ASCII figure words indexed by hexagram bits
// (the King Wen pinyin out of scripts/core/iching/king_wen.gd, so this file
// keeps no second copy of a table that would then be free to drift). The first
// time a decode runs, each word is tokenized once and its FIRST token id kept.
// Every token after that, the logit of each of those 64 ids gets
//
//     logits[id] += weight * p[h] * 64
//
// so a cube that has made up its mind pushes its own word by weight * 64, and a
// cube with nothing to say (uniform, p[h] = 1/64) pushes all 64 words by
// exactly `weight`, which is the same for every one of them and therefore
// changes no ranking at all. The prior LEANS; it never decides.
//
// AT WEIGHT 0 NOTHING IS TOUCHED and the old path runs: MNN's own
// Llm::response(), byte for byte the behaviour before this file grew a cube.
std::mutex gQ6Mutex;
ix64::q6::Q6 gQ6;
double gPriorWeight = 0.0;
std::vector<std::string> gFigureWords;  // indexed by hexagram bits, 0..63
std::vector<int> gFigureTokens;         // first token id per figure, or -1
bool gFigureTokensReady = false;

// HOW OFTEN A CHAT ASKED FOR A VERSION THE CUBE DID NOT HAVE. Counted, logged,
// and never acted on: see staleAgainst() in q6/q6.hpp. Atomic because the
// decode loop bumps it on the worker thread while Godot reads it on its own.
std::atomic<int> gPriorMismatches{0};

void resetFigureTokens() {
    gFigureTokens.clear();
    gFigureTokensReady = false;
}

// Tokenize the 64 figure words once, against the LLM that will decode them.
void ensureFigureTokens(Llm* llm) {
    if (gFigureTokensReady || llm == nullptr) return;
    gFigureTokens.assign(ix64::q6::kStates, -1);
    for (int h = 0; h < ix64::q6::kStates && h < static_cast<int>(gFigureWords.size()); ++h) {
        const std::string& w = gFigureWords[static_cast<size_t>(h)];
        if (w.empty()) continue;
        try {
            // A leading space is what a word in the MIDDLE of a sentence looks
            // like to a BPE tokenizer. Without it the id kept would be the one
            // that only ever starts a line.
            std::vector<int> ids = llm->tokenizer_encode(" " + w);
            if (!ids.empty()) gFigureTokens[static_cast<size_t>(h)] = ids.front();
        } catch (...) {
        }
    }
    gFigureTokensReady = true;
}

// Add the cube's lean to one step's logits, in place.
void applyPrior(MNN::Express::VARP logits) {
    if (gPriorWeight == 0.0 || !gFigureTokensReady || logits.get() == nullptr) return;
    auto info = logits->getInfo();
    if (info == nullptr || info->size <= 0 || info->dim.empty()) return;
    const int vocab = info->dim.back();
    if (vocab <= 0 || vocab > static_cast<int>(info->size)) return;
    // Only the LAST row matters: that is the distribution over the next token.
    const int base = static_cast<int>(info->size) - vocab;
    auto* p = const_cast<float*>(logits->readMap<float>());
    if (p == nullptr) return;
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    for (int h = 0; h < ix64::q6::kStates && h < static_cast<int>(gFigureTokens.size()); ++h) {
        const int id = gFigureTokens[static_cast<size_t>(h)];
        if (id < 0 || id >= vocab) continue;
        p[base + id] += static_cast<float>(ix64::q6::priorLogit(gQ6, h, gPriorWeight));
    }
}

// THE DECODE LOOP, OPENED UP.
//
// MNN's Llm::response() runs prefill, sampling and the stop check behind one
// call with no hook in the middle -- llm.hpp exposes no logit processor and no
// sampler callback -- so when the prior is on we run those same three steps
// ourselves out of the PUBLIC api (forward / sample / tokenizer_decode) and add
// the cube's lean to the logits in the one place it belongs: between forward
// and sample. Everything else stays MNN's -- its module, its KV cache, its
// sampler, its tokenizer, its stop tokens.
//
// Returns false if anything at all goes wrong, and the caller falls back to
// Llm::response(). A cube that cannot lean must never cost the user an answer.
bool generateWithPrior(Llm* llm, const std::string& prompt, int maxTokens, std::ostream* os,
                       int expectVersion) {
    if (llm == nullptr || os == nullptr) return false;
    if (gPriorWeight == 0.0) return false;  // weight 0 is the old path, exactly
    {
        // A STALE CUBE IS REPORTED, NOT REFUSED. If the chat was opened against
        // one cast and the cube has since been re-stamped by another, say so in
        // the log, count it, and lean anyway -- the answer is still the user's.
        std::lock_guard<std::mutex> lock(gQ6Mutex);
        const int have = gQ6.version();
        if (ix64::q6::staleAgainst(expectVersion, have)) {
            gPriorMismatches.fetch_add(1);
            LOGE("q6 prior stale: chat expects v%d, cube has v%d", expectVersion, have);
        }
    }
    try {
        ensureFigureTokens(llm);
        llm->reset();
        std::vector<int> ids = llm->tokenizer_encode(llm->apply_chat_template(prompt));
        if (ids.empty()) return false;
        llm->generate_init(os, nullptr);
        MNN::Express::VARP logits = llm->forward(ids, true);
        const int cap = maxTokens > 0 ? maxTokens : 1;
        for (int n = 0; n < cap; ++n) {
            if (logits.get() == nullptr) return n > 0;
            applyPrior(logits);
            const int token = llm->sample(logits, 0, 0);
            if (llm->is_stop(token)) break;
            *os << llm->tokenizer_decode(token);
            logits = llm->forward(std::vector<int>{token}, false);
        }
        os->flush();
        return true;
    } catch (...) {
        return false;
    }
}

jbyteArray toBytes(JNIEnv* env, const std::string& s) {
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(s.size()));
    if (arr != nullptr && !s.empty()) {
        env->SetByteArrayRegion(arr, 0, static_cast<jsize>(s.size()),
                                reinterpret_cast<const jbyte*>(s.data()));
    }
    return arr;
}

jclass gIxMnnNativeClass = nullptr;
jmethodID gOnChatToken = nullptr;

struct JniSink {
    JNIEnv* env;
};

void jniEmit(const char* bytes, size_t count, void* user) {
    auto* sink = reinterpret_cast<JniSink*>(user);
    if (!sink || !sink->env || !gIxMnnNativeClass || !gOnChatToken) return;
    jbyteArray arr = sink->env->NewByteArray(static_cast<jsize>(count));
    if (!arr) return;
    sink->env->SetByteArrayRegion(arr, 0, static_cast<jsize>(count),
                                  reinterpret_cast<const jbyte*>(bytes));
    sink->env->CallStaticVoidMethod(gIxMnnNativeClass, gOnChatToken, arr);
    sink->env->DeleteLocalRef(arr);
}

}  // namespace

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }
    jclass local = env->FindClass("com/ix64/hexy/mnn/IxMnnNative");
    if (!local) return JNI_ERR;
    gIxMnnNativeClass = reinterpret_cast<jclass>(env->NewGlobalRef(local));
    env->DeleteLocalRef(local);
    gOnChatToken = env->GetStaticMethodID(gIxMnnNativeClass, "onChatToken", "([B)V");
    if (!gOnChatToken) return JNI_ERR;
    return JNI_VERSION_1_6;
}

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbeddingCreate(JNIEnv* env, jobject, jstring configPath) {
    const std::string path = toStd(env, configPath);
    try {
        auto* e = Embedding::createEmbedding(path);
        return reinterpret_cast<jlong>(e);
    } catch (...) {
        return 0;
    }
}

JNIEXPORT jint JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbeddingDim(JNIEnv*, jobject, jlong handle) {
    auto* e = reinterpret_cast<Embedding*>(handle);
    return e ? static_cast<jint>(e->dim()) : 0;
}

JNIEXPORT jfloatArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbed(JNIEnv* env, jobject, jlong handle, jstring text) {
    auto* e = reinterpret_cast<Embedding*>(handle);
    if (!e) return env->NewFloatArray(0);
    std::vector<float> out;
    try {
        auto var = e->txt_embedding(toStd(env, text));
        if (var.get()) {
            auto info = var->getInfo();
            if (info && info->size > 0) {
                out.resize(info->size);
                auto* ptr = var->readMap<float>();
                if (ptr) {
                    std::copy(ptr, ptr + info->size, out.begin());
                }
            }
        }
    } catch (...) {}
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
    try {
        resetFigureTokens();
        auto* llm = Llm::createLLM(path);
        if (llm && !llm->load()) {
            Llm::destroy(llm);
            return 0;
        }
        return reinterpret_cast<jlong>(llm);
    } catch (...) {
        return 0;
    }
}

JNIEXPORT jstring JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeChat(JNIEnv* env, jobject, jlong handle, jstring prompt, jint maxTokens, jint expectVersion) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return env->NewStringUTF("");
    try {
        std::ostringstream os;
        const std::string text = toStd(env, prompt);
        if (!generateWithPrior(llm, text, static_cast<int>(maxTokens), &os,
                               static_cast<int>(expectVersion))) {
            os.str(std::string());
            llm->reset();
            llm->response(text, &os, nullptr, static_cast<int>(maxTokens));
        }
        std::string reply = stripThink(os.str());
        return env->NewStringUTF(reply.c_str());
    } catch (...) {
        return env->NewStringUTF("");
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeChatStream(JNIEnv* env, jobject, jlong handle, jstring prompt, jint maxTokens, jint expectVersion) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return toBytes(env, "");
    JniSink sink{env};
    try {
        TokenStream buf(&jniEmit, &sink);
        std::ostream os(&buf);
        const std::string text = toStd(env, prompt);
        if (!generateWithPrior(llm, text, static_cast<int>(maxTokens), &os,
                               static_cast<int>(expectVersion))) {
            llm->reset();
            llm->response(text, &os, nullptr, static_cast<int>(maxTokens));
        }
        os.flush();
        buf.finish();
        return toBytes(env, buf.text());
    } catch (...) {
        return toBytes(env, "");
    }
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeLlmRelease(JNIEnv*, jobject, jlong handle) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (llm) Llm::destroy(llm);
}


// --- THE ENGINE SURFACE -----------------------------------------------------
//
// MNN's `llm.hpp` handed through, nothing more. Every one of these needs a
// loaded Llm and nothing else -- no model file is opened, no decode runs -- and
// every one answers a safe empty on a null handle or a throw, because a seam
// that has to branch on "did the engine survive" is a seam that will forget to.

JNIEXPORT jintArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeTokenize(JNIEnv* env, jobject, jlong handle, jstring text) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    std::vector<int> ids;
    if (llm) {
        try {
            ids = llm->tokenizer_encode(toStd(env, text));
        } catch (...) {
            ids.clear();
        }
    }
    jintArray arr = env->NewIntArray(static_cast<jsize>(ids.size()));
    if (!ids.empty()) {
        env->SetIntArrayRegion(arr, 0, static_cast<jsize>(ids.size()),
                               reinterpret_cast<const jint*>(ids.data()));
    }
    return arr;
}

JNIEXPORT jstring JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeDetokenize(JNIEnv* env, jobject, jlong handle, jint tokenId) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return env->NewStringUTF("");
    try {
        return env->NewStringUTF(llm->tokenizer_decode(static_cast<int>(tokenId)).c_str());
    } catch (...) {
        return env->NewStringUTF("");
    }
}

JNIEXPORT jstring JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeGetPerf(JNIEnv* env, jobject, jlong handle) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return env->NewStringUTF("{}");
    try {
        const auto* ctx = llm->getContext();
        if (!ctx) return env->NewStringUTF("{}");
        std::ostringstream os;
        os << "{\"prompt_len\":" << ctx->prompt_len
           << ",\"gen_seq_len\":" << ctx->gen_seq_len
           << ",\"all_seq_len\":" << ctx->all_seq_len
           << ",\"prefill_us\":" << static_cast<long long>(ctx->prefill_us)
           << ",\"decode_us\":" << static_cast<long long>(ctx->decode_us)
           << ",\"status\":" << static_cast<int>(ctx->status)
           << "}";
        return env->NewStringUTF(os.str().c_str());
    } catch (...) {
        return env->NewStringUTF("{}");
    }
}

JNIEXPORT jboolean JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeSetSampling(JNIEnv*, jobject, jlong handle,
                                                     jfloat temperature, jfloat topP,
                                                     jfloat repetitionPenalty) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return JNI_FALSE;
    try {
        std::ostringstream os;
        os << "{\"sampler_type\":\"mixed\",\"temperature\":" << temperature
           << ",\"topP\":" << topP
           << ",\"penalty\":" << repetitionPenalty << "}";
        return llm->set_config(os.str()) ? JNI_TRUE : JNI_FALSE;
    } catch (...) {
        return JNI_FALSE;
    }
}

JNIEXPORT jint JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeHistoryCount(JNIEnv*, jobject, jlong handle) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return 0;
    try {
        return static_cast<jint>(llm->getCurrentHistory());
    } catch (...) {
        return 0;
    }
}

JNIEXPORT jboolean JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEraseHistory(JNIEnv*, jobject, jlong handle,
                                                      jint begin, jint end) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm || begin < 0 || end < begin) return JNI_FALSE;
    try {
        llm->eraseHistory(static_cast<size_t>(begin), static_cast<size_t>(end));
        return JNI_TRUE;
    } catch (...) {
        return JNI_FALSE;
    }
}

JNIEXPORT jstring JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeApplyTemplate(JNIEnv* env, jobject, jlong handle, jstring prompt) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return env->NewStringUTF("");
    try {
        return env->NewStringUTF(llm->apply_chat_template(toStd(env, prompt)).c_str());
    } catch (...) {
        return env->NewStringUTF("");
    }
}


// --- Q6: THE SIX-BIT CUBE ---------------------------------------------------
//
// The same state the decode loop reads as a prior, moved from Godot. All of it
// is arithmetic over 64 doubles, so none of it needs a loaded model; the mutex
// is only there because the decode loop reads it on the worker thread while
// Godot writes it from its own.

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Reset(JNIEnv*, jobject, jint bits) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    gQ6.reset(static_cast<int>(bits));
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Inject(JNIEnv*, jobject, jint bits) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    gQ6.inject(static_cast<int>(bits));
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Uniform(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    gQ6.uniform();
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Anchor(JNIEnv*, jobject, jint bits, jfloat amount) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    gQ6.anchor(static_cast<int>(bits), static_cast<double>(amount));
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Step(JNIEnv* env, jobject, jfloatArray bias,
                                                jfloat t, jfloat beta) {
    double b[ix64::q6::kLines] = {0, 0, 0, 0, 0, 0};
    if (bias != nullptr) {
        const jsize n = std::min<jsize>(env->GetArrayLength(bias), ix64::q6::kLines);
        if (n > 0) {
            std::vector<jfloat> tmp(static_cast<size_t>(n));
            env->GetFloatArrayRegion(bias, 0, n, tmp.data());
            for (jsize i = 0; i < n; ++i) {
                b[i] = static_cast<double>(tmp[static_cast<size_t>(i)]);
            }
        }
    }
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    gQ6.step(b, static_cast<double>(t), static_cast<double>(beta));
}

JNIEXPORT jfloatArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6State(JNIEnv* env, jobject) {
    float out[ix64::q6::kStates];
    {
        std::lock_guard<std::mutex> lock(gQ6Mutex);
        for (int h = 0; h < ix64::q6::kStates; ++h) out[h] = static_cast<float>(gQ6.p[h]);
    }
    jfloatArray arr = env->NewFloatArray(ix64::q6::kStates);
    if (arr) env->SetFloatArrayRegion(arr, 0, ix64::q6::kStates, out);
    return arr;
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6SetState(JNIEnv* env, jobject, jfloatArray state) {
    if (state == nullptr) return;
    if (env->GetArrayLength(state) != ix64::q6::kStates) return;
    std::vector<jfloat> tmp(ix64::q6::kStates);
    env->GetFloatArrayRegion(state, 0, ix64::q6::kStates, tmp.data());
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    for (int h = 0; h < ix64::q6::kStates; ++h) {
        gQ6.p[h] = static_cast<double>(tmp[static_cast<size_t>(h)]);
    }
}

JNIEXPORT jint JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Argmax(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    return static_cast<jint>(gQ6.argmax());
}

JNIEXPORT jfloat JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Tension(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    return static_cast<jfloat>(gQ6.tension());
}

JNIEXPORT jint JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6BestNeighbour(JNIEnv*, jobject, jint bits) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    return static_cast<jint>(gQ6.bestNeighbour(static_cast<int>(bits)));
}

JNIEXPORT jfloatArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6Embed(JNIEnv* env, jobject) {
    float out[ix64::q6::kEmbedDim];
    {
        std::lock_guard<std::mutex> lock(gQ6Mutex);
        gQ6.embed(out);
    }
    jfloatArray arr = env->NewFloatArray(ix64::q6::kEmbedDim);
    if (arr) env->SetFloatArrayRegion(arr, 0, ix64::q6::kEmbedDim, out);
    return arr;
}

JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6SetPriorWeight(JNIEnv*, jobject, jfloat w) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    gPriorWeight = static_cast<double>(w);
}

JNIEXPORT jfloat JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6PriorWeight(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    return static_cast<jfloat>(gPriorWeight);
}

// The 64 figure words, indexed by hexagram bits, handed down from
// scripts/core/iching/king_wen.gd. Setting them drops any token ids cached
// against the old list.
JNIEXPORT void JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6SetFigureWords(JNIEnv* env, jobject,
                                                          jobjectArray words,
                                                          jint version) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    gFigureWords.assign(ix64::q6::kStates, std::string());
    if (words != nullptr) {
        const jsize n = std::min<jsize>(env->GetArrayLength(words), ix64::q6::kStates);
        for (jsize i = 0; i < n; ++i) {
            auto s = reinterpret_cast<jstring>(env->GetObjectArrayElement(words, i));
            gFigureWords[static_cast<size_t>(i)] = toStd(env, s);
            if (s) env->DeleteLocalRef(s);
        }
    }
    gQ6.setVersion(static_cast<int>(version));
    resetFigureTokens();
}

// How many times a chat has declared a version the cube did not have. Never
// resets on its own; it is a counter for the dashboard, not a gate.
JNIEXPORT jint JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6PriorMismatches(JNIEnv*, jobject) {
    return static_cast<jint>(gPriorMismatches.load());
}

// The version stamped on the cube's current figure-word push, or -1 if none.
JNIEXPORT jint JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeQ6FigureVersion(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(gQ6Mutex);
    return static_cast<jint>(gQ6.version());
}

} // extern "C"
