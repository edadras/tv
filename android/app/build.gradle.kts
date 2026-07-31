plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.edadras.lan_cast"
    // Pinned to the newest *stable* API. Letting this float picks up preview
    // platforms that are not in the public SDK repo yet, which breaks CI.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.edadras.lan_cast"
        // Android 7.0. Covers the Android TV boxes still in use without
        // dragging in the legacy storage model.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with the debug key on purpose: this app is sideloaded, not
            // shipped through a store, and a stable key means updates install
            // over the top instead of forcing an uninstall. Drop your own
            // keystore in here if you would rather sign it yourself.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        // One universal APK: the whole point is being able to drop a single
        // file onto any TV and have it install.
        jniLibs.useLegacyPackaging = false
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
