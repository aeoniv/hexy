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
		from(layout.buildDirectory.dir("outputs/aar")) {
			include("*-debug.aar")
			into("debug")
		}
		from(layout.buildDirectory.dir("outputs/aar")) {
			include("*-release.aar")
			into("release")
		}

		doLast {
			var stamped = ""
			srcDir.walkTopDown().filter { it.extension == "kt" }.forEach { f ->
				val m = versionLine.find(f.readText())
				if (m != null && stamped.isEmpty()) stamped = m.groupValues[1]
			}
			if (stamped.isEmpty()) {
				throw GradleException("$moduleName: no PLUGIN_VERSION constant in src/main/kotlin")
			}
			File(bin, "VERSION").writeText(stamped + "\n")
			logger.lifecycle("$moduleName: staged $stamped -> ${bin.path}")
		}
	}
}

tasks.register("exportAllAars") {
	group = "hexy"
	description = "Stage ixmnn plugin AAR into addons/ixmnn/bin/."
	dependsOn(subprojects.map { "${it.path}:exportAars" })
}
