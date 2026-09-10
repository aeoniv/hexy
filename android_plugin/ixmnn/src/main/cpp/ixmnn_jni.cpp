// ixmnn_jni.cpp — JNI Bridge for Alibaba MNN LLM (Qwen) and Embeddings (GTE).

#include <jni.h>
#include <android/log.h>

#include <sstream>
#include <streambuf>
#include <string>
#include <vector>

#include <MNN/expr/Expr.hpp>
#include <MNN/expr/ExprCreator.hpp>
#include <llm/llm.hpp>

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
    return e ? static_cast<jint>(e->getDimension()) : 0;
}

JNIEXPORT jfloatArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeEmbed(JNIEnv* env, jobject, jlong handle, jstring text) {
    auto* e = reinterpret_cast<Embedding*>(handle);
    if (!e) return env->NewFloatArray(0);
    std::vector<float> out;
    try {
        auto var = e->embedding(toStd(env, text));
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
Java_com_ix64_hexy_mnn_IxMnnNative_nativeChat(JNIEnv* env, jobject, jlong handle, jstring prompt, jint maxTokens) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return env->NewStringUTF("");
    try {
        std::ostringstream os;
        llm->reset();
        llm->response(toStd(env, prompt), &os, nullptr, static_cast<int>(maxTokens));
        std::string reply = stripThink(os.str());
        return env->NewStringUTF(reply.c_str());
    } catch (...) {
        return env->NewStringUTF("");
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_ix64_hexy_mnn_IxMnnNative_nativeChatStream(JNIEnv* env, jobject, jlong handle, jstring prompt, jint maxTokens) {
    auto* llm = reinterpret_cast<Llm*>(handle);
    if (!llm) return toBytes(env, "");
    JniSink sink{env};
    try {
        TokenStream buf(&jniEmit, &sink);
        std::ostream os(&buf);
        llm->reset();
        llm->response(toStd(env, prompt), &os, nullptr, static_cast<int>(maxTokens));
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

} // extern "C"
