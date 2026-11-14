// Jetpack Media3 (checked on Google Maven 2026-11-13: 1.11.1 is the latest stable).
// Every Media3 module in one app must be the same version. The app's own video code uses the
// transformer; the video_player plugin brings the player and names an older version (1.9.2 in
// video_player_android 2.12.4), so all of them are set to this one here.
val media3Version by extra("1.11.1")
// Declared before anything else: the blocks below evaluate :app, which reads it.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.media3") useVersion(media3Version)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
