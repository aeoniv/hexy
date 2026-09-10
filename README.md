# Hexy: Minimal MNN + Qwen + I-Ching Experiment

An on-device mobile experiment combining **Alibaba MNN**, **Qwen LLM**, and the **I-Ching** in Godot 4.7 Forward Mobile for Android.

## Architecture

This experiment integrates three core components:

1. **I-Ching Cybernetic System**:
   - **64-Hexagram King Wen System**: Maps hexagrams to geometric balance states.
   - **3D Tensegrity Ball Creature** (`scripts/creature_ball_3d.gd`): An icosahedral tensegrity structure (6 struts, 24 elastic cords). The 6 struts represent the 6 hexagram lines, dynamically mutating color and pulsating on moving lines.
   - **Radial Mandala Dial** (`scripts/mandala_dial_2d.gd`): 64-hexagram touch-draggable radial dial with snap-to-closest and haptic feedback.

2. **Alibaba MNN Hardware Bridge**:
   - **Native JNI/NDK Bridge** (`android_plugin/ixmnn`): Direct C++ bindings to Alibaba MNN (`llm.hpp`).
   - **Local Inference**: Runs quantized Qwen (0.6B) and GTE multilingual sentence embeddings on device silicon (Mali-G57 MC2 GPU / NPU).
   - **MnnRuntime** (`scripts/brain/mnn_runtime.gd`): GDScript interface for chat and embedding generation.

3. **Mobile Interface**:
   - **Cast Oracle**: Yarrow stalks / 3-coins probability algorithm generating hexagrams and changing lines.
   - **Ask MNN**: Queries the on-device Qwen model for hexagram interpretation and guidance.
   - **Telemetry**: Real-time GPU FPS, gravity vector, and JNI bridge status.

## Target Hardware
- Tested on: **Samsung Galaxy A22** (`SM-A226B`)
- GPU: ARM Mali-G57 MC2 (Vulkan 1.1 / Forward Mobile)
- Frame Rate: 75–90 FPS
