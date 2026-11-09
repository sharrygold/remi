import Foundation
import SwiftData

// Every property has a default and relationships are optional, which is what CloudKit sync would need later.

@Model
final class Space {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "folder"
    var tintName: String = "work"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.space) var tasks: [TaskItem]? = []
    @Relationship(deleteRule: .nullify, inverse: \Note.space) var notes: [Note]? = []

    init(name: String, symbol: String, tintName: String, sortOrder: Int) {
        self.name = name
        self.symbol = symbol
        self.tintName = tintName
        self.sortOrder = sortOrder
    }
}

@Model
final class TaskItem {
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
final class Note {
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
