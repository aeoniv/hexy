# android_plugin — ixmnn

Android plugin hosting the Alibaba MNN runtime for Godot 4.7.

## Modules
- `ixmnn`: Native C++ JNI bridge hosting Alibaba MNN (`llm.hpp`) for on-device Qwen inference and GTE embeddings.

## Requirements
- Android NDK 27.0.12077973
- CMake 3.22.1
- MNN 3.6.1 prebuilt binaries in `libs/mnn-jni/`
