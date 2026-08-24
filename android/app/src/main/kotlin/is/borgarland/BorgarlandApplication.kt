package `is`.borgarland

import android.app.Application
import com.google.firebase.crashlytics.FirebaseCrashlytics
import `is`.borgarland.net.Telemetry
import `is`.borgarland.net.TelemetryEvent

/**
 * The single place the app starts, and the only place `app-opened` is emitted
 * (#70).
 *
 * The event marks the beginning of a telemetry session, and a session is a
 * process: `Telemetry.shared` is created once per process and its session id
 * lives exactly that long (`Telemetry.kt`). So the emission has to happen
 * somewhere with the same lifetime, and on Android that is `Application`,
 * whose `onCreate` runs once per process and never again.
 *
 * It used to be emitted from `PocViewModel`'s `init`, under a comment
 * asserting one instance per launch. That is true on iOS, where `ReportModel`
 * is a `@StateObject` on the `App` struct and SwiftUI keeps it for the app's
 * lifetime. It is not true on Android, because the process outlives the
 * Activity: a ViewModel is cleared when its Activity FINISHES — Back, a swipe
 * out of the recents list, an explicit finish() — and the next launch built a
 * second one that emitted a second `app-opened` into the same session.
 *
 * Not a rotation and not backgrounding, which is worth stating because it is
 * the guess a reader makes and it is wrong. Surviving a configuration change
 * is the entire purpose of a ViewModel, and pressing Home does not destroy the
 * Activity at all. Anyone debugging this by rotating the phone will see one
 * event and conclude the write-up is mistaken.
 *
 * The duplicate was measured, not predicted: the first Android field test on
 * real hardware recorded two of them 16 minutes apart in one session, and
 * `app-opened` is the denominator of every funnel this channel exists to
 * support. Which lifecycle event caused it is the reasoned half, and the first
 * version of this paragraph got it wrong — see the two entries in
 * `data/field-tests.json`, of which the second reproduces it deliberately with
 * Back rather than with a rotation.
 */
class BorgarlandApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Fire-and-forget by contract (data/relay-events.json): telemetry must
        // never affect the report, and it must never delay startup either.
        // Telemetry.track buffers and flushes off the UI thread, so this
        // returns immediately.
        Telemetry.shared.track(TelemetryEvent.AppOpened)

        // Crashlytics initialises itself through the google-services plugin's
        // ContentProvider, so there is nothing to start here -- only something
        // to switch off. A debug build is the development loop, and its crashes
        // are ours to see in logcat, not signal to put in a dashboard that
        // exists to show what happens on somebody else's phone.
        //
        // Wrapped, because this runs before anything else the app does and an
        // SDK that has drifted must not be able to stop the app launching. That
        // is the shape of the Simaver beta35 failure, where a Firebase call in
        // onCreate crashed every launch for 26 testers.
        runCatching {
            FirebaseCrashlytics.getInstance().isCrashlyticsCollectionEnabled = !BuildConfig.DEBUG
        }
    }
}
