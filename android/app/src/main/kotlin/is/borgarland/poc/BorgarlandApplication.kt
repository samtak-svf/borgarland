package `is`.borgarland.poc

import android.app.Application
import `is`.borgarland.poc.net.Telemetry
import `is`.borgarland.poc.net.TelemetryEvent

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
 * lifetime. It is not true on Android: the process outlives the Activity, so
 * backgrounding the app or rotating the phone destroys the ViewModel and the
 * next construction emitted a second `app-opened` into the same session.
 *
 * That was measured rather than reasoned about — the first Android field test
 * on real hardware recorded two of them 16 minutes apart in one session, and
 * `app-opened` is the denominator of every funnel this channel exists to
 * support. See `data/field-tests.json`, entry `2026-08-23-android-first-walk`.
 */
class BorgarlandApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Fire-and-forget by contract (data/relay-events.json): telemetry must
        // never affect the report, and it must never delay startup either.
        // Telemetry.track buffers and flushes off the UI thread, so this
        // returns immediately.
        Telemetry.shared.track(TelemetryEvent.AppOpened)
    }
}
