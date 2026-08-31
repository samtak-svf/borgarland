import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ktlint)
    alias(libs.plugins.google.services)
    alias(libs.plugins.firebase.crashlytics)
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

// Upload signing, per ~/.claude/skills/sosi-android-app-delivery. Values come
// from app/keystore.properties (written by scripts/pull-release-keystore.sh) or
// from the environment in CI. Slug is `borgarland`, so the env prefix is
// BORGARLAND_.
//
// The keystore is NEVER in this repository: it is public, and Play pins the
// upload certificate to the package name for the life of the app, so a leak
// cannot be fixed by rotating.
val keystorePropertiesFile = rootProject.file("app/keystore.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.inputStream().use { load(it) }
        }
    }

fun signingValue(propertyKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propertyKey) ?: System.getenv(envKey)

android {
    namespace = "is.borgarland"
    compileSdk = 36

    defaultConfig {
        applicationId = "is.borgarland"
        minSdk = 26
        targetSdk = 36
        // Driven by CI so a release never carries a placeholder. The skill's
        // rule: the hardcoded default must never reach a store.
        versionCode = (System.getenv("BORGARLAND_VERSION_CODE") ?: "1").toInt()
        versionName = System.getenv("BORGARLAND_VERSION_NAME") ?: "0.1.1"
    }

    signingConfigs {
        create("release") {
            val storeFilePath = signingValue("storeFile", "BORGARLAND_UPLOAD_KEYSTORE_PATH")
            val storePwd = signingValue("storePassword", "BORGARLAND_UPLOAD_KEYSTORE_PASSWORD")
            val alias = signingValue("keyAlias", "BORGARLAND_UPLOAD_KEY_ALIAS")
            val keyPwd = signingValue("keyPassword", "BORGARLAND_UPLOAD_KEY_PASSWORD")
            if (storeFilePath != null && storePwd != null && alias != null && keyPwd != null) {
                storeFile =
                    file(storeFilePath).let { f ->
                        if (f.isAbsolute) f else rootProject.file("app/$storeFilePath")
                    }
                storePassword = storePwd
                keyAlias = alias
                keyPassword = keyPwd
            }
        }
    }

    buildTypes {
        debug {
            buildConfigField("String", "RELAY_BASE_URL", "\"$relayBaseUrlDebug\"")
        }
        release {
            // R8 is ON as of #118, in its own change with its own on-device
            // smoke test, which is the only thing that catches the failure it
            // risks: R8 strips the Crashlytics ComponentRegistrar because it is
            // found by service loader, the build stays green, and the app dies
            // on launch. proguard-rules.pro keeps it, and a real walk on a real
            // phone is what proved the rules are enough.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            buildConfigField("String", "RELAY_BASE_URL", "\"$relayBaseUrlRelease\"")

            // Unsigned if no keystore is present, so a clean clone can still run
            // assembleRelease. Real signing comes from CI env or the pull script.
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile?.exists() == true) releaseSigning else null
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        // The camera is the entry point, so requiring the hardware is the
        // specification rather than an oversight. This check assumes the
        // opposite and asks for required="false", which would be a false
        // declaration: the app cannot do anything on a device with no camera.
        // See the reasoning in AndroidManifest.xml beside the uses-feature tag.
        disable += "PermissionImpliesUnsupportedChromeOsHardware"
        // Everything else is a build failure. A warning nobody reads is the
        // state this workflow exists to leave behind.
        abortOnError = true
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
    // Crashlytics only, no Analytics. The Firebase project is `borgarland-app`
    // on the personal Google account -- the same one ios-release.yml sends
    // dSYMs to. Rosa Parks reports to the party's project; this is a Samtak
    // svf. app and deliberately does not (#37).
    //
    // The keep rules that make this survive R8 are in proguard-rules.pro, and
    // they are not optional: minification is ON (#118), and R8 strips the
    // ComponentRegistrar that Firebase discovers by service loader unless it is
    // told not to. This comment said the opposite until an audit read it against
    // the buildType fifty lines above, which had already been flipped.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.crashlytics)

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

    // The real org.json, for unit tests only. Android ships a STUB of it on the
    // JVM test classpath whose every method throws "not mocked", which is why
    // FollowUps' round trip went untested until #129: the store serialises with
    // JSONObject, so any test that touched it died before asserting anything.
    // This does not reach the app -- the device uses the platform's own.
    testImplementation(libs.json)
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

// Our own words for the city's categories, where the city's are wrong for a
// person standing in front of the thing (#40). Same single-home rule and same
// build-time copy as the two files above; a copy in git is a copy that drifts.
val copyCategoryLabels by tasks.registering(Copy::class) {
    from(rootProject.file("../data/category-labels.json"))
    into(layout.projectDirectory.dir("src/main/assets"))
}

// Our words for what the relay answered, where its own JSON is not something
// to put in front of a person (#77). Same single-home rule and same build-time
// copy as the three files above.
val copyRelayOutcomes by tasks.registering(Copy::class) {
    from(rootProject.file("../data/relay-outcomes.json"))
    into(layout.projectDirectory.dir("src/main/assets"))
}

tasks.named("preBuild") {
    dependsOn(copyFacts, copyRelayRequest, copyCategoryLabels, copyRelayOutcomes)
}
