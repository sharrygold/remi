import Foundation

/// One JSON backup a day in Application Support, keeping the newest 14.
enum Backups {
    static let keep = 14
    private static let prefix = "Backup "

    static func directory(in libraryDirectory: URL) -> URL {
        libraryDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%@%04d-%02d-%02d.json", prefix, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The backups present, newest first.
    static func list(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Writes today's backup if there isn't one yet, then removes the oldest beyond `keep`.
    /// `force` writes even when today's exists, used just before an import.
    @discardableResult
    static func backUp(_ archive: () -> LibraryArchive, to directory: URL, now: Date = Date(), force: Bool = false) throws -> URL? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(fileName(for: now))
        if FileManager.default.fileExists(atPath: file.path), !force { return nil }
        try LibraryArchive.encoder().encode(archive()).write(to: file, options: .atomic)
        for old in list(in: directory).dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
        return file
    }
}
