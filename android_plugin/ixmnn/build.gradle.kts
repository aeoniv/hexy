plugins {
	id("com.android.library")
	id("org.jetbrains.kotlin.android")
}

android {
	namespace = "com.ix64.hexy.mnn"
	compileSdk = 35
	defaultConfig {
		minSdk = 24
		ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
		externalNativeBuild {
			cmake {
				// MNN's prebuilt .so files are built against libc++_shared;
				// our bridge must use the same STL or std::string crosses the
				// boundary with a different layout.
				arguments += listOf("-DANDROID_STL=c++_shared")
				cppFlags += "-fexceptions"
			}
		}
	}

	externalNativeBuild {
		cmake {
			path = file("src/main/cpp/CMakeLists.txt")
			version = "3.22.1"
		}
	}

	packaging {
		// libc++_shared.so arrives twice: once from libs/mnn-jni (it ships in
		// MNN's release zip and libMNN.so needs it) and once from the NDK for
		// our own bridge. They are the same library; take one.
		jniLibs.pickFirsts += "**/libc++_shared.so"
	}
	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}
	kotlinOptions { jvmTarget = "17" }
	// MNN ships no AAR and no Maven artifact (checked releases up to 3.6.1:
	// every android asset is a zip of bare .so files). So the runtime arrives
	// as loose jniLibs unpacked from mnn_<ver>_android_*.zip into libs/mnn-jni/
	// — see README. libMNN.so is what System.loadLibrary("MNN") resolves;
	// libc++_shared.so must travel with it or the load fails.
	sourceSets["main"].jniLibs.srcDir(rootProject.file("libs/mnn-jni"))
}

val godotLib = rootProject.file("libs/godot-lib.template_release.aar")

dependencies {
	compileOnly(files(godotLib))
	implementation("androidx.core:core-ktx:1.15.0")

	// The one-shot back lens (IxLens, Phase 6). Same CameraX version ixbody
	// pins — two plugins in one APK resolving to two CameraX versions is a
	// dependency fight nobody wins, and the front and back lenses have no
	// reason to disagree about which library they are.
	val cameraX = "1.4.1"
	implementation("androidx.camera:camera-core:$cameraX")
	implementation("androidx.camera:camera-camera2:$cameraX")
	implementation("androidx.camera:camera-lifecycle:$cameraX")
}
