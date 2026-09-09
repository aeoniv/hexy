// NO `plugins { ... version ... apply false }` BLOCK. AGP 8.7.3 and Kotlin
// 2.0.21 now arrive on every project's buildscript classpath through
// `buildSrc/build.gradle.kts`, which is what compiles the `ix64.android.plugin`
// convention the seven modules apply. Declaring a version here as well is the
// "plugin is already on the classpath with an unknown version" failure: the
// versions live in buildSrc and only there.

/**
 * THE COPY THAT USED TO BE A SENTENCE IN A RUNBOOK.
 *
 * docs/FIELD.md said "copy each result to addons/<plugin>/bin/{debug,release}/"
 * and nothing enforced it. The AARs are gitignored build output, so a forgotten
 * copy leaves a STALE plugin in the export with no diff to notice and no error
 * to read: the APK builds, installs, runs, and answers the old questions. Every
 * hour lost to "the Kotlin change did nothing" was this.
 *
 * So the copy is a task now, and it is the only supported way to stage an AAR.
 * `./gradlew exportAllAars` from android_plugin/ builds all seven modules in
 * both flavours and puts them where the export presets look.
 *
 * IT ALSO STAMPS A VERSION. Each module's Kotlin file carries one
 * `const val PLUGIN_VERSION = "<name>/<n>"`, and that string is read out of the
 * source here and written to `addons/<name>/bin/VERSION` — a tracked file, so
 * the version that was staged is visible in git even though the AAR beside it
 * is not. `scripts/seam.gd` asks the running plugin the same question at attach
 * and refuses a plugin that answers with a different number.
 */
val versionLine = Regex("""PLUGIN_VERSION\s*=\s*"([^"]+)"""")

subprojects {
	tasks.register<Copy>("exportAars") {
		group = "hexy"
		description = "Build both flavours and stage them in addons/${project.name}/bin/."
		dependsOn("assembleDebug", "assembleRelease")

		val bin = rootProject.file("../addons/${project.name}/bin")
		val srcDir = project.file("src/main/kotlin")
		val moduleName = project.name
		into(bin)
		// Two specs rather than one: `outputs/aar/` is flat, and debug and
		// release must land in different directories because the Godot export
		// plugin picks per build type.
		from(layout.buildDirectory.dir("outputs/aar")) {
			include("*-debug.aar")
			into("debug")
		}
		from(layout.buildDirectory.dir("outputs/aar")) {
			include("*-release.aar")
			into("release")
		}

		doLast {
			// The stamp. One source of truth — the Kotlin constant — copied to
			// a place a human and a git diff can both read.
			var stamped = ""
			srcDir.walkTopDown().filter { it.extension == "kt" }.forEach { f ->
				val m = versionLine.find(f.readText())
				if (m != null && stamped.isEmpty()) stamped = m.groupValues[1]
			}
			if (stamped.isEmpty()) {
				throw GradleException(
					"$moduleName: no PLUGIN_VERSION constant in src/main/kotlin — " +
						"the seam handshake has nothing to compare against")
			}
			File(bin, "VERSION").writeText(stamped + "\n")
			logger.lifecycle("$moduleName: staged $stamped -> ${bin.path}")
		}
	}
}

/**
 * ONE VERB FOR THE WHOLE STAGE. Seven modules, both flavours, every AAR where
 * the export looks and every VERSION file rewritten. This is the command
 * docs/FIELD.md now names, and `tools/preflight_aars.py` is the thing that
 * tells you when you forgot to run it.
 */
tasks.register("exportAllAars") {
	group = "hexy"
	description = "Stage every plugin AAR into addons/<name>/bin/."
	dependsOn(subprojects.map { "${it.path}:exportAars" })
}
