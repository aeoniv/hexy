// THE PLACE THE SEVEN MODULES STOPPED REPEATING THEMSELVES.
//
// Each android_plugin/<mod>/build.gradle.kts carried the same five lines —
// compileSdk, minSdk, both Java compatibilities, the Kotlin jvmTarget and the
// compileOnly godot-lib coordinate — and an SDK bump was a seven-file edit with
// no way to notice the file that did not get edited. They now live in one
// precompiled script plugin, `ix64.android.plugin`, and a module states only
// what is actually its own: its namespace, its dependencies, and (ixmnn, ixbody)
// the build settings that genuinely differ.
plugins { `kotlin-dsl` }

repositories {
	google()
	mavenCentral()
	gradlePluginPortal()
}

// The same versions the root build declares. buildSrc resolves its own
// classpath, so these are stated rather than inherited; if the root moves, this
// moves with it or the convention plugin compiles against the wrong AGP.
dependencies {
	implementation("com.android.tools.build:gradle:8.7.3")
	implementation("org.jetbrains.kotlin:kotlin-gradle-plugin:2.0.21")
}
