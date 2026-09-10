// ix64.android.plugin — everything all seven Godot plugin modules agree on.
//
// compileSdk 35 / minSdk 24: 24 is the floor CameraX, MediaPipe, ARCore and the
// speech stack all clear, and the first level with the ImageAnalysis
// backpressure behaviour the body pipeline relies on. Java 17 and a matching
// Kotlin jvmTarget because Godot 4.7's own Android build is 17.
//
// godot-lib.aar is NOT vendored: extract it from the Godot 4.7.1 export
// templates into android_plugin/libs/ (see libs/extract-godot-lib.ps1).
// compileOnly — the engine supplies the real implementation at runtime, and a
// second copy inside an aar is a duplicate-class failure at export.
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
	id("com.android.library")
	id("org.jetbrains.kotlin.android")
}

android {
	compileSdk = 35
	defaultConfig { minSdk = 24 }
	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}
}

tasks.withType<KotlinCompile>().configureEach {
	compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
}

dependencies {
	"compileOnly"(files(rootProject.file("libs/godot-lib.template_release.aar")))
}
