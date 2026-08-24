# R8 rules for the release build (#118).
#
# These exist for exactly one reason: Firebase discovers its per-library
# ComponentRegistrar through a service loader, not through a direct reference,
# so nothing in the build graph knows the class is needed and R8 removes it.
# The build succeeds, the Crashlytics Gradle tasks succeed, and the app crashes
# on every launch with "FirebaseCrashlytics component is not present".
#
# That is not hypothetical. Simaver 0.1.0-beta35 went to 26 internal testers in
# May 2026 and none of them could open it. The only thing that catches it is
# launching the release-signed APK on a real device, which is why #118 required
# a smoke test rather than a green build.

# Every Firebase library that uses the Components SDK.
-keep class com.google.firebase.components.ComponentRegistrar
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }

# Crashlytics specifically. Swap the package if Analytics, Performance or
# Messaging is ever added -- each needs its own pair.
-keepnames class com.google.firebase.crashlytics.** { *; }
-keepclassmembers class com.google.firebase.crashlytics.** { *; }

# kotlinx.serialization needs NO rules here, deliberately. The library ships its
# own consumer rules (META-INF/proguard/kotlinx-serialization-common.pro inside
# the artifact) and R8 applies them automatically. Hand-writing a second set
# would duplicate them and drift from whatever the library ships next.
# Verified by reading the jar rather than by assuming.
