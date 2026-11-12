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
    @State private var addingLink = false
    @State private var linkDraft = ""
    @State private var hovering = CommandLine.arguments.contains("--preview-row-hover")
    @FocusState private var fieldFocused: Bool
    @FocusState private var linkFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.panelActions) private var actions

    var body: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Button(action: toggle) {
                // The completion pop: the check lands from 0.6 with a small overshoot, the only bounce in the app.
                ZStack {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                        .opacity(task.isCompleted ? 0 : 1)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(task.space?.tint ?? .brand)
                        .scaleEffect(task.isCompleted || reduceMotion ? 1 : 0.6)
                        .opacity(task.isCompleted ? 1 : 0)
                }
                .animation(reduceMotion ? Motion.reduced : Motion.pop, value: task.isCompleted)
            }
            .buttonStyle(PressScale(scale: 0.96))
            .accessibilityLabel(task.isCompleted ? "Mark \(task.title) as not done" : "Mark \(task.title) as done")

            title

            if task.isImportant {
                Image(systemName: "exclamationmark").font(.caption.bold()).foregroundStyle(.secondary)
                    .accessibilityLabel("Important")
            }
            Spacer(minLength: Tokens.Spacing.s)
            if let action = task.action { actionButton(action) }
            if let rule = task.repeatRule {
                Image(systemName: "repeat").font(.caption2).foregroundStyle(.tertiary)
                    .help(rule.label(for: task.dueDate))
                    .accessibilityLabel("Repeats \(rule.label(for: task.dueDate).lowercased())")
            }
            // On hover the date gives way to a delete button, so the row doesn't shift.
            ZStack(alignment: .trailing) {
                if let due = task.dueDate {
                    Text(DueLabel.text(for: due)).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
                        .opacity(hovering ? 0 : 1)
                }
                deleteButton.opacity(hovering ? 1 : 0)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .transition(Motion.row(reduce: reduceMotion))
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
        if addingLink {
            linkField
        } else if editing {
            TextField("Task", text: $draft)
                .brandTextInput()
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

    /// Typed or pasted in the row itself, so the link becomes this task's action, not a saved link.
    private var linkField: some View {
        HStack(spacing: Tokens.Spacing.s - 2) {
            Image(systemName: "link").font(Tokens.TextRole.detail).foregroundStyle(.secondary)
            TextField("Paste or type a link", text: $linkDraft)
                .brandTextInput()
                .textFieldStyle(.plain)
                .font(Tokens.TextRole.row)
                .focused($linkFocused)
                .onSubmit(finishLink)
                .onExitCommand(perform: cancelLink)
                .onChange(of: linkFocused) { _, focused in
                    if !focused { cancelLink() }
                }
                .onAppear { linkFocused = true }
                .accessibilityLabel("Link for \(task.title)")
        }
    }

    private var hasLink: Bool {
        if case .url = task.action { true } else { false }
    }

    private func startLink() {
        DispatchQueue.main.async {
            if case .url(let url) = task.action {
                linkDraft = url.absoluteString
            } else {
                linkDraft = ClipboardNudge.readURL()?.absoluteString ?? ""
            }
            editing = false
            addingLink = true
        }
    }

    private func finishLink() {
        guard addingLink else { return }
        let text = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return cancelLink() }
        guard let url = LinkClassifier.url(from: text) else {
            actions.confirm("That doesn't look like a link")
            return
        }
        addingLink = false
        store.setAction(task, .url(url))
        actions.focusCapture()
    }

    private func cancelLink() {
        guard addingLink else { return }
        addingLink = false
        actions.focusCapture()
    }

    private var deleteButton: some View {
        Button {
            store.delete(task)
            actions.confirm("Task deleted  ·  ⌘Z to undo")
        } label: {
            Image(systemName: "trash")
                .font(Tokens.TextRole.detail)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.96))
        .help("Delete (⌘Z undoes it)")
        .accessibilityLabel("Delete \(task.title)")
    }

    /// The task's doorway: one click opens the link, app or folder.
    private func actionButton(_ action: ItemAction) -> some View {
        let available = LinkOpener.isAvailable(action)
        return Button { actions.open(action) } label: {
            Image(systemName: Self.symbol(for: action))
                .font(Tokens.TextRole.detail.weight(.semibold))
                .foregroundStyle(available ? AnyShapeStyle(task.space?.tint ?? .brand) : AnyShapeStyle(.tertiary))
                .padding(.horizontal, Tokens.Spacing.s - 2)
                .padding(.vertical, 2)
                .background((task.space?.tint ?? .brand).opacity(available ? 0.14 : 0.05), in: Capsule())
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
            Button(hasLink ? "Change Link…" : "Add Link…", action: startLink)
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

    private var repeatMenu: some View {
        Picker(selection: Binding(get: { task.repeatRule }, set: { store.setRepeat(task, $0) })) {
            Text("Never").tag(RepeatRule?.none)
            ForEach(RepeatRule.allCases) { Text($0.menuTitle).tag(Optional($0)) }
        } label: {
            Text("Repeat")
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder private var menu: some View {
        if task.isSetAside {
            Button("Bring Back") { store.bringBack(task) }
            Divider()
        }
        Button("Rename…") {
            DispatchQueue.main.async {
                draft = task.title
                editing = true
            }
        }
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
        if !task.isCompleted { repeatMenu }
        Divider()
        Button("Delete", role: .destructive) { store.delete(task) }
    }

    private func toggle() {
        store.toggleCompleted(task)
        // Lets the pop be seen, then eases the row out while the rows below close up.
        DispatchQueue.main.asyncAfter(deadline: .now() + LibraryStore.lingerSeconds + 0.05) {
            withAnimation(Motion.adaptive(Motion.collapse, reduce: reduceMotion)) { store.reload() }
        }
    }

    private func finishEditing() {
        guard editing else { return }
        editing = false
        store.rename(task, to: draft)
        actions.focusCapture()
    }
}
