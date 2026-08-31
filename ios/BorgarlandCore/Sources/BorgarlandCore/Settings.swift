import Foundation

/// The device's preferences for the app, kept beside the address (#179). One
/// value today: whether a captured photograph is also saved to the device
/// gallery.
///
/// Default ON, deliberately: the surprising behaviour was the one that kept
/// nothing, and a person who does not want the picture kept can turn the
/// toggle off — while a person who wanted it and did not know to ask has
/// already lost it.
///
/// This file never leaves the device and is not part of a report: the relay
/// learns nothing about it, and nothing here may enter
/// `data/relay-request.json`.
public struct Settings {

    /// The default is the decision: save, unless the person says otherwise.
    public static let defaultSaveToGallery = true

    private let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// Beside the queue and the address, in Application Support: a preference
    /// is not a cache, and the system deletes Caches under disk pressure.
    /// Falls back to the temporary directory for the same reason
    /// `ContactDetails.applicationDefault` does.
    public static func applicationDefault(fileManager: FileManager = .default) -> Settings {
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = support ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return Settings(
            url: base.appendingPathComponent("settings.json"),
            fileManager: fileManager
        )
    }

    private struct Stored: Codable {
        let saveToGallery: Bool
    }

    /// Whether a captured photograph should also land in the gallery. A
    /// missing file or an unreadable one is the default, never a reason to
    /// stop saving: the app was installed moments ago, and the person has not
    /// said otherwise.
    public func saveToGallery() -> Bool {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return Self.defaultSaveToGallery
        }
        return stored.saveToGallery
    }

    /// Returns whether the write landed. A failure costs the person a
    /// preference they have to re-state; the save path keeps its own default.
    @discardableResult
    public func setSaveToGallery(_ save: Bool) -> Bool {
        guard let data = try? JSONEncoder().encode(Stored(saveToGallery: save)) else { return false }
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
