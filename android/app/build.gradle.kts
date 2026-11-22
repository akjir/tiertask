import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.isFile) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun resolveSigningProperty(propertyKey: String, envVar: String): String? {
    return keystoreProperties.getProperty(propertyKey)?.trim()?.takeIf { it.isNotEmpty() }
        ?: System.getenv(envVar)?.trim()?.takeIf { it.isNotEmpty() }
}

val releaseStorePath = resolveSigningProperty("storeFile", "TIERTASK_KEYSTORE_PATH")
val releaseStorePassword = resolveSigningProperty("storePassword", "TIERTASK_KEYSTORE_PASSWORD")
val releaseKeyAlias = resolveSigningProperty("keyAlias", "TIERTASK_KEY_ALIAS")
val releaseKeyPassword = resolveSigningProperty("keyPassword", "TIERTASK_KEY_PASSWORD")
val hasReleaseSigning =
    releaseStorePath != null &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

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

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "de.akjir.tiertask"
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
            resolveFullAppVersion(rootProject.projectDir.parentFile, flutter.versionName ?: "0.5.0"),
        )
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                val configuredPath = requireNotNull(releaseStorePath)
                val candidateFile = File(configuredPath)
                storeFile = if (candidateFile.isAbsolute) {
                    candidateFile
                } else {
                    rootProject.file(configuredPath)
                }
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
