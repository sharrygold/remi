import SwiftUI

/// Something the keyboard can select in the current list.
enum NavItem: Identifiable {
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
}

enum NavCommand {
    /// Return: open a note or link, edit a task's title.
    case open
    /// ⌘R: rename a link or task.
    case rename
    /// Space: tick a task, mark a video watched.
    case toggle
    /// ⌘O: run a task's action, or open a link.
    case action
    /// ⌘⌫, undoable.
    case delete
    /// ⌘P: pin a note or link, mark a task important.
    case pin
    /// ⇧⌘[ and ⇧⌘]: previous or next Space.
    case moveSpace(Int)
    /// ← and → on the Links tab.
    case switchList
}

/// Keyboard selection in the panel's lists. The capture bar keeps the text cursor throughout, so
/// typing anything that isn't a list key goes straight back to capturing.
final class ListNavigation: ObservableObject {
    @Published private(set) var selectedID: UUID?
    /// The current list in display order, supplied by the panel.
    var items: () -> [NavItem] = { [] }
    var perform: (NavCommand, NavItem) -> Void = { _, _ in }
    /// ⌘1–4 and ⌘[ ⌘], answered by the panel.
    var switchTab: (Int) -> Void = { _ in }
    var switchSpace: (Int) -> Void = { _ in }

    var isActive: Bool { selectedID != nil }

    var selected: NavItem? {
        guard let selectedID else { return nil }
        return items().first { $0.id == selectedID }
    }

    /// Moves by `step`; leaving the top returns to the capture bar. Returns false when there is nothing to select.
    @discardableResult
    func move(_ step: Int) -> Bool {
        let list = items()
        guard !list.isEmpty else {
            selectedID = nil
            return false
        }
        guard let current = list.firstIndex(where: { $0.id == selectedID }) else {
            if step > 0 { selectedID = list[0].id }
            return step > 0
        }
        let next = current + step
        selectedID = next < 0 ? nil : list[min(next, list.count - 1)].id
        return true
    }

    func run(_ command: NavCommand) {
        guard let item = selected else {
            selectedID = nil
            return
        }
        let list = items()
        let index = list.firstIndex { $0.id == item.id } ?? 0
        perform(command, item)
        // If the item left the list (deleted, moved, ticked away), select its neighbour.
        DispatchQueue.main.asyncAfter(deadline: .now() + TaskStoreTiming.settle) { [weak self] in
            guard let self, self.selectedID == item.id else { return }
            let after = self.items()
            if !after.contains(where: { $0.id == item.id }) {
                self.selectedID = after.isEmpty ? nil : after[min(index, after.count - 1)].id
            }
        }
    }

    func clear() {
        if selectedID != nil { selectedID = nil }
    }
}

enum TaskStoreTiming {
    /// Long enough for a ticked task to linger and leave the list.
    static let settle = LibraryStore.lingerSeconds + 0.15
}

private struct KeyboardSelectionKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// The row the keyboard has selected, if any.
    var keyboardSelection: UUID? {
        get { self[KeyboardSelectionKey.self] }
        set { self[KeyboardSelectionKey.self] = newValue }
    }
}

/// Draws the keyboard selection behind a row, the way Finder and Mail do.
struct KeyboardHighlight: ViewModifier {
    let id: UUID
    @Environment(\.keyboardSelection) private var selection

    func body(content: Content) -> some View {
        content
            .background {
                if selection == id {
                    RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .padding(.horizontal, -Tokens.Spacing.s + 2)
                }
            }
            .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

extension View {
    func keyboardHighlight(_ id: UUID) -> some View {
        modifier(KeyboardHighlight(id: id))
    }
}

/// Scrolls a list to keep the keyboard selection visible.
struct FollowSelection: ViewModifier {
    let proxy: ScrollViewProxy
    @Environment(\.keyboardSelection) private var selection

    func body(content: Content) -> some View {
        content.onChange(of: selection) { _, id in
            guard let id else { return }
            withAnimation(Tokens.Motion.quick) { proxy.scrollTo(id) }
        }
    }
}
