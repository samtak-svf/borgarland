import Foundation

/// The two decisions the walk turns on, out of the screens and into a place
/// that has tests.
///
/// #89: everything added after the first field test had tests except the part
/// the defects were actually in. The telemetry channel, the queue and the
/// outcome mapping each got a dedicated test class, while the logic those fixes
/// exist for lived in `ReportModel` and `PocViewModel` — neither of which has a
/// test target at all, so a revert of #73 or #76 left every test green.
///
/// These two functions are what those fixes are ABOUT, expressed without a
/// screen, an actor or a platform API in sight. What is still not pinned by
/// them is the wiring: that the screens call these, and call them with the
/// right arguments. Extracting the decision does not test the caller, and the
/// PR that adds this says so rather than implying otherwise.

/// What the relay's answer means for a report that is waiting.
public enum RelayDisposition: Equatable {
    /// The relay took it. Nothing more is owed.
    case sent
    /// The relay read it and refused it. The same bytes would be refused again,
    /// so it stops waiting.
    case refused
    /// Nobody answered, or the relay asked us to come back. Keep it.
    case waiting

    /// `ok` is the relay's own judgement and is trusted. Below it, the split is
    /// between an answer that would be the same next time and no answer at all:
    /// 0 is the transports' shared convention for "nothing answered", and 408
    /// and 429 are the two 4xx that mean try later rather than never.
    public static func of(status: Int, ok: Bool) -> RelayDisposition {
        if ok { return .sent }
        switch status {
        case 0, 408, 429:
            return .waiting
        case 400..<500:
            return .refused
        default:
            // A 5xx is the relay having a bad moment, not a bad report.
            return .waiting
        }
    }
}

/// Where a location permission stands, which is not the same question as
/// whether it is granted.
public enum LocationPermission: Equatable {
    case granted
    /// Nobody has answered yet. Asking again can still work.
    case unanswered
    /// Refused, and the system will not ask again. Only the settings app can
    /// change it.
    case deniedForGood

    /// `canAskAgain` is the platform's answer to a question this type cannot
    /// ask: iOS reads it from `authorizationStatus`, Android from
    /// `shouldShowRequestPermissionRationale` AFTER the launcher has answered.
    public static func of(granted: Bool, canAskAgain: Bool) -> LocationPermission {
        if granted { return .granted }
        return canAskAgain ? .unanswered : .deniedForGood
    }

    /// What the screen must offer. Offering a retry on `deniedForGood` is #76:
    /// the field test pressed it and got the same refusal, twice, ten seconds
    /// apart.
    public enum Exit: Equatable {
        case carryOn
        case askAgain
        case openSystemSettings
    }

    public var exit: Exit {
        switch self {
        case .granted: return .carryOn
        case .unanswered: return .askAgain
        case .deniedForGood: return .openSystemSettings
        }
    }

    /// Whether coming back to the app should carry the walk on from where it
    /// stopped. Only when it stopped for THIS reason and the reason is gone:
    /// resuming on every return would restart the location step under somebody
    /// who had moved on.
    public static func shouldResume(after stopped: LocationPermission, nowGranted: Bool) -> Bool {
        stopped == .deniedForGood && nowGranted
    }
}
