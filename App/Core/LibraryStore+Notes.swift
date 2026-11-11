import Foundation
import SwiftData

extension LibraryStore {
    /// Pinned first, then most recently edited, like Apple Notes.
    func notes(in space: Space?) -> [Note] {
        notes.filter { space == nil || $0.space?.id == space?.id }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// The heading a note sits under, by when it was last written in, like Apple Notes.
    static func dateGroup(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2...7: return "Previous 7 Days"
        case 8...30: return "Previous 30 Days"
        default: return "Earlier"
        }
    }

    /// Notes split under those headings, newest first, keeping their order within each.
    static func groupedByDate(_ notes: [Note], now: Date = Date(), calendar: Calendar = .current) -> [(title: String, notes: [Note])] {
        var groups: [(title: String, notes: [Note])] = []
        for note in notes {
            let title = dateGroup(for: note.updatedAt, now: now, calendar: calendar)
            if groups.last?.title == title { groups[groups.count - 1].notes.append(note) } else { groups.append((title, [note])) }
        }
        return groups
    }

    /// ⌘Return in the capture bar. Only `#space` is read; words like "today" stay in the note.
    @discardableResult
    func addNote(fromCapture text: String, currentSpace: Space?) -> Note? {
        let parsed = CaptureParser.parse(text, spaceNames: spaces.map(\.name))
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if parsed.space != .none, let index = words.firstIndex(where: { $0.hasPrefix("#") && $0.count > 1 }) {
            words.remove(at: index)
        }
        let body = words.joined(separator: " ")
        guard !body.isEmpty else { return nil }
        let (space, createdSpace) = resolveSpace(parsed.space, currentSpace: currentSpace)
        let note = Note(body: body, space: space)
        context.insert(note)
        commit { [context] in
            context.delete(note)
            if let createdSpace { context.delete(createdSpace) }
        }
        return note
    }

    /// A blank note for the editor. It is not undoable, and it disappears if left empty.
    func newNote(in space: Space?) -> Note {
        let note = Note(body: "", space: space ?? fallbackSpace)
        context.insert(note)
        save()
        reload()
        return note
    }

    /// Typing goes straight to the note and is saved after a pause; the editor has its own undo.
    func setBody(_ note: Note, _ body: String, now: Date = Date()) {
        guard note.body != body else { return }
        note.body = body
        note.updatedAt = now
        scheduleSave()
    }

    /// Called when the editor closes: a note left empty is removed for good, not sent to Recently deleted.
    func finishEditing(_ note: Note) {
        if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.deletedAt == nil {
            context.delete(note)
        }
        save()
        reload()
    }

    /// A note opened and left blank before a quit would otherwise linger as an empty row.
    func removeBlankNotes() {
        let all = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        for note in all where note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.delete(note)
        }
        save()
    }

    private func change(_ note: Note, _ apply: (Note) -> Void, undo: @escaping (Note) -> Void) {
        apply(note)
        commit { undo(note) }
    }

    /// Pinning does not count as an edit, so the note keeps its place among the others.
    func setPinned(_ note: Note, _ pinned: Bool) {
        let previous = note.isPinned
        change(note, { $0.isPinned = pinned }, undo: { $0.isPinned = previous })
    }

    func move(_ note: Note, to space: Space) {
        let previous = note.space
        change(note, { $0.space = space }, undo: { $0.space = previous })
    }

    /// Moves to Recently deleted; permanent removal arrives in M5.
    func delete(_ note: Note, now: Date = Date()) {
        change(note, { $0.deletedAt = now }, undo: { $0.deletedAt = nil })
    }
}
