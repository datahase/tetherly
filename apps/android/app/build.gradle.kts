plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "link.tetherly"
    compileSdk = 36

    defaultConfig {
        applicationId = "link.tetherly"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Supply the existing Play upload key through the environment. Never use a
    // debug key as a fallback, and never commit passwords or keystore files.
    val uploadVariables = listOf(
        "TETHERLY_UPLOAD_STORE_FILE", "TETHERLY_UPLOAD_STORE_PASSWORD",
        "TETHERLY_UPLOAD_KEY_ALIAS", "TETHERLY_UPLOAD_KEY_PASSWORD"
    )
    val uploadValues = uploadVariables.map { providers.environmentVariable(it).orNull }
    require(uploadValues.all { it.isNullOrBlank() } || uploadValues.all { !it.isNullOrBlank() }) {
        "Set all four TETHERLY_UPLOAD_* variables, or leave all unset for an unsigned preparation build."
    }
    val uploadSigning = if (uploadValues.all { !it.isNullOrBlank() }) {
        signingConfigs.create("upload") {
            storeFile = file(uploadValues[0]!!)
            require(storeFile!!.isFile) { "TETHERLY_UPLOAD_STORE_FILE must point to an existing keystore." }
            storePassword = uploadValues[1]
            keyAlias = uploadValues[2]
            keyPassword = uploadValues[3]
        }
    } else null

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = uploadSigning
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.12.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    // android.jar's org.json is a stub on the JVM; tests need the real implementation.
    testImplementation("org.json:json:20260814")
}

tasks.withType<Test> {
    systemProperty("fixtures", rootProject.projectDir.resolve("../../protocol/fixtures").absolutePath)
}
