plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()

if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun readSigningEnv(name: String): String? {
    val value = System.getenv(name) ?: return null
    return if (value.isBlank()) null else value
}

val envStoreFile = readSigningEnv("ANDROID_KEYSTORE_FILE")
val envStorePassword = readSigningEnv("ANDROID_KEYSTORE_PASSWORD")
val envKeyAlias = readSigningEnv("ANDROID_KEY_ALIAS")
val envKeyPassword = readSigningEnv("ANDROID_KEY_PASSWORD")

val hasAnySigningEnv = listOf(
    envStoreFile,
    envStorePassword,
    envKeyAlias,
    envKeyPassword,
).any { it != null }

val hasCompleteSigningEnv = listOf(
    envStoreFile,
    envStorePassword,
    envKeyAlias,
    envKeyPassword,
).all { it != null }

if (hasAnySigningEnv && !hasCompleteSigningEnv) {
    throw GradleException(
        "检测到部分 Android 签名环境变量。请同时设置 " +
            "ANDROID_KEYSTORE_FILE / ANDROID_KEYSTORE_PASSWORD / " +
            "ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD",
    )
}

val hasSigningConfig = hasCompleteSigningEnv || hasKeystoreProperties

android {
    namespace = "com.aimessoft.misa_rin"
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
        applicationId = "com.aimessoft.misa_rin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "**/libVkLayer_khronos_validation.so",
                "**/libVkLayer_api_dump.so",
            )
        }
    }

    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                val storeFilePath: String
                val storePasswordValue: String
                val keyAliasValue: String
                val keyPasswordValue: String

                if (hasCompleteSigningEnv) {
                    storeFilePath = envStoreFile!!
                    storePasswordValue = envStorePassword!!
                    keyAliasValue = envKeyAlias!!
                    keyPasswordValue = envKeyPassword!!
                } else {
                    val fromPropsStoreFile = keystoreProperties.getProperty("storeFile")
                    val fromPropsStorePassword = keystoreProperties.getProperty("storePassword")
                    val fromPropsKeyAlias = keystoreProperties.getProperty("keyAlias")
                    val fromPropsKeyPassword = keystoreProperties.getProperty("keyPassword")

                    if (fromPropsStoreFile.isNullOrBlank() ||
                        fromPropsStorePassword.isNullOrBlank() ||
                        fromPropsKeyAlias.isNullOrBlank() ||
                        fromPropsKeyPassword.isNullOrBlank()
                    ) {
                        throw GradleException("key.properties 缺少签名字段：storeFile/storePassword/keyAlias/keyPassword")
                    }

                    storeFilePath = fromPropsStoreFile
                    storePasswordValue = fromPropsStorePassword
                    keyAliasValue = fromPropsKeyAlias
                    keyPasswordValue = fromPropsKeyPassword
                }

                val storeFileByKeyPropsDir = keystorePropertiesFile.parentFile.resolve(storeFilePath)
                val storeFileByModuleDir = file(storeFilePath)
                val storeFileByRootDir = rootProject.file(storeFilePath)
                val resolvedStoreFile = when {
                    File(storeFilePath).isAbsolute -> File(storeFilePath)
                    storeFileByKeyPropsDir.exists() -> storeFileByKeyPropsDir
                    storeFileByModuleDir.exists() -> storeFileByModuleDir
                    storeFileByRootDir.exists() -> storeFileByRootDir
                    else -> storeFileByKeyPropsDir
                }
                storeFile = resolvedStoreFile
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
