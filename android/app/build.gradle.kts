plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun runGitCommand(workDir: File, vararg args: String): String? {
    return try {
        val process = ProcessBuilder(*args)
            .directory(workDir)
            .redirectErrorStream(false)
            .start()
        val output = process.inputStream.bufferedReader().readText().trim()
        if (process.waitFor() == 0) output else null
    } catch (_: Exception) {
        null
    }
}

fun resolveFullAppVersion(repoDir: File, packageVersion: String): String {
    val rawCount = runGitCommand(repoDir, "git", "rev-list", "--count", "HEAD")
    val commitCount = if (!rawCount.isNullOrEmpty() && rawCount.all { it.isDigit() }) {
        rawCount
    } else {
        "0"
    }
    val rawHash = runGitCommand(repoDir, "git", "rev-parse", "--short", "HEAD")
    val commitHash = if (!rawHash.isNullOrEmpty() && rawHash.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }) {
        rawHash
    } else {
        "unknown"
    }
    val rawStatus = runGitCommand(repoDir, "git", "status", "--porcelain")
    val suffix = if (!rawStatus.isNullOrEmpty()) ".dev" else ""
    return "v$packageVersion+$commitCount.$commitHash$suffix"
}

android {
    namespace = "de.akjir.tiertask"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.akjir.tiertask"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue(
            "string",
            "tiertask_full_version",
            resolveFullAppVersion(rootProject.projectDir.parentFile, flutter.versionName ?: "0.1.0"),
        )
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
