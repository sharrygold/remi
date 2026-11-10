import SwiftUI

/// ⌘F search state, shared with the app so arrow keys can move the selection.
final class SearchState: ObservableObject {
    @Published var active = false
    @Published var query = ""
    @Published var selection = 0
    /// Bumped by ⌘F; the panel answers by showing and focusing the search field.
    @Published var requests = 0
    var isFocused = false
    var resultCount = 0
}

enum SearchHit: Identifiable {
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

    static func flatten(_ results: SearchResults) -> [SearchHit] {
        results.tasks.map(SearchHit.task) + results.notes.map(SearchHit.note) + results.links.map(SearchHit.link)
    }
}

/// Results grouped by type, moved through with ↑ ↓, opened with Return or a click.
struct SearchPane: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var search: SearchState
    let density: Density
    var onOpen: (SearchHit) -> Void
    var onClose: () -> Void
    @FocusState private var focused: Bool

    private var results: SearchResults { store.search(search.query) }

    var body: some View {
        let results = results
        let hits = SearchHit.flatten(results)
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search tasks, notes and links", text: $search.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        guard hits.indices.contains(search.selection) else { return }
                        onOpen(hits[search.selection])
                    }
                    .accessibilityLabel("Search")
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .help("Close search (Esc)")
                    .accessibilityLabel("Close search")
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .frame(height: 40)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: density.sectionGap) {
                        if search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                            hint("Type to search every Space", detail: "↑ ↓ to move, Return to open, Esc to go back.")
                        } else if hits.isEmpty {
                            hint("No matches", detail: "Try fewer words, or check the spelling.")
                        } else {
                            group("Tasks", hits: hits, results.tasks.count, offset: 0)
                            group("Notes", hits: hits, results.notes.count, offset: results.tasks.count)
                            group("Links", hits: hits, results.links.count, offset: results.tasks.count + results.notes.count)
                        }
                    }
                    .padding(Tokens.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: search.selection) { _, index in
                    guard hits.indices.contains(index) else { return }
                    withAnimation(Tokens.Motion.quick) { proxy.scrollTo(hits[index].id) }
                }
            }
        }
        .onAppear { focused = true }
        .onChange(of: search.requests) { _, _ in focused = true }
        .onChange(of: focused) { _, value in search.isFocused = value }
        .onChange(of: search.query) { _, _ in search.selection = 0 }
        .onChange(of: hits.count, initial: true) { _, count in search.resultCount = count }
    }

    private func hint(_ title: String, detail: String) -> some View {
        VStack(spacing: Tokens.Spacing.s) {
            Text(title).font(Tokens.TextRole.sectionTitle)
            Text(detail).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.l * 2)
    }

    @ViewBuilder private func group(_ title: String, hits: [SearchHit], _ count: Int, offset: Int) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Tokens.TextRole.sectionTitle).foregroundStyle(.secondary).padding(.bottom, Tokens.Spacing.xs)
                ForEach(offset..<(offset + count), id: \.self) { index in
                    row(hits[index], selected: index == search.selection)
                        .id(hits[index].id)
                        .onTapGesture { onOpen(hits[index]) }
                }
            }
        }
    }

    private func row(_ hit: SearchHit, selected: Bool) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            switch hit {
            case .task(let task):
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(.tertiary)
                    .frame(width: 20)
                text(task.title, detail: [task.space?.name, task.dueDate.map { DueLabel.text(for: $0) }].compactMap { $0 }.joined(separator: " · "))
            case .note(let note):
                Image(systemName: "note.text").foregroundStyle(.secondary).frame(width: 20)
                text(note.title.isEmpty ? "New Note" : note.title, detail: [note.space?.name, note.preview].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " · "))
            case .link(let link):
                LinkIcon(data: link.iconData, fallback: link.list == .watchLater ? "play.rectangle.fill" : "globe")
                text(link.title, detail: [link.domain, link.space?.name].compactMap { $0 }.joined(separator: " · "))
            }
            Spacer(minLength: 0)
            if selected { Text("↩").font(Tokens.TextRole.detail).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, Tokens.Spacing.s)
        .padding(.vertical, density.rowPadding)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func text(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Tokens.TextRole.row).lineLimit(1)
            if !detail.isEmpty {
                Text(detail).font(Tokens.TextRole.detail).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
