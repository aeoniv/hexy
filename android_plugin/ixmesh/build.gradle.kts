plugins {
	// compileSdk, minSdk, Java/Kotlin 17 and the compileOnly godot-lib
	// coordinate all live in buildSrc/src/main/kotlin/ix64.android.plugin.gradle.kts.
	id("ix64.android.plugin")
}

android {
	namespace = "com.ix64.hexy.mesh"
}

dependencies {
	implementation("com.google.android.gms:play-services-nearby:19.3.0")
	implementation("androidx.core:core-ktx:1.15.0")
}
