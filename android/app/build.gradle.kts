import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real upload key when android/key.properties exists (never committed);
// debug keys otherwise, so `flutter run --release` still works unconfigured.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.arunesh.anvil"
    // 37 (Android 17), above Flutter's default 36: receive_sharing_intent 1.9.0
    // compiles against 37, and AGP requires consumers to match or exceed it.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.arunesh.anvil"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // STACK.md: minSdk 26+ for later ML/NPU engines
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Needle 3's engine is a static archive we relink into
        // libneedle_ffi.so. abiFilters here scopes ONLY the CMake build (the
        // archive exists for arm64-v8a/armeabi-v7a and nothing else);
        // defaultConfig.ndk.abiFilters would instead strip x86_64 from every
        // other plugin and break emulator builds of the rest of the app.
        // c++_static keeps libc++ inside our .so — the archive is its only
        // consumer, so no libc++_shared.so is added to the APK.
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_static")
                cppFlags += "-std=c++17"
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
            }
        }
    }

    signingConfigs {
        keystoreProperties.getProperty("storeFile")?.let { path ->
            create("release") {
                storeFile = file(path)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // onnxruntime and sherpa_onnx_android_arm64 both bundle libonnxruntime.so;
    // keep the first to resolve the duplicate-native-lib merge conflict.
    packaging {
        jniLibs {
            pickFirsts.add("**/libonnxruntime.so")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
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
