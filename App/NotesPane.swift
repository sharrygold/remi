import SwiftUI

/// The Notes tab: a calm list like Apple Notes, and the editor when a note is open.
struct NotesPane: View {
    @ObservedObject var store: LibraryStore
    let density: Density
    let space: Space?
    /// True for "All", where each row names its Space.
    let showsSpace: Bool
    @Binding var openNoteID: UUID?
    var onNewNote: () -> Void
    /// Hands focus back to the capture bar after leaving a note.
    var onClose: () -> Void
    var onConfirm: (String) -> Void

    private var openNote: Note? { store.notes.first { $0.id == openNoteID } }

    var body: some View {
        if let note = openNote {
            editor(note)
        } else {
            list
        }
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        let notes = store.notes(in: space)
        let pinned = notes.filter(\.isPinned)
        let others = notes.filter { !$0.isPinned }
        ScrollView {
            VStack(alignment: .leading, spacing: density.sectionGap) {
                Button(action: onNewNote) {
                    Label("New Note", systemImage: "square.and.pencil")
                        .font(Tokens.TextRole.meta)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New note (⌘N)")

                if notes.isEmpty {
                    emptyState
                } else {
                    if !pinned.isEmpty { group("Pinned", symbol: "pin", notes: pinned) }
                    if !others.isEmpty { group(pinned.isEmpty ? nil : "Notes", symbol: "note.text", notes: others) }
                }
            }
            .padding(Tokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "note.text").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No notes here yet").font(Tokens.TextRole.sectionTitle)
            Text("Type above and press ⌘Return, or start a new note.")
                .font(Tokens.TextRole.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.l * 2)
    }

    private func group(_ title: String?, symbol: String, notes: [Note]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Label(title, systemImage: symbol).font(Tokens.TextRole.sectionTitle).foregroundStyle(.secondary)
                    .padding(.bottom, Tokens.Spacing.xs)
            }
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                if index > 0 { Divider() }
                row(note)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        Button { openNoteID = note.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Tokens.Spacing.xs) {
                    Text(note.title.isEmpty ? "New Note" : note.title)
                        .font(Tokens.TextRole.row.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: Tokens.Spacing.s)
                    if note.isPinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tertiary).accessibilityLabel("Pinned")
                    }
                }
                HStack(spacing: Tokens.Spacing.s) {
                    Text(NoteDate.text(for: note.updatedAt)).foregroundStyle(.secondary)
                    Text(note.preview.isEmpty ? "No additional text" : note.preview)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .font(Tokens.TextRole.detail)
                if showsSpace, let space = note.space {
                    Label(space.name, systemImage: space.symbol)
                        .font(Tokens.TextRole.detail)
                        .foregroundStyle(space.tint)
                }
            }
            .padding(.vertical, density.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the note")
        .contextMenu { menu(for: note) }
    }

    @ViewBuilder private func menu(for note: Note) -> some View {
        Button(note.isPinned ? "Unpin" : "Pin") { store.setPinned(note, !note.isPinned) }
        Menu("Move to") {
            ForEach(store.spaces) { space in
                Button(space.name) { store.move(note, to: space) }.disabled(space.id == note.space?.id)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { delete(note) }
    }

    private func delete(_ note: Note) {
        if openNoteID == note.id { openNoteID = nil }
        store.delete(note)
        onConfirm("Note deleted  ·  ⌘Z to undo")
    }

    // MARK: Editor

    private func editor(_ note: Note) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Spacing.m) {
                Button(action: close) {
                    Label("Notes", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Back to notes (Esc)")
                Spacer()
                Menu {
                    ForEach(store.spaces) { space in
                        Button(space.name) { store.move(note, to: space) }.disabled(space.id == note.space?.id)
                    }
                } label: {
                    Label(note.space?.name ?? "Space", systemImage: note.space?.symbol ?? "folder")
                        .foregroundStyle(note.space?.tint ?? .secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Space: \(note.space?.name ?? "none")")
                Button { store.setPinned(note, !note.isPinned) } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.isPinned ? "Unpin note" : "Pin note")
                Button { delete(note) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete note")
            }
            .font(Tokens.TextRole.detail)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.top, Tokens.Spacing.s + Tokens.Spacing.xs)

            NoteEditor(note: note, store: store, onEscape: close)
                .id(note.id)
        }
    }

    private func close() {
        if let note = openNote { store.finishEditing(note) }
        openNoteID = nil
        onClose()
    }
}

enum NoteDate {
    /// A time for today, a weekday this week, otherwise a short date, as Apple Notes does.
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day {
            if days == 1 { return "Yesterday" }
            if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
