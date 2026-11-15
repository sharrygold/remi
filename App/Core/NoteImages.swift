import Foundation
import SwiftData

/// Images in notes. A note's Markdown holds `![image](remi-image:NAME)` and the picture itself is a
/// file called NAME in the library's Note Images folder, so notes stay small and quick to save.
enum NoteImages {
    static let scheme = "remi-image"
    static let folderName = "Note Images"
    private static let pattern = try! NSRegularExpression(pattern: #"!\[[^\]\n]*\]\(remi-image:([A-Za-z0-9._-]+)\)"#)

    static func markdown(for name: String) -> String { "![image](\(scheme):\(name))" }

    /// Each reference in order: where it is in `text` and the file name it points to.
    static func references(in text: String) -> [(range: NSRange, name: String)] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ($0.range, ns.substring(with: $0.range(at: 1)))
        }
    }

    static func names(in text: String) -> [String] { references(in: text).map(\.name) }

    static func removingReferences(from text: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }

    /// The same rules for any folder, so tests can use a temporary one.
    /// Removes image files no note refers to, including notes in Recently Deleted. Files younger than
    /// `minimumAge` stay, so an image undone a moment ago can still be redone.
    @discardableResult
    static func purgeUnused(in folder: URL, keeping referenced: Set<String>, minimumAge: TimeInterval = 86_400, now: Date = Date()) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var removed = 0
        for file in files where !referenced.contains(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            guard now.timeIntervalSince(modified) >= minimumAge else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }
}

extension LibraryStore {
    /// Next to the library; an in-memory library gets a folder of its own in temporary items.
    var noteImagesFolder: URL {
        let folder = directory?.appendingPathComponent(NoteImages.folderName, isDirectory: true) ?? Self.scratchImagesFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static let scratchImagesFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("note-images-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    func noteImageURL(_ name: String) -> URL { noteImagesFolder.appendingPathComponent(name) }

    /// Every image any note uses, Recently Deleted included.
    func referencedNoteImages() -> Set<String> {
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        return Set(notes.flatMap { NoteImages.names(in: $0.body) })
    }

    @discardableResult
    func purgeUnusedNoteImages(now: Date = Date()) -> Int {
        NoteImages.purgeUnused(in: noteImagesFolder, keeping: referencedNoteImages(), now: now)
    }
}
