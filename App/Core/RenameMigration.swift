import Foundation

/// The app was called Perch, with the bundle ID below. On the first installed launch under the new
/// identity, its data and settings are copied across. The old copies are left exactly as they were.
enum RenameMigration {
    static let oldBundleID = "com.example.oldapp"
    static let doneKey = "migratedFromPerch"
    /// Written by the last Perch build as it removed its own login item.
    static let loginItemKey = "loginItemWasEnabled"

    /// Copies the library folder if the new location has no library yet. Returns true if it copied.
    @discardableResult
    static func copyLibrary(support: URL, fromID old: String, toID new: String, fileManager: FileManager = .default) throws -> Bool {
        let source = support.appendingPathComponent(old, isDirectory: true)
        let destination = support.appendingPathComponent(new, isDirectory: true)
        guard fileManager.fileExists(atPath: source.appendingPathComponent("Library.store").path),
              !fileManager.fileExists(atPath: destination.appendingPathComponent("Library.store").path) else { return false }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path) { try fileManager.copyItem(at: item, to: target) }
        }
        return true
    }

    /// The settings to carry over, renamed where the key changed. The old companion colours are
    /// left behind on purpose, so everyone starts on the default Plumage.
    static func migratedDefaults(from old: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in old where !key.hasPrefix("NS") && !key.hasPrefix("com.apple.") {
            switch key {
            case "debug.widgetColour", loginItemKey:
                continue
            case "debug.widgetPrototype":
                // Pebble is retired; anyone on it moves to Perched.
                result[CompanionKeys.style] = (value as? String) == "cord" ? "cord" : "bird"
            default:
                result[key] = value
            }
        }
        return result
    }
}

/// Stored setting names for the companion, shared with the migration above.
enum CompanionKeys {
    static let style = "companionStyle"
    static let plumage = "plumage"
}
