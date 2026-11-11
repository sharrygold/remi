import Foundation
import SwiftData

// Every property has a default and relationships are optional, which is what CloudKit sync would need later.

@Model
final class Space: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "folder"
    var tintName: String = "work"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.space) var tasks: [TaskItem]? = []
    @Relationship(deleteRule: .nullify, inverse: \Note.space) var notes: [Note]? = []
    @Relationship(deleteRule: .nullify, inverse: \LinkItem.space) var links: [LinkItem]? = []

    init(name: String, symbol: String, tintName: String, sortOrder: Int) {
        self.name = name
        self.symbol = symbol
        self.tintName = tintName
        self.sortOrder = sortOrder
    }
}

@Model
final class TaskItem: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var space: Space?
    var dueDate: Date?
    var isImportant: Bool = false
    var isCompleted: Bool = false
    var completedAt: Date?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    /// The optional doorway, stored as two plain fields so the model stays sync-friendly. Use `action`.
    var actionKind: String?
    var actionTarget: String?
    /// "daily", "weekdays", "weekly" or "monthly"; nil for a one-off task. Use `repeatRule`.
    var repeatName: String?
    /// The first date missed since the task was last done. Two weeks of misses pauses it.
    var skippedSince: Date?
    /// A repeating task left alone for two weeks: hidden until the morning review asks about it.
    var isPaused: Bool = false
    /// Let go in the morning review or a fresh start: out of the lists, still searchable, never deleted.
    var setAsideAt: Date?

    init(title: String, space: Space?, dueDate: Date?, isImportant: Bool, sortOrder: Int) {
        self.title = title
        self.space = space
        self.dueDate = dueDate
        self.isImportant = isImportant
        self.sortOrder = sortOrder
    }
}

/// The body is stored as plain Markdown, so export and future sync never depend on the editor.
@Model
final class Note: Identifiable {
    var id: UUID = UUID()
    var body: String = ""
    var space: Space?
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(body: String, space: Space?) {
        self.body = body
        self.space = space
    }

    var title: String { NoteText.title(of: body) }
    var preview: String { NoteText.preview(of: body) }
}

/// Something a task can open in one click.
enum ItemAction: Equatable {
    case url(URL)
    case app(URL)
    case file(URL)

    var kind: String {
        switch self {
        case .url: "url"
        case .app: "app"
        case .file: "file"
        }
    }

    var target: URL {
        switch self {
        case .url(let url), .app(let url), .file(let url): url
        }
    }

    /// A short name for menus and VoiceOver: the site, the app or the file name.
    var label: String {
        switch self {
        case .url(let url): LinkClassifier.displayHost(url)
        case .app(let url): url.deletingPathExtension().lastPathComponent
        case .file(let url): url.lastPathComponent
        }
    }
}

extension TaskItem {
    var action: ItemAction? {
        get {
            guard let kind = actionKind, let target = actionTarget else { return nil }
            switch kind {
            case "url": return URL(string: target).map(ItemAction.url)
            case "app": return .app(URL(fileURLWithPath: target))
            case "file": return .file(URL(fileURLWithPath: target))
            default: return nil
            }
        }
        set {
            actionKind = newValue?.kind
            switch newValue {
            case .url(let url): actionTarget = url.absoluteString
            case .app(let url), .file(let url): actionTarget = url.path
            case nil: actionTarget = nil
            }
        }
    }
}

enum LinkList: String, CaseIterable {
    case saved, watchLater

    var title: String { self == .saved ? "Saved links" : "Watch later" }
    var symbol: String { self == .saved ? "bookmark" : "play.rectangle" }
}

/// A list of links you named yourself, alongside Saved links and Watch later.
@Model
final class LinkGroup: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

@Model
final class LinkItem: Identifiable {
    var id: UUID = UUID()
    var urlString: String = ""
    /// The page title once fetched; until then, the site name.
    var title: String = ""
    var iconData: Data?
    var titleFetched: Bool = false
    /// Set when you rename the link, so a later page fetch keeps your name.
    var titleEdited: Bool = false
    var listName: String = LinkList.saved.rawValue
    /// The custom list it lives in; nil for Saved links and Watch later.
    var groupID: UUID?
    var isPinned: Bool = false
    var isWatched: Bool = false
    var watchedAt: Date?
    var space: Space?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(url: URL, list: LinkList, space: Space?) {
        urlString = url.absoluteString
        title = LinkClassifier.displayHost(url)
        listName = list.rawValue
        self.space = space
    }

    var url: URL? { URL(string: urlString) }
    var list: LinkList {
        get { LinkList(rawValue: listName) ?? .saved }
        set { listName = newValue.rawValue }
    }
    var domain: String { url.map(LinkClassifier.displayHost) ?? urlString }
}
