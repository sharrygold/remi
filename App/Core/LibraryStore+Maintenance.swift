import Foundation
import SwiftData

/// Something in Recently deleted.
enum DeletedItem: Identifiable {
    case task(TaskItem)
    case note(Note)
    case link(LinkItem)

    var id: UUID {
        switch self {
        case .task(let task): task.id
        case .note(let note): note.id
        case .link(let link): link.id
        }
    }

    var title: String {
        switch self {
        case .task(let task): task.title
        case .note(let note): note.title.isEmpty ? "Untitled note" : note.title
        case .link(let link): link.title
        }
    }

    var kind: String {
        switch self {
        case .task: "Task"
        case .note: "Note"
        case .link: "Link"
        }
    }

    var deletedAt: Date {
        switch self {
        case .task(let task): task.deletedAt ?? .distantPast
        case .note(let note): note.deletedAt ?? .distantPast
        case .link(let link): link.deletedAt ?? .distantPast
        }
    }

    var spaceName: String? {
        switch self {
        case .task(let task): task.space?.name
        case .note(let note): note.space?.name
        case .link(let link): link.space?.name
        }
    }
}

extension LibraryStore {
    static let keepDeletedDays = 30

    // MARK: Recently deleted

    func deletedItems() -> [DeletedItem] {
        let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { $0.deletedAt != nil }.map(DeletedItem.task)
        let notes = ((try? context.fetch(FetchDescriptor<Note>())) ?? []).filter { $0.deletedAt != nil }.map(DeletedItem.note)
        let links = ((try? context.fetch(FetchDescriptor<LinkItem>())) ?? []).filter { $0.deletedAt != nil }.map(DeletedItem.link)
        return (tasks + notes + links).sorted { $0.deletedAt > $1.deletedAt }
    }

    func restore(_ item: DeletedItem) {
        switch item {
        case .task(let task): task.deletedAt = nil; task.updatedAt = Date()
        case .note(let note): note.deletedAt = nil
        case .link(let link): link.deletedAt = nil; link.updatedAt = Date()
        }
        save()
        reload()
    }

    func deleteForever(_ item: DeletedItem) {
        switch item {
        case .task(let task): context.delete(task)
        case .note(let note): context.delete(note)
        case .link(let link): context.delete(link)
        }
        save()
        reload()
    }

    /// Removes for good anything deleted more than 30 days ago. Run at launch and each new day.
    @discardableResult
    func purgeDeleted(now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-Double(Self.keepDeletedDays) * 86_400)
        let old = deletedItems().filter { $0.deletedAt < cutoff }
        for item in old {
            switch item {
            case .task(let task): context.delete(task)
            case .note(let note): context.delete(note)
            case .link(let link): context.delete(link)
            }
        }
        if !old.isEmpty {
            save()
            reload()
        }
        return old.count
    }

    // MARK: Spaces (from Settings; not on the panel's undo stack)

    static let spaceSymbols = ["briefcase", "building.2", "house", "book", "magnifyingglass", "folder", "star", "leaf", "flag", "bolt",
                               "heart", "graduationcap", "dumbbell", "cart", "airplane", "paintbrush", "music.note", "camera",
                               "laptopcomputer", "chart.bar", "person.2", "sparkles", "lightbulb", "globe"]
    static let spaceTints = ["work", "clients", "personal", "learning", "homeReno"]

    @discardableResult
    func addSpace(named name: String) -> Space? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !spaces.contains(where: { CaptureParser.normalized($0.name) == CaptureParser.normalized(cleaned) }) else {
            return nil
        }
        let space = resolveSpace(.new(cleaned), currentSpace: nil).space
        save()
        reload()
        return space
    }

    /// Refuses names already used by another Space, since `#name` must point to one place.
    @discardableResult
    func rename(_ space: Space, to name: String) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !spaces.contains(where: {
            $0.id != space.id && CaptureParser.normalized($0.name) == CaptureParser.normalized(cleaned)
        }) else { return false }
        space.name = cleaned
        space.updatedAt = Date()
        save()
        reload()
        return true
    }

    func setLook(_ space: Space, symbol: String? = nil, tint: String? = nil) {
        if let symbol { space.symbol = symbol }
        if let tint { space.tintName = tint }
        space.updatedAt = Date()
        save()
        reload()
    }

    func reorderSpaces(_ ordered: [Space]) {
        for (index, space) in ordered.enumerated() { space.sortOrder = index }
        save()
        reload()
    }

    /// Moves everything in the Space, deleted items included, to `target`, then removes the Space.
    func deleteSpace(_ space: Space, movingItemsTo target: Space) {
        guard space.id != target.id, spaces.count > 1 else { return }
        for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] where task.space?.id == space.id { task.space = target }
        for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] where note.space?.id == space.id { note.space = target }
        for link in (try? context.fetch(FetchDescriptor<LinkItem>())) ?? [] where link.space?.id == space.id { link.space = target }
        context.delete(space)
        // Undo entries may point at the removed Space.
        clearUndo()
        save()
        reload()
    }

    func itemCount(in space: Space) -> Int {
        tasks.filter { $0.space?.id == space.id }.count + notes.filter { $0.space?.id == space.id }.count
            + links.filter { $0.space?.id == space.id }.count
    }
}
