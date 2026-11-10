import SwiftUI

extension Space {
    var tint: Color { Tokens.Tint.named(tintName) }
}

enum DueLabel {
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        if days == 1 { return "Tomorrow" }
        if days == -1 { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

struct TaskRowView: View {
    @ObservedObject var store: LibraryStore
    let task: TaskItem
    let density: Density
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.panelActions) private var actions

    var body: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Button(action: toggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? AnyShapeStyle(task.space?.tint ?? .accentColor) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark \(task.title) as not done" : "Mark \(task.title) as done")

            title

            if task.isImportant {
                Image(systemName: "exclamationmark").font(.caption.bold()).foregroundStyle(.secondary)
                    .accessibilityLabel("Important")
            }
            Spacer(minLength: Tokens.Spacing.s)
            if let action = task.action { actionButton(action) }
            if let due = task.dueDate {
                Text(DueLabel.text(for: due)).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, density.rowPadding)
        .contentShape(Rectangle())
        .keyboardHighlight(task.id)
        .id(task.id)
        .contextMenu { menu }
        .onChange(of: actions.editRequest) { _, id in
            guard id == task.id, !editing else { return }
            draft = task.title
            editing = true
        }
    }

    @ViewBuilder private var title: some View {
        if editing {
            TextField("Task", text: $draft)
                .textFieldStyle(.plain)
                .font(Tokens.TextRole.row)
                .focused($fieldFocused)
                .onSubmit(finishEditing)
                .onChange(of: fieldFocused) { _, focused in
                    if !focused { finishEditing() }
                }
                .onAppear { fieldFocused = true }
        } else {
            Text(task.title)
                .font(Tokens.TextRole.row)
                .lineLimit(1)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .onTapGesture {
                    draft = task.title
                    editing = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Edit title")
        }
    }

    /// The task's doorway: one click opens the link, app or folder.
    private func actionButton(_ action: ItemAction) -> some View {
        let available = LinkOpener.isAvailable(action)
        return Button { actions.open(action) } label: {
            Image(systemName: Self.symbol(for: action))
                .font(Tokens.TextRole.detail.weight(.semibold))
                .foregroundStyle(available ? AnyShapeStyle(task.space?.tint ?? .accentColor) : AnyShapeStyle(.tertiary))
                .padding(.horizontal, Tokens.Spacing.s - 2)
                .padding(.vertical, 2)
                .background((task.space?.tint ?? .accentColor).opacity(available ? 0.14 : 0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .help(available ? "Open \(action.label)" : "Can't find \(action.label). It may have moved.")
        .accessibilityLabel(available ? "Open \(action.label)" : "\(action.label) can't be found")
    }

    static func symbol(for action: ItemAction) -> String {
        switch action {
        case .url: "arrow.up.right"
        case .app: "app"
        case .file: "folder"
        }
    }

    @ViewBuilder private var actionMenu: some View {
        Menu(task.action == nil ? "Add Action" : "Action") {
            if let action = task.action {
                Button("Open \(action.label)") { actions.open(action) }
                Divider()
            }
            Button("Paste Link") {
                guard let url = ClipboardNudge.readURL() else {
                    actions.confirm("There is no link on the clipboard")
                    return
                }
                store.setAction(task, .url(url))
            }
            Button("Choose App…") { choose(app: true) }
            Button("Choose File or Folder…") { choose(app: false) }
            if task.action != nil {
                Divider()
                Button("Remove Action") { store.setAction(task, nil) }
            }
        }
    }

    /// Runs after the menu closes, so the file chooser isn't opened mid-menu.
    private func choose(app: Bool) {
        DispatchQueue.main.async {
            guard let url = LinkOpener.choose(app: app) else { return }
            store.setAction(task, app ? .app(url) : .file(url))
        }
    }

    @ViewBuilder private var menu: some View {
        actionMenu
        Divider()
        Menu("Move to") {
            ForEach(store.spaces) { space in
                Button(space.name) { store.move(task, to: space) }.disabled(space.id == task.space?.id)
            }
        }
        Button(task.isImportant ? "Remove Important" : "Mark Important") { store.setImportant(task, !task.isImportant) }
        Divider()
        Button("Due Today") { store.setDue(task, Calendar.current.startOfDay(for: Date())) }
        Button("Due Tomorrow") {
            let today = Calendar.current.startOfDay(for: Date())
            store.setDue(task, Calendar.current.date(byAdding: .day, value: 1, to: today))
        }
        Button("No Due Date") { store.setDue(task, nil) }.disabled(task.dueDate == nil)
        Divider()
        Button("Delete", role: .destructive) { store.delete(task) }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : Tokens.Motion.quick) { store.toggleCompleted(task) }
        // Lets the tick be seen, then fades the row into Done.
        DispatchQueue.main.asyncAfter(deadline: .now() + LibraryStore.lingerSeconds + 0.05) {
            withAnimation(reduceMotion ? nil : Tokens.Motion.quick) { store.reload() }
        }
    }

    private func finishEditing() {
        guard editing else { return }
        editing = false
        store.rename(task, to: draft)
        actions.focusCapture()
    }
}
