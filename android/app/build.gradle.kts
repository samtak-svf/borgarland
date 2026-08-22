import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "is.borgarland.poc"
    compileSdk = 36

    defaultConfig {
        applicationId = "is.borgarland.poc"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.kotlinx.serialization.json)
    debugImplementation(libs.androidx.ui.tooling)
    testImplementation(libs.junit)
}

// The facts file has exactly one home: data/reykjavik-form.json at the repo
// root, read by scripts/send-report.mjs, the Worker adapter and CI. The app
// needs it on the device, so it is copied in at build time rather than
// committed a second time. A copy in git is a copy that drifts, which is the
// failure decisions/0001 exists to prevent; a copy made by the build cannot.
val copyFacts by tasks.registering(Copy::class) {
    from(rootProject.file("../data/reykjavik-form.json"))
    into(layout.projectDirectory.dir("src/main/assets"))
}

// The relay request contract has the same single home: data/relay-request.json
// at the repo root, read by the Worker (worker/src/app.ts) and CI
// (scripts/check-relay-contract.mjs). The app needs it on the device to know
// what it may send, so it is copied in at build time, same pattern and same
// reasoning as the facts file above.
val copyRelayRequest by tasks.registering(Copy::class) {
    from(rootProject.file("../data/relay-request.json"))
    into(layout.projectDirectory.dir("src/main/assets"))
}

tasks.named("preBuild") { dependsOn(copyFacts, copyRelayRequest) }
