pluginManagement {
	repositories {
		google()
		mavenCentral()
		gradlePluginPortal()
	}
}
dependencyResolutionManagement {
	repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
	repositories {
		google()
		mavenCentral()
	}
}

rootProject.name = "ixhexy"
include(":ixmesh")
include(":ixmnn")
include(":ixloc")
include(":ixbody")
include(":ixvoice")
include(":ixcap")
