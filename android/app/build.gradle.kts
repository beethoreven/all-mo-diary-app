import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key. key.properties and the key file stay out of git.
// Once a build signed with a key is installed on a phone, every later build must use the same key;
// a different key means uninstalling first, which deletes the diaries on that phone. Back the key up.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = !keyProps.isEmpty

android {
    // Package name: can never change after release.
    namespace = "tw.com.tutorarthur.allmodiary"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // DiagnosticsChannel uses BuildConfig.DEBUG to keep the debug-only crash/hang tools out of release builds.
        buildConfig = true
    }

    defaultConfig {
        applicationId = "tw.com.tutorarthur.allmodiary"
        // Android 11 and up (emoji from Unicode 13; ApplicationExitInfo for the crash diagnostics).
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Shrinking and trimming diary videos (VideoChannel.kt). The version is set once in
    // android/build.gradle.kts, together with the player that video_player brings.
    val media3Version: String by rootProject.extra
    implementation("androidx.media3:media3-transformer:$media3Version")
    implementation("androidx.media3:media3-effect:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")
    implementation("androidx.media3:media3-muxer:$media3Version")
    implementation("androidx.media3:media3-container:$media3Version")
    // The system photo picker's intent (PickVisualMedia), which falls back by itself on phones
    // without the picker. Checked on Google Maven 2026-11-13: 1.13.0 is the latest stable.
    implementation("androidx.activity:activity:1.13.0")
}

// A release build without the real key is refused unless explicitly allowed
// (AMD_ALLOW_DEBUG_SIGNING=1), so a debug-signed build never ends up on a family phone.
tasks.configureEach {
    if (name == "assembleRelease" || name == "bundleRelease") {
        doFirst {
            if (!hasReleaseKey && System.getenv("AMD_ALLOW_DEBUG_SIGNING") != "1") {
                throw GradleException(
                    "Missing android/key.properties (the release signing key). To try a release build on your own " +
                        "emulator only, set AMD_ALLOW_DEBUG_SIGNING=1."
                )
            }
        }
    }
}
