import Foundation
import Security

/// 32 lowercase hex characters from the system's secure random source.
///
/// One shape for every id this app generates, because the relay generates the
/// same one: a telemetry session, and since #88 a report's own id, which the
/// relay stores as the row's primary key. Sharing the function is the point —
/// two implementations of "random hex" are two chances for one of them to be
/// neither random nor hex.
public enum RandomHex {
    public static func id(bytes count: Int = 16) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "secure random is unavailable")
        return bytes.map { String(format: "%02x", Int($0)) }.joined()
    }
}
