plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.aplicaciones_foliares"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

   defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.gestion_campo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 💡 ACA ES LO NUEVO: Filtro NDK para empaquetar solo lo necesario en producción
        ndk {
            abiFilters.addAll(setOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    // 💡 ACA ES LO NUEVO: Configuración de división de APKs por arquitectura
    splits {
        abi {
            isEnable = true // Activa la división de APKs
            reset()         // Resetea las configuraciones por defecto de Android Studio
            include("armeabi-v7a", "arm64-v8a", "x86_64") // Arquitecturas a generar
            isUniversalApk = true // Genera también un APK gordo que funciona en cualquier lado
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 🛠️ ESTO LO MODIFIQUE: Parche de empaquetado nativo adaptado a la sintaxis estricta de Kotlin DSL
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}