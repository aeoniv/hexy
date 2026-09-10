# Hexy: Minimal MNN + Qwen + I-Ching Experiment

An on-device mobile experiment combining **Alibaba MNN**, **Qwen LLM**, and the **I-Ching** in Godot 4.7 Forward Mobile for Android.

## Overview

This repository is strictly scoped to three core pillars:

1. **Alibaba MNN Engine**:
   - Native C++ JNI bridge (ndroid_plugin/ixmnn) directly hosting Alibaba MNN (llm.hpp).
   - Runs on-device quantized Qwen LLM for chat completions and GTE sentence embeddings.
   - Zero cloud dependencies — pure local silicon inference.

2. **Qwen LLM**:
   - On-device philosophical counsel and interpretation.
   - Real-time token streaming via JNI callbacks into Godot.

3. **I-Ching Oracle**:
   - 64 King Wen hexagrams lookup with trigrams and judgments.
   - Authentic 3-coins probability casting (generating static and moving lines).
   - Dynamic 6-line visualization (solid Yang and divided Yin lines, moving line mutations).

## Hardware Target
- Tested on: **Samsung Galaxy A22** (SM-A226B)
- Engine: Godot 4.7 Forward Mobile
