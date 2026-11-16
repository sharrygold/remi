import AppKit
import SwiftUI

/// The Notes tab: a calm list like Apple Notes, and the editor when a note is open.
struct NotesPane: View {
    @ObservedObject var store: LibraryStore
    let density: Density
    let space: Space?
    @Binding var openNoteID: UUID?
    @Binding var filter: String
    /// Changes on ⌘F while the list is showing.
    var filterRequests: Int
    var onNewNote: () -> Void
    /// Hands focus back to the capture bar after leaving a note.
    var onClose: () -> Void
    var onConfirm: (String) -> Void
    @Environment(\.panelActions) private var actions
    @State private var hoveredNoteID: UUID?
    @FocusState private var filterFocused: Bool

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
        let all = store.notes(in: space)
        let notes = LibraryStore.filter(all, by: filter)
        let pinned = notes.filter(\.isPinned)
        let others = notes.filter { !$0.isPinned }
        VStack(spacing: 0) {
        PaneHeader(addTitle: "New note", addHelp: "New note (⌘N)", onAdd: onNewNote) {
            Text(countLabel(shown: notes.count, total: all.count))
                .font(Tokens.TextRole.detail.weight(.medium))
                .foregroundStyle(.secondary)
        }
        if !all.isEmpty { filterField(first: notes.first) }
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: density.sectionGap) {
                if all.isEmpty {
                    emptyState
                } else if notes.isEmpty {
                    Text("No notes match “\(filter)”")
                        .font(Tokens.TextRole.detail).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Tokens.Spacing.l)
                } else {
                    if !pinned.isEmpty { group("Pinned", symbol: "pin", notes: pinned) }
                    // Newest first, under headings for when each was last written in.
                    ForEach(LibraryStore.groupedByDate(others), id: \.title) { section in
                        group(section.title, symbol: "calendar", notes: section.notes)
                    }
                }
            }
            .padding(Tokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(FollowSelection(proxy: proxy))
        }
        }
    }

    private func countLabel(shown: Int, total: Int) -> String {
        let noun = total == 1 ? "note" : "notes"
        return shown == total ? "\(total) \(noun)" : "\(shown) of \(total) \(noun)"
    }

    /// Narrows the list as you type, matching words anywhere in a note. Return opens the top match;
    /// Esc clears it, then hands the keyboard back to the capture bar.
    private func filterField(first: Note?) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).accessibilityHidden(true)
            TextField("Filter notes", text: $filter)
                .brandTextInput()
                .textFieldStyle(.plain)
                .focused($filterFocused)
                .onSubmit { if let first { openNoteID = first.id } }
                .onExitCommand {
                    if filter.isEmpty { filterFocused = false; onClose() } else { filter = "" }
                }
                .accessibilityLabel("Filter notes")
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).iconTarget(22)
                }
                .buttonStyle(HoverButtonStyle(radius: 11))
                .help("Clear filter")
                .accessibilityLabel("Clear filter")
            }
        }
        .font(Tokens.TextRole.detail)
        .padding(.leading, Tokens.Spacing.s + 2)
        .padding(.trailing, Tokens.Spacing.xs)
        .frame(height: 30)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
        .padding(.horizontal, Tokens.Spacing.s + 2)
        .padding(.top, Tokens.Spacing.s)
        .onChange(of: filterRequests) { _, _ in filterFocused = true }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "note.text").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No notes here yet").font(Tokens.TextRole.sectionTitle)
            Text("Start a new note, or type below and press ⌘Return.")
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
            // Title and one quiet line under it, nothing else, so the list scans at a glance during a call.
            VStack(alignment: .leading, spacing: 3) {
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
            }
            .padding(.vertical, density.rowPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                    .fill(Color.primary.opacity(hoveredNoteID == note.id ? 0.06 : 0))
                    .padding(.horizontal, -Tokens.Spacing.s + 2)
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredNoteID = note.id } else if hoveredNoteID == note.id { hoveredNoteID = nil }
        }
        .animation(Motion.hover, value: hoveredNoteID == note.id)
        .keyboardHighlight(note.id)
        .id(note.id)
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
        ShareLink("Share…", item: NoteText.plainText(fromMarkdown: note.body))
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
            // One row, a fixed height with every control centred in it, and a hairline under it
            // so text scrolling up stops at a clear edge.
            HStack(spacing: 2) {
                Button(action: close) {
                    Label("Notes", systemImage: "chevron.left")
                        .padding(.horizontal, Tokens.Spacing.xs + 2)
                        .frame(height: Tokens.Size.iconTarget)
                }
                .buttonStyle(.hover)
                .foregroundStyle(Color.brand)
                .help("Back to notes (Esc)")
                Spacer(minLength: Tokens.Spacing.s)
                Menu {
                    ForEach(store.spaces) { space in
                        Button(space.name) { store.move(note, to: space) }.disabled(space.id == note.space?.id)
                    }
                } label: {
                    Label(note.space?.name ?? "Space", systemImage: "folder")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, Tokens.Spacing.xs + 2)
                .frame(height: Tokens.Size.iconTarget)
                .hoverHighlight()
                .help("Move to another Space")
                .accessibilityLabel("Space: \(note.space?.name ?? "none")")
                Button { NoteEditorController.current?.showFind() } label: {
                    Image(systemName: "text.magnifyingglass").iconTarget()
                }
                .buttonStyle(.hover)
                .help("Find in note (⌘F)")
                .accessibilityLabel("Find in note")
                ShareButton { NoteEditorController.current?.sharingItems ?? [NoteText.plainText(fromMarkdown: note.body)] }
                    .iconTarget()
                    .hoverHighlight()
                    .help("Share note")
                Button { store.setPinned(note, !note.isPinned) } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin").iconTarget()
                }
                .buttonStyle(.hover)
                .help(note.isPinned ? "Unpin note" : "Pin note to the top")
                .accessibilityLabel(note.isPinned ? "Unpin note" : "Pin note")
                Button { delete(note) } label: {
                    Image(systemName: "trash").iconTarget()
                }
                .buttonStyle(.hover)
                .help("Delete note (⌘Z undoes it)")
                .accessibilityLabel("Delete note")
            }
            .font(Tokens.TextRole.detail)
            .foregroundStyle(.secondary)
            .padding(.leading, Tokens.Spacing.s)
            .padding(.trailing, Tokens.Spacing.s + 2)
            .frame(height: 44)
            Divider().opacity(0.6)

            NoteEditor(note: note, store: store, onEscape: close, onOpenLink: { actions.open(.url($0)) }, onConfirm: onConfirm)
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

/// The share sheet's own button, so the picker can open beside it (Mail, Messages, AirDrop, Notes…).
struct ShareButton: NSViewRepresentable {
    let items: () -> [Any]

    func makeNSView(context: Context) -> NSButton {
        let configuration = NSImage.SymbolConfiguration(textStyle: .footnote)
        let image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share note")?.withSymbolConfiguration(configuration)
        let button = NSButton(image: image ?? NSImage(), target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel("Share note")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.items = items }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    final class Coordinator: NSObject {
        var items: () -> [Any]
        init(items: @escaping () -> [Any]) { self.items = items }

        @objc func share(_ sender: NSButton) {
            NSSharingServicePicker(items: items()).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
