import Foundation
import SwiftData

/// Everything in the library as plain JSON: used for Export, Import and the daily backups.
/// Deleted items are included, so Recently deleted survives a restore.
struct LibraryArchive: Codable, Equatable {
    /// Neutral on purpose, so renaming the app does not break old files.
    static let format = "command-centre-library"
    var format = LibraryArchive.format
    var version = 1
    var exportedAt: Date
    var spaces: [SpaceRecord]
    var tasks: [TaskRecord]
    var notes: [NoteRecord]
    var links: [LinkRecord]

    struct SpaceRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var symbol: String
        var tintName: String
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
    }

    struct TaskRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var notes: String
        var spaceID: UUID?
        var dueDate: Date?
        var isImportant: Bool
        var isCompleted: Bool
        var completedAt: Date?
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var actionKind: String?
        var actionTarget: String?
    }

    struct NoteRecord: Codable, Equatable {
        var id: UUID
        var body: String
        var spaceID: UUID?
        var isPinned: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
    }

    struct LinkRecord: Codable, Equatable {
        var id: UUID
        var url: String
        var title: String
        var iconData: Data?
        var titleFetched: Bool
        var list: String
        var isPinned: Bool
        var isWatched: Bool
        var watchedAt: Date?
        var spaceID: UUID?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        /// Optional so archives written before renaming existed still import.
        var titleEdited: Bool? = nil
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decode(_ data: Data) throws -> LibraryArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LibraryArchive.self, from: data)
        guard archive.format == format else { throw ArchiveError.notALibrary }
        return archive
    }

    enum ArchiveError: Error {
        case notALibrary
    }
}

struct ImportSummary: Equatable {
    var added = 0
    var updated = 0
    var unchanged = 0
}

extension LibraryStore {
    private func all<Item: PersistentModel>(_ type: Item.Type) -> [Item] {
        (try? context.fetch(FetchDescriptor<Item>())) ?? []
    }

    func makeArchive(now: Date = Date()) -> LibraryArchive {
        LibraryArchive(
            exportedAt: now,
            spaces: all(Space.self).sorted { $0.sortOrder < $1.sortOrder }.map {
                .init(id: $0.id, name: $0.name, symbol: $0.symbol, tintName: $0.tintName, sortOrder: $0.sortOrder,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            tasks: all(TaskItem.self).sorted { $0.createdAt < $1.createdAt }.map {
                .init(id: $0.id, title: $0.title, notes: $0.notes, spaceID: $0.space?.id, dueDate: $0.dueDate, isImportant: $0.isImportant,
                      isCompleted: $0.isCompleted, completedAt: $0.completedAt, sortOrder: $0.sortOrder, createdAt: $0.createdAt,
                      updatedAt: $0.updatedAt, deletedAt: $0.deletedAt, actionKind: $0.actionKind, actionTarget: $0.actionTarget)
            },
            notes: all(Note.self).sorted { $0.createdAt < $1.createdAt }.map {
                .init(id: $0.id, body: $0.body, spaceID: $0.space?.id, isPinned: $0.isPinned, createdAt: $0.createdAt,
                      updatedAt: $0.updatedAt, deletedAt: $0.deletedAt)
            },
            links: all(LinkItem.self).sorted { $0.createdAt < $1.createdAt }.map {
                .init(id: $0.id, url: $0.urlString, title: $0.title, iconData: $0.iconData, titleFetched: $0.titleFetched,
                      list: $0.listName, isPinned: $0.isPinned, isWatched: $0.isWatched, watchedAt: $0.watchedAt, spaceID: $0.space?.id,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt, titleEdited: $0.titleEdited)
            }
        )
    }

    /// Merges an archive into the library. Items are matched by ID and the newer copy wins, so importing
    /// the same file twice changes nothing. Spaces are also matched by name, so a restore onto a fresh
    /// install reuses the starter Spaces instead of duplicating them. Not undoable; the app backs up first.
    @discardableResult
    func importArchive(_ archive: LibraryArchive) -> ImportSummary {
        var summary = ImportSummary()
        var spacesByID: [UUID: Space] = [:]
        let existingSpaces = all(Space.self)
        for record in archive.spaces {
            let match = existingSpaces.first { $0.id == record.id }
                ?? existingSpaces.first { CaptureParser.normalized($0.name) == CaptureParser.normalized(record.name) }
            if let match {
                if record.updatedAt > match.updatedAt {
                    match.name = record.name
                    match.symbol = record.symbol
                    match.tintName = record.tintName
                    match.updatedAt = record.updatedAt
                    summary.updated += 1
                } else {
                    summary.unchanged += 1
                }
                spacesByID[record.id] = match
            } else {
                let space = Space(name: record.name, symbol: record.symbol, tintName: record.tintName,
                                  sortOrder: (existingSpaces.map(\.sortOrder).max() ?? -1) + 1 + summary.added)
                space.id = record.id
                space.createdAt = record.createdAt
                space.updatedAt = record.updatedAt
                context.insert(space)
                spacesByID[record.id] = space
                summary.added += 1
            }
        }
        func space(_ id: UUID?) -> Space? { id.flatMap { spacesByID[$0] } ?? fallbackSpace }

        let tasksByID = Dictionary(all(TaskItem.self).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in archive.tasks {
            let task: TaskItem
            if let existing = tasksByID[record.id] {
                guard record.updatedAt > existing.updatedAt else { summary.unchanged += 1; continue }
                task = existing
                summary.updated += 1
            } else {
                task = TaskItem(title: record.title, space: nil, dueDate: nil, isImportant: false, sortOrder: 0)
                task.id = record.id
                context.insert(task)
                summary.added += 1
            }
            task.title = record.title
            task.notes = record.notes
            task.space = space(record.spaceID)
            task.dueDate = record.dueDate
            task.isImportant = record.isImportant
            task.isCompleted = record.isCompleted
            task.completedAt = record.completedAt
            task.sortOrder = record.sortOrder
            task.createdAt = record.createdAt
            task.updatedAt = record.updatedAt
            task.deletedAt = record.deletedAt
            task.actionKind = record.actionKind
            task.actionTarget = record.actionTarget
        }

        let notesByID = Dictionary(all(Note.self).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in archive.notes {
            let note: Note
            if let existing = notesByID[record.id] {
                guard record.updatedAt > existing.updatedAt else { summary.unchanged += 1; continue }
                note = existing
                summary.updated += 1
            } else {
                note = Note(body: record.body, space: nil)
                note.id = record.id
                context.insert(note)
                summary.added += 1
            }
            note.body = record.body
            note.space = space(record.spaceID)
            note.isPinned = record.isPinned
            note.createdAt = record.createdAt
            note.updatedAt = record.updatedAt
            note.deletedAt = record.deletedAt
        }

        let linksByID = Dictionary(all(LinkItem.self).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in archive.links {
            guard let url = URL(string: record.url) else { continue }
            let link: LinkItem
            if let existing = linksByID[record.id] {
                guard record.updatedAt > existing.updatedAt else { summary.unchanged += 1; continue }
                link = existing
                summary.updated += 1
            } else {
                link = LinkItem(url: url, list: .saved, space: nil)
                link.id = record.id
                context.insert(link)
                summary.added += 1
            }
            link.urlString = record.url
            link.title = record.title
            link.iconData = record.iconData
            link.titleFetched = record.titleFetched
            link.titleEdited = record.titleEdited ?? false
            link.listName = record.list
            link.isPinned = record.isPinned
            link.isWatched = record.isWatched
            link.watchedAt = record.watchedAt
            link.space = space(record.spaceID)
            link.createdAt = record.createdAt
            link.updatedAt = record.updatedAt
            link.deletedAt = record.deletedAt
        }
        save()
        reload()
        return summary
    }
}

/// A readable Markdown copy, grouped by Space. Export only; Import reads the JSON.
enum ArchiveMarkdown {
    static func render(_ archive: LibraryArchive, appName: String) -> String {
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted)
        var lines = ["# \(appName) export", "", "Exported \(archive.exportedAt.formatted(date: .long, time: .shortened)).", ""]
        let live = (
            tasks: archive.tasks.filter { $0.deletedAt == nil },
            notes: archive.notes.filter { $0.deletedAt == nil },
            links: archive.links.filter { $0.deletedAt == nil }
        )
        for space in archive.spaces {
            let tasks = live.tasks.filter { $0.spaceID == space.id }.sorted { $0.sortOrder < $1.sortOrder }
            let notes = live.notes.filter { $0.spaceID == space.id }.sorted { $0.updatedAt > $1.updatedAt }
            let links = live.links.filter { $0.spaceID == space.id }.sorted { $0.createdAt > $1.createdAt }
            guard !(tasks.isEmpty && notes.isEmpty && links.isEmpty) else { continue }
            lines += ["## \(space.name)", ""]
            if !tasks.isEmpty {
                lines += ["### Tasks", ""]
                for task in tasks {
                    var line = "- [\(task.isCompleted ? "x" : " ")] \(task.title)"
                    if task.isImportant { line += " (important)" }
                    if let due = task.dueDate { line += " · due \(due.formatted(day))" }
                    if task.actionKind == "url", let target = task.actionTarget { line += " · \(target)" }
                    lines.append(line)
                }
                lines.append("")
            }
            if !notes.isEmpty {
                lines += ["### Notes", ""]
                for note in notes {
                    let title = NoteText.title(of: note.body)
                    lines += ["#### \(title.isEmpty ? "Untitled" : title)\(note.isPinned ? " (pinned)" : "")", ""]
                    // The first line is already the heading.
                    let rest = note.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().joined()
                    let body = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty { lines += [body, ""] }
                }
            }
            for list in LinkList.allCases {
                let inList = links.filter { $0.list == list.rawValue }
                guard !inList.isEmpty else { continue }
                lines += ["### \(list.title)", ""]
                for link in inList {
                    lines.append("- [\(link.title.replacingOccurrences(of: "]", with: ")"))](\(link.url))\(link.isWatched ? " (watched)" : "")")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
