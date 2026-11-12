import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is opt-in: only builds started with MLC_RELEASE_SIGNING=1 (set by
// scripts/release.sh) use the release keystore from android/key.properties (git-ignored).
// Every other build, including `flutter run --release` and scripts/run.sh, uses the debug key.
// See docs/ANDROID-RELEASE.md.
val useReleaseSigning = providers.environmentVariable("MLC_RELEASE_SIGNING").orNull == "1"
val keystorePropertiesFile = rootProject.file("key.properties")
if (useReleaseSigning && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "MLC_RELEASE_SIGNING=1 but android/key.properties was not found. " +
            "See docs/ANDROID-RELEASE.md."
    )
}
val keystoreProperties = Properties().apply {
    if (useReleaseSigning) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "com.repasscloud.mylittlecrm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.repasscloud.mylittlecrm"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (useReleaseSigning) {
            create("release") {
                fun prop(name: String) = keystoreProperties.getProperty(name)
                    ?: throw GradleException("android/key.properties is missing '$name'.")
                keyAlias = prop("keyAlias")
                keyPassword = prop("keyPassword")
                storeFile = file(prop("storeFile"))
                storePassword = prop("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug key unless scripts/release.sh asked for the release key.
            // Never distribute an APK signed with the debug key.
            signingConfig = signingConfigs.getByName(if (useReleaseSigning) "release" else "debug")
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
