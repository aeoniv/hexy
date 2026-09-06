# android_plugin — ixloc + ixmesh + ixmnn + ixbody

Four Godot Android plugins, same layout as `ix64-avatar/android_plugin`.

| Plugin | Wraps | Status |
|---|---|---|
| `ixloc` | FusedLocationProvider + rotation-vector sensor | on device: fine location held on API 33 and 34, duty-cycled accuracy, live magnetic heading. A placeable (< 50 m) fix indoors: not yet |
| `ixmesh` | Google Nearby Connections (P2P_CLUSTER) | on device: singleton registers, advertising + discovery start. Two-device meshing still unverified |
| `ixmnn` | Alibaba MNN runtime (LLM engine) | on device: real `embed()` and real `chat()` through a JNI bridge this repo owns — see *MNN sessions* below |
| `ixbody` | CameraX + MediaPipe FaceLandmarker | on device: the front camera bound and unbound on a 1.5 s in 30 s duty cycle, six inferences a window, honest `away` readings. A `watching` reading from a real face: not yet |

## Drop-ins required before the first build (both gitignored)

1. `libs/godot-lib.template_release.aar` — extract from the Godot 4.7.1 export
   templates with `libs/extract-godot-lib.ps1`, or copy the one
   `ix64-avatar/android_plugin/libs/` already has. ~100 MB, `compileOnly`.
2. `libs/mnn-jni/{arm64-v8a,armeabi-v7a}/*.so` — **MNN ships no AAR and no
   Maven artifact.** Every `mnn_<ver>_android_*` asset on
   https://github.com/alibaba/MNN/releases (checked through 3.6.1) is a zip of
   bare `.so` files: `libMNN.so`, `libMNN_CL.so`, `libMNN_Vulkan.so`,
   `libMNN_Express.so`, `libMNNAudio.so`, `libMNNOpenCV.so`, `libllm.so`,
   `libmnncore.so`, `libc++_shared.so`. So `ixmnn` takes them as loose jniLibs
   instead of a dependency:

   ```
   curl -L -o mnn.zip https://github.com/alibaba/MNN/releases/download/3.6.1/mnn_3.6.1_android_armv7_armv8_cpu_opencl_vulkan.zip
   unzip mnn.zip
   mkdir -p libs/mnn-jni
   cp -r mnn_3.6.1_android_*/arm64-v8a mnn_3.6.1_android_*/armeabi-v7a libs/mnn-jni/
   ```

   `libc++_shared.so` must sit beside the rest or nothing loads.

`local.properties` (also gitignored) needs `sdk.dir` pointing at the Android
SDK. `JAVA_HOME` must be a JDK 17+ — Android Studio's bundled
`jbr` works. `ixmnn` also compiles C++, so the SDK needs **NDK 27.0.12077973**
(AGP 8.7's default) and **CMake 3.22.1**:

```
sdkmanager "ndk;27.0.12077973" "cmake;3.22.1"
```

## MNN sessions — why this repo owns a JNI file

The release zips ship `libmnncore.so`, and it is tempting to think that is the
Java bridge. It is not the one we need: its only exports are
`Java_com_taobao_android_mnn_MNNNetNative_*`, the old Interpreter/Session
wrapper. It knows nothing about tokenizers, chat templates, or KV cache, so
using it would mean writing a tokenizer in Kotlin and a pooling strategy by
hand. `libllm.so` — the `transformers/llm` engine, which *does* know all of
that — exports the full C++ `MNN::Transformer::{Llm,Embedding}` API and **zero
JNI symbols**. MNN's own Android chat app builds its own JNI on top of
`llm.hpp`; so do we, minimally:

- `ixmnn/src/main/cpp/ixmnn_jni.cpp` — ~7 entry points, no logic beyond
  marshalling and swallowing exceptions at the boundary.
- `ixmnn/src/main/cpp/include/` — MNN's public headers vendored at tag **3.6.1**,
  the same version as the prebuilt `.so` files. Bumping the `.so` files means
  re-vendoring these from the matching tag.
- Built with `ANDROID_STL=c++_shared` (MNN's prebuilts use it; a different STL
  changes `std::string`'s layout across the boundary) and
  `jniLibs.pickFirsts += **/libc++_shared.so`, since that library arrives both
  from MNN's zip and from the NDK.

`System.loadLibrary("ixmnnjni")` pulls in `libllm`, `libMNN_Express` and
`libMNN` as dependencies, so it is the single load that `runtime_ready()` does.

MNN's `Executor` is thread-local and `Llm` is not reentrant, so `IxMnn.kt`
serialises every native call onto one dedicated worker thread and blocks the
Godot caller on the result. GDScript keeps the loads off the main thread
itself (`scripts/main.gd` wakes the mind on a `Thread`).

### Models

Models never ride in the APK. `embed_start(dir)` / `chat_start(dir)` resolve
`dir` against the app's external files dir and expect MNN's `config.json`
there:

```
/storage/emulated/0/Android/data/app.ix64.hexy/files/<dir>/config.json
```

`tools/push_mnn_model.ps1` puts them there; re-run it after every reinstall,
because that directory dies with the install. Missing model → `start` returns
false/0 and the seam stays honest (`backend=mock` on desktop, empty vector on
device).

| Role | Model | Notes |
|---|---|---|
| embed | `taobao-mnn/gte_sentence-embedding_multilingual-base-MNN` | 768-dim, ~450 MB. MNN's `Embedding` class loads a module with output `sentence_embeddings`, which BERT-style exports have and the `Qwen3-Embedding-*-MNN` exports do not — those will not load through this API. |
| chat | `taobao-mnn/Qwen3-0.6B-MNN` | int4, ~450 MB of weights. Chosen because it fits the A22's 4 GB; `Qwen3-1.7B-MNN` (1.2 GB) is untried — the Fold 4 has the RAM for it but nothing here has proven that yet. |
| chat | `taobao-mnn/Qwen3.5-0.8B-MNN` | int4, ~548 MB pushed (`llm.mnn.weight` 470 MB + `visual.*` 63 MB + a 5.3 MB `llm.mnn.json` the 0.6B has no equivalent of — push all of them or it will not load). MULTIMODAL: one directory is both mouth and eyes, so once it is smoked on device it can retire the 1.71 GB Qwen2-VL pack for Phase 9 vision. Runs on the pinned MNN 3.6.1 as-is (hybrid attention since 3.4.1). Directory `qwen3.5-0.8b-mnn`; `-Model chat35` pushes it. |

`<think>...</think>` is stripped in the JNI layer — Hexy speaks one line, and
the reasoning is not the line. Qwen3's own `/no_think` switch is appended in
`mnn_runtime.gd`, next to the model name, because without it the whole token
budget goes into reasoning and no answer ever arrives.

Qwen3.5 does not have that switch and must not be sent it — `/no_think` there
is a sentence the model reads, not a command. It decides by
`jinja.context.enable_thinking` in its own `llm_config.json` (shipped `true`)
and by the `<think>` tags the seam already separates, so the gate in
`mnn_runtime.gd` is `qwen3-`, with the dash, and `qwen3.5-*` falls outside it.

The embed row does not move with the chat row. `gte` stays because MNN's
`Embedding` class loads a module whose output is named `sentence_embeddings`
and the `Qwen3-Embedding-*-MNN` exports do not have one.

### DEVICE — 2026-08-17

Both phones, fresh install, models pushed, `hexy-debug.apk`:

```
Fold 4 (RFCT71BW9YV, API 34)
  IxMnnNative: embedding loaded from .../gte-embedding-mnn/config.json, dim=768
  godot: mnn embed: dim=768 got=768 head=[-0.0723876953125, 0.05960083007812, ...]
  IxMnnNative: llm loaded from .../qwen3-0.6b-mnn/config.json
  godot: mnn chat: **Hello!**

A22 (R9WT200BA8F, API 33, 4 GB RAM)
  IxMnnNative: embedding loaded from .../gte-embedding-mnn/config.json, dim=768
  godot: mnn embed: dim=768 got=768 head=[-0.0694580078125, 0.07080078125, ...]
  IxMnnNative: llm loaded from .../qwen3-0.6b-mnn/config.json
  godot: mnn chat: - Greetings!
```

Load is ~1.5 s for the embedder and ~1.5–6 s for the 0.6B; a greeting decodes
in well under a second on both. The two phones' vectors differ in the low bits
— `precision: low` in `config.json`, different CPUs — so treat embeddings as
comparable within a device, not across the mesh, until that is measured.

## ixbody — the camera, and what deliberately cannot leave it

MediaPipe Tasks Vision rather than MNN; the reasoning is in docs/ROADMAP.md
Phase 5 and at the top of `IxBody.kt`. Unlike MNN it needs no drop-in: the
engine arrives as a Maven artifact and the 3.7 MB `face_landmarker.task` is
fetched into `src/main/assets` by the build (`fetchModel`, copied from
`../tools/` first if a checkout already has it). Neither is committed.

**The public surface is three signals of words and floats and nothing else.**
No bitmap, no buffer, no landmark array, no handle that resolves into one, and
no CameraX Preview use case — nothing draws the camera, so no screenshot of
this app can contain a frame. `scripts/body/body_sense.gd` is the only caller
and `BodySense.event_is_clean()` refuses anything image-shaped at any depth of
an event. That is how README's "device-to-device events, never frames" is made
true structurally instead of promised.

**The duty cycle lives in GDScript, not here.** `start()` opens a window and
`stop()` closes it; the seam calls them 1.5 s in 30 s. Two reasons: it is a
battery decision that has to be testable headless, and the one time a duty
cycle went wrong in this repo it was because only the native side knew what it
was (ixloc's `set_mode`).

**A future can outlive the window that asked for it.** `ProcessCameraProvider.
getInstance` took ~3 s on a cold first bind on the Fold; the window closed,
`stop()` unbound a provider that did not exist yet, and the listener bound the
camera anyway with nothing left to close it — 170 frames in the next window
instead of six, i.e. a 5% duty cycle silently running at 100%. `wanted` is
cleared first thing in `stop()` and re-checked inside the callback, which drops
the late bind. Anything else added here that binds hardware asynchronously
needs the same gate.

## Build

```
JAVA_HOME=".../Android Studio/jbr" ./gradlew :ixloc:assembleRelease :ixmesh:assembleRelease :ixmnn:assembleRelease :ixbody:assembleRelease :ixcap:assembleRelease
                                   ./gradlew :ixloc:assembleDebug   :ixmesh:assembleDebug   :ixmnn:assembleDebug   :ixbody:assembleDebug   :ixcap:assembleDebug
cp ixloc/build/outputs/aar/ixloc-release.aar   ../addons/ixloc/bin/release/
cp ixloc/build/outputs/aar/ixloc-debug.aar     ../addons/ixloc/bin/debug/
cp ixmesh/build/outputs/aar/ixmesh-release.aar ../addons/ixmesh/bin/release/
cp ixmesh/build/outputs/aar/ixmesh-debug.aar   ../addons/ixmesh/bin/debug/
cp ixmnn/build/outputs/aar/ixmnn-release.aar   ../addons/ixmnn/bin/release/
cp ixmnn/build/outputs/aar/ixmnn-debug.aar     ../addons/ixmnn/bin/debug/
cp ixbody/build/outputs/aar/ixbody-release.aar ../addons/ixbody/bin/release/
cp ixbody/build/outputs/aar/ixbody-debug.aar   ../addons/ixbody/bin/debug/
cp ixcap/build/outputs/aar/ixcap-release.aar   ../addons/ixcap/bin/release/
cp ixcap/build/outputs/aar/ixcap-debug.aar     ../addons/ixcap/bin/debug/
```

`ixcap` is HexCam's camera (CameraX `VideoCapture`). It shares CameraX with
`ixbody` and the two versions MUST match — two CameraX versions in one APK is
the dual-registry crash avatar paid for once, resolved silently by Gradle with
the loser's native symbols missing at runtime.

Both `debug/` and `release/` must be filled (avatar's release-export gotcha: a
missing release aar kills export at `:checkStandardReleaseAarMetadata`).

`gradle.properties` caps the daemon at 1 GB and runs the Kotlin compiler
in-process: on an 8 GB machine the default 2 GB daemon plus a separate Kotlin
daemon crashed the JVM with a malloc failure.

## Export plumbing

`addons/ixmesh` and `addons/ixmnn` are Godot 4 editor plugins (`plugin.cfg` +
`export_plugin.gd`, enabled in `project.godot`). Each `EditorExportPlugin`
returns its aar from `_get_android_libraries()` and its Maven coordinates from
`_get_android_dependencies()` — without the latter Godot's Gradle bundles only
the plugin's own classes. `ixmesh` also declares the Nearby permission set
(`BLUETOOTH_ADVERTISE/CONNECT/SCAN`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`,
`NEARBY_WIFI_DEVICES`) via `_get_android_manifest_element_contents()`, and
`ixloc` declares `ACCESS_COARSE_LOCATION` and `ACCESS_FINE_LOCATION`, and
`ixbody` declares `CAMERA` — each in exactly one plugin, see below.

**Declare a permission in exactly one plugin.** `ixmesh` used to declare
`ACCESS_FINE_LOCATION` with `android:maxSdkVersion="32"`, since Nearby needs
location below API 33 and not above. The manifest merger merges *attributes* as
well as names, so on every API 33+ phone the merged manifest carried FINE capped
away — the app could only hold COARSE, FusedLocationProvider never engaged GNSS,
and every fix was a 2000 m cell-tower centroid. It now lives only in `ixloc`,
uncapped, which covers Nearby's pre-33 need as well.

**Verify the merged manifest, never the source.** Two plugins' declarations are
merged by Gradle at export time and neither source file shows the result:

```
aapt2 dump xmltree hexy-debug.apk --file AndroidManifest.xml | grep -A1 FINE_LOCATION
# ACCESS_FINE_LOCATION with no maxSdkVersion attribute under it = correct
adb shell pm grant app.ix64.hexy android.permission.ACCESS_FINE_LOCATION
adb shell dumpsys package app.ix64.hexy | grep "ACCESS_FINE_LOCATION: granted"
```

**`Object.has_method()` answers false for every `@UsedByGodot` method.** A Godot
Android plugin arrives in GDScript as a JNISingleton, which dispatches through
its own method map rather than through MethodBind. A `has_method` guard around a
plugin call therefore never fires and the call is silently skipped — this cost a
whole device session with `geo: mode=high` printing while the plugin stayed on
balanced power. `has_signal()` does not have the problem; signals really are
added to the object. `ixmnn` declares no MNN
dependency because there is none — its `.so` files ride inside its own aar.

Shipping the aar is not enough to make a plugin exist. Godot finds plugins by
scanning the merged manifest for
`<meta-data android:name="org.godotengine.plugin.v2.<Name>" android:value="<class>" />`,
so each module carries that in its own `src/main/AndroidManifest.xml`. Without
it the aar lands in the APK, `GodotPluginRegistry` logs only `AndroidRuntime`,
and both seams fall back silently — `backend=lan`, `backend=mock`.

## Runtime permissions — requested in-app

`start()` no longer assumes the dangerous permissions are held. It computes the
set for the running API level (31+: `BLUETOOTH_ADVERTISE/CONNECT/SCAN`; 33+ adds
`NEARBY_WIFI_DEVICES`; below 31: `ACCESS_FINE_LOCATION`), and if any are missing
it calls `ActivityCompat.requestPermissions` on the UI thread and returns
*without* touching Nearby. Advertising and discovery start from
`onMainRequestPermissionsResult`, with `onMainResume` as a re-check in case the
dialog was answered while Godot was paused. `pm grant` is no longer needed.

Verified on a Fold 4 (API 35, `RFCT71BW9YV`) from a fresh install: one system
dialog covering all four, one tap on Allow, then
`IxMesh: permissions granted; starting advertising + discovery as hexy-1e59`.

The endpoint name is `<displayName>-<first 4 of ANDROID_ID>`, not the bare
GDScript name: `onEndpointFound` picks a requester by lexicographic tiebreak, so
two installs sharing the name `hexy` would both request and neither would win
cleanly.

## `start()` is a handshake, not a switch

**An emit before anybody connected is not delayed, it is destroyed.** The
rotation-vector listener starts from `onMainResume`, at Activity resume;
`scripts/social/geo.gd` connects to `heading_changed` when Godot has loaded the
main scene and calls `start()`. On the A22 that gap is **1.49 s**, and it
swallowed three heading emits, a pose and an accuracy level. The delta gate in
`publishHeading` then suppressed every later sample on a motionless phone, so the
stream was over: three values, all lost, none repeatable. GDScript held its
initial `0.0` for the rest of the session and the dial froze on `0 + declination`.

So `start()` re-announces everything already known — pose, accuracy, declination,
heading — and resets the emit gate, because it is the one moment the plugin knows
a listener exists. `onMainResume` does the same after a pause re-registers.

Two rules follow for anything else added to this plugin:

- **Every signal must have a re-announce path.** A value emitted once, at a
  moment of the plugin's choosing, reaches whoever happened to be connected and
  nobody else.
- **A throttle must never be the only gate.** `publishHeading` carries a
  one-second keepalive alongside its 1° delta, so silence means *broken* rather
  than *unchanged* — which is what lets `Geo`'s four-second watchdog exist at all.

And two logging rules, because both of these bugs were invisible:

- `registerListener` returns `false` when the platform declines. **Log the
  result**, and the sensor's type and name with it; the old line said
  "registered" either way.
- Print a periodic summary (samples/s seen, samples/s sent, raw, smoothed, pose).
  A dead stream and a still phone produce identical logs otherwise, and an empty
  log is not evidence of anything.

### DEVICE — 2026-08-18

Both phones, fresh install, flat on a desk, ~45 s each. The acceptance test is
that the plugin's number and GDScript's number are the same number:

```
A22 (R9WT200BA8F)   IxLoc  heading: 292.7 true (313.7 magnetic -21.04 decl)
                    godot  geo: heading=292.7° (true) = 313.7° magnetic -21.04° decl
                    IxLoc  heading: 50.3 samples/s seen, 1.0/s sent (252/5 in 5.0s)

Fold 4 (RFCT71BW9YV) IxLoc  heading: 343.1 true (4.2 magnetic -21.04 decl)
                    godot  geo: heading=343.1° (true) = 4.2° magnetic -21.04° decl
                    IxLoc  heading: 15.1 samples/s seen, 1.0/s sent (76/5 in 5.0s)
```

88 paired comparisons across three captures, 0 mismatched. Before the fix the
same comparison read `kotlin=61.9 gdscript=0.0`. Sensor rates differ by hardware
(50.3 Hz / 15.1 Hz) and the delivered rate does not (1.0/s, the keepalive).

Nobody lifted or turned either phone — `adb` cannot — so the dial's response to a
real turn is still UNBUILT.

## Contract

The GDScript seams (`scripts/net/mesh_peer.gd`, `scripts/brain/mnn_runtime.gd`)
are the only callers. Wire shape = the desktop backends' wire shape: JSON
events on the mesh, FloatArray embeddings from MNN. Desktop fallbacks stay
forever — they are the test rig, not a stopgap.

| Singleton | Signals | Methods |
|---|---|---|
| `IxMesh` | `peer_found(String,String)`, `peer_lost(String)`, `event_received(String,String)`, `peer_proximity(String,String)`, `bandwidth_changed(String,String)`, `probe_done(String,String,double,double)` | `start(String)`, `stop()`, `broadcast(String)`, `connected_peers() -> String`, `probe_send(String,int) -> bool`, `probe_send_chunks(String,int,int) -> bool` |
| `IxLoc` | `location_changed(double,double,double)` (lat, lon, acc), `heading_changed(double)` (degrees clockwise from **magnetic** north), `declination_changed(double)`, `heading_accuracy_changed(int)`, `pose_changed(String,double)` | `available() -> bool`, `has_fine_permission() -> bool`, `start()` (**also a handshake — see below**), `stop()`, `set_mode(bool)` (true = `PRIORITY_HIGH_ACCURACY` at 2 s, false = balanced at 10 s), `high_accuracy() -> bool` |
| `IxBody` | `face_seen(double,double,double,double)` (confidence, smile, surprise, blink — all 0..1), `face_gone()`, `body_fault(String)` | `available() -> bool`, `has_camera_permission() -> bool`, `start()` (opens a sampling window; requests CAMERA the first time), `stop()` (unbinds the camera and closes the graph), `is_running() -> bool` |
| `IxMnn` | — | `runtime_ready() -> bool`, `embed_start(String) -> int` (dim, 0 = failed), `embed_dim() -> int`, `embed(String) -> FloatArray`, `chat_start(String) -> bool`, `chat_ready() -> bool`, `chat(String) -> String`, `release()` |
