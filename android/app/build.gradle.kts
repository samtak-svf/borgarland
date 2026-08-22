import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Where the relay lives, per build type (#29). The counterpart of
// ios/BorgarlandCore/.../RelayEndpoint.swift, and the same reasoning: a release
// build carrying the loopback is dead in the field, because on a real phone
// 127.0.0.1 is the phone. It fails loudly for the user and silently for us —
// no test and no CI run notices, since RelayRequestTest pins the body and
// never the host.
val relayBaseUrlDebug = "http://127.0.0.1:8787"
val relayBaseUrlRelease = "https://borgarland.samtak.is"

// The guard that makes a loopback release impossible rather than unlikely.
// This runs at configuration time, so a wrong value fails the build before it
// produces an artifact anyone could install.
check(relayBaseUrlRelease.startsWith("https://")) {
    "the release relay URL must be https, not: $relayBaseUrlRelease"
}
check(listOf("127.0.0.1", "localhost", "::1", "0.0.0.0").none { relayBaseUrlRelease.contains(it) }) {
    "the release relay URL must not be a loopback: $relayBaseUrlRelease"
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
        debug {
            buildConfigField("String", "RELAY_BASE_URL", "\"$relayBaseUrlDebug\"")
        }
        release {
            isMinifyEnabled = false
            buildConfigField("String", "RELAY_BASE_URL", "\"$relayBaseUrlRelease\"")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        // Required for buildConfigField above; off by default since AGP 8.
        buildConfig = true
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
