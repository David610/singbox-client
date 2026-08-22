import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

var dartEnvironmentVariables = mutableMapOf("publish" to false)

if (project.hasProperty("dart-defines")) {
    dartEnvironmentVariables.putAll(
            (project.property("dart-defines") as String).split(',').associate { entry ->
                val pair = String(Base64.getDecoder().decode(entry)).split('=')
                pair.first() to (pair.last() == "true")
            }
    )
}

android {
    namespace = "com.david610.singboxclient"
    compileSdkVersion = "android-35"
    buildToolsVersion = "36.0.0"
    ndkVersion = "28.2.13676358" // flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }

    defaultConfig {
        applicationId = "com.david610.singboxclient"
        minSdk = 26 // apk size(android:extractNativeLibs):
        // https://github.com/flutter/website/blob/ada9edc19074cce17e92b129eec0759bad7c3c7c/src/content/platform-integration/android/c-interop.md?plain=1#L180
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        val keystore = rootProject.file("./key.properties")
        val prop = Properties().apply { keystore.inputStream().use(this::load) }
        named("debug") { ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86") } }
        named("profile") {
            signingConfig =
                    signingConfigs.create("profile") {
                        storeFile = rootProject.file(prop.getProperty("storeFile.release"))
                        storePassword = prop.getProperty("storePassword.release")
                        keyAlias = prop.getProperty("keyAlias.release")
                        keyPassword = prop.getProperty("keyPassword.release")
                    }
            ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86") }
        }
        named("release") {
            // packagingOptions {
            //   doNotStrip = '**/*.so'
            // }
            // shrinkResources = true
            // proguardFiles = getDefaultProguardFile('proguard-android-optimize.txt'),
            // 'proguard-rules.pro'
            signingConfig =
                    signingConfigs.create("release") {
                        storeFile = rootProject.file(prop.getProperty("storeFile.release"))
                        storePassword = prop.getProperty("storePassword.release")
                        keyAlias = prop.getProperty("keyAlias.release")
                        keyPassword = prop.getProperty("keyPassword.release")
                    }
            ndk {
                abiFilters.clear()
                abiFilters += listOf("armeabi-v7a", "arm64-v8a")
                // debugSymbolLevel = 'FULL'
            }
        }
    }
    splits {
        abi {
            isEnable = true
            isUniversalApk = true
            reset()
            include("armeabi-v7a", "arm64-v8a")
        }
    }
}

flutter { source = "../.." }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.browser:browser:1.8.0")

    // packages/vpn_core (an Android library module, included as a
    // Flutter plugin) only depends on this compileOnly -- see
    // packages/vpn_core/android/build.gradle's comment: the Android
    // Gradle Plugin refuses to bundle a *library* module's own AAR
    // output if it has a direct local-.aar runtime dependency. This
    // application module has no such restriction, so it takes the real
    // `implementation` dependency instead, which is what actually lands
    // io.nekohasekai.libbox.*'s classes in the runtime classpath and the
    // final APK -- required for SingBoxVpnService.kt (used by vpn_core,
    // which this app depends on) to do anything at runtime, not just
    // compile.
    val libboxAar = file("../../packages/vpn_core/android/libs/libbox.aar")
    if (libboxAar.exists()) {
        implementation(files(libboxAar))
    }
}

configurations.configureEach {
    resolutionStrategy.force(
            "androidx.browser:browser:1.8.0",
            "androidx.core:core:1.15.0",
            "androidx.core:core-ktx:1.15.0",
            "androidx.activity:activity:1.9.3",
            "androidx.activity:activity-ktx:1.9.3",
    )
}
