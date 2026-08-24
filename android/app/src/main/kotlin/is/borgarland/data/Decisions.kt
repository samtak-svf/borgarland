package `is`.borgarland.data

// The two decisions the walk turns on, out of the screens and into a place that
// has tests. The Swift counterpart is BorgarlandCore/Decisions.swift.
//
// #89: everything added after the first field test had tests except the part
// the defects were actually in. The telemetry channel and the outcome mapping
// each got a dedicated test class, while the logic those fixes exist for lived
// in `PocViewModel`, which needs an Application and therefore has no plain JVM
// test at all — so a revert of #76 left every test green.
//
// What is still not pinned here is the wiring: that the screens call these, and
// call them with the right arguments. Extracting the decision does not test the
// caller.

/** What the relay's answer means for a report. */
enum class RelayDisposition {
    /** The relay took it. */
    SENT,

    /** The relay read it and refused it; the same bytes would be refused again. */
    REFUSED,

    /** Nobody answered, or the relay asked us to come back. */
    WAITING,

    ;

    companion object {
        /**
         * [ok] is the relay's own judgement and is trusted. Below it, the split
         * is between an answer that would be the same next time and no answer
         * at all: 0 is the transports' shared convention for "nothing
         * answered", and 408 and 429 are the two 4xx that mean try later rather
         * than never.
         */
        fun of(status: Int, ok: Boolean): RelayDisposition = when {
            ok -> SENT
            status == 0 || status == 408 || status == 429 -> WAITING
            // A 5xx is the relay having a bad moment, not a bad report.
            status in 400..499 -> REFUSED
            else -> WAITING
        }
    }
}

/**
 * Where a location permission stands, which is not the same question as whether
 * it is granted.
 */
enum class LocationPermission {
    GRANTED,

    /** Nobody has answered yet. Asking again can still work. */
    UNANSWERED,

    /**
     * Refused, and the system will not ask again. Only app settings can change
     * it.
     */
    DENIED_FOR_GOOD,

    ;

    /** What the screen must offer. */
    enum class Exit { CARRY_ON, ASK_AGAIN, OPEN_SYSTEM_SETTINGS }

    /**
     * Offering a retry on [DENIED_FOR_GOOD] is #76: the field test pressed it
     * and got the same refusal, twice, ten seconds apart.
     */
    val exit: Exit
        get() = when (this) {
            GRANTED -> Exit.CARRY_ON
            UNANSWERED -> Exit.ASK_AGAIN
            DENIED_FOR_GOOD -> Exit.OPEN_SYSTEM_SETTINGS
        }

    companion object {
        /**
         * [canAskAgain] is the platform's answer to a question this type cannot
         * ask: Android reads it from shouldShowRequestPermissionRationale AFTER
         * the launcher has answered, iOS from authorizationStatus.
         */
        fun of(granted: Boolean, canAskAgain: Boolean): LocationPermission = when {
            granted -> GRANTED
            canAskAgain -> UNANSWERED
            else -> DENIED_FOR_GOOD
        }

        /**
         * Whether coming back to the app should carry the walk on from where it
         * stopped. Only when it stopped for THIS reason and the reason is gone:
         * resuming on every return would restart the location step under
         * somebody who had moved on.
         */
        fun shouldResume(stopped: LocationPermission, nowGranted: Boolean): Boolean =
            stopped == DENIED_FOR_GOOD && nowGranted
    }
}
