import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case today = "Today", tasks = "Tasks", notes = "Notes", links = "Links"
    var id: String { rawValue }
}

/// Drives the panel growing out of, and shrinking back into, the widget.
final class PanelPresentation: ObservableObject {
    @Published var presented = false
    @Published var pinned = false
    @Published var anchor = UnitPoint.trailing
}

struct PanelView: View {
    let density: Density
    @ObservedObject var presentation: PanelPresentation
    @ObservedObject var capture: CaptureText
    @ObservedObject var store: TaskStore
    @State var tab: PanelTab
    @State private var selectedSpaceID: UUID?
    @State private var showDone = false
    @State private var confirmation: String?
    @FocusState private var captureFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)

    private var selectedSpace: Space? { store.spaces.first { $0.id == selectedSpaceID } }

    private var parsed: ParsedCapture {
        CaptureParser.parse(capture.text, spaceNames: store.spaces.map(\.name))
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.s) {
            captureBar
            if showsTokens { tokenRow }
            spaceSwitcher
            tabs
            content
            footer
        }
        .padding(Tokens.Spacing.s)
        .frame(width: Tokens.Size.panel.width, height: Tokens.Size.panel.height)
        .background {
            if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
        // A growing mask rather than scaling the content, which knocks the text field out of position.
        .mask {
            shape.scaleEffect(presentation.presented || reduceMotion ? 1 : 0.08, anchor: presentation.anchor)
        }
        .opacity(presentation.presented ? 1 : 0)
        .animation(Tokens.Motion.panel, value: presentation.presented)
        .onAppear { captureFocused = true }
        .onChange(of: presentation.presented) { _, presented in
            if presented {
                captureFocused = true
                store.reload()
            }
        }
    }

    // MARK: Capture

    private var captureBar: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "plus").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Capture a task, note or link", text: $capture.text)
                .textFieldStyle(.plain)
                .font(Tokens.TextRole.row)
                .focused($captureFocused)
                .onSubmit(submit)
                .accessibilityLabel("Capture")
        }
        .padding(.horizontal, Tokens.Spacing.m - Tokens.Spacing.xs)
        .frame(height: 40)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
    }

    private var showsTokens: Bool {
        !capture.text.trimmingCharacters(in: .whitespaces).isEmpty || confirmation != nil
    }

    private var tokenRow: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            if let confirmation, capture.text.isEmpty {
                token(confirmation, symbol: "checkmark", tint: .secondary)
            } else {
                spaceToken
                if let due = parsed.due { token(DueLabel.text(for: due), symbol: "calendar", tint: .secondary) }
                if parsed.important { token("Important", symbol: "exclamationmark", tint: .secondary) }
            }
            Spacer()
        }
        .frame(height: Tokens.Spacing.l)
    }

    @ViewBuilder private var spaceToken: some View {
        switch parsed.space {
        case .new(let name):
            token("New space: \(name)", symbol: "plus", tint: .accentColor)
        case .existing(let name):
            let space = store.spaces.first { $0.name == name }
            token(name, symbol: space?.symbol ?? "folder", tint: space?.tint ?? .secondary)
        case .none:
            let space = selectedSpace ?? store.fallbackSpace
            token(space?.name ?? "", symbol: space?.symbol ?? "folder", tint: space?.tint ?? .secondary)
        }
    }

    private func token(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(Tokens.TextRole.detail)
            .foregroundStyle(tint)
            .padding(.horizontal, Tokens.Spacing.s)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func submit() {
        let result = parsed
        guard let task = store.add(result, currentSpace: selectedSpace) else { return }
        capture.text = ""
        show(confirmation: "Added to \(task.space?.name ?? "Tasks")  ·  ⌘Z to undo")
    }

    private func show(confirmation text: String) {
        confirmation = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if confirmation == text { confirmation = nil }
        }
    }

    // MARK: Spaces and tabs

    private var spaceSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.xs) {
                spaceChip(name: "All", symbol: "square.grid.2x2", tint: .accentColor, id: nil)
                ForEach(store.spaces) { space in
                    spaceChip(name: space.name, symbol: space.symbol, tint: space.tint, id: space.id)
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let task = store.tasks.first(where: { $0.id.uuidString == raw }) else { return false }
                            store.move(task, to: space)
                            return true
                        }
                }
                Button(action: startNewSpace) {
                    Image(systemName: "plus").font(Tokens.TextRole.detail).foregroundStyle(.secondary)
                        .padding(.horizontal, Tokens.Spacing.s).padding(.vertical, Tokens.Spacing.xs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Space")
            }
            .padding(.trailing, Tokens.Spacing.l)
        }
        .mask {
            // Fades the trailing edge so a cut-off Space reads as scrollable.
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Tokens.Spacing.l)
            }
        }
    }

    /// New Spaces come from the capture bar, so there is never a dialog.
    private func startNewSpace() {
        if !capture.text.contains("#") {
            capture.text = capture.text.isEmpty ? "#" : capture.text + " #"
        }
        captureFocused = true
    }

    private func spaceChip(name: String, symbol: String, tint: Color, id: UUID?) -> some View {
        let selected = selectedSpaceID == id
        return Button { selectedSpaceID = id } label: {
            Label(name, systemImage: symbol)
                .font(Tokens.TextRole.detail)
                .padding(.horizontal, Tokens.Spacing.s)
                .padding(.vertical, Tokens.Spacing.xs)
                .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .background(selected ? tint.opacity(0.18) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tabs: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach(PanelTab.allCases) { item in
                Button { tab = item } label: {
                    Text(item.rawValue)
                        .font(Tokens.TextRole.meta.weight(tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(tab == item ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        Group {
            if tab == .tasks {
                tasksList
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: density.sectionGap) {
                        switch tab {
                        case .today: todayContent
                        case .notes: notesContent
                        default: linksContent
                        }
                    }
                    .padding(Tokens.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : Tokens.Surface.contentOpacity),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
    }

    @ViewBuilder private var todayContent: some View {
        let today = store.dueToday(in: selectedSpace)
        let overdue = store.overdue(in: selectedSpace)
        if today.isEmpty && overdue.isEmpty {
            emptyState(symbol: "sun.max", title: "Nothing planned for today",
                       detail: "Type a task above and add “today” to put it here.")
        } else {
            ForEach(store.spaces.filter { space in today.contains { $0.space?.id == space.id } }) { space in
                section(space.name, tint: space.tint, symbol: space.symbol) {
                    ForEach(today.filter { $0.space?.id == space.id }) { taskRow($0) }
                }
            }
            if !overdue.isEmpty {
                section("Still open", tint: .secondary, symbol: "clock") {
                    ForEach(overdue) { taskRow($0) }
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        TaskRowView(store: store, task: task, density: density)
    }

    @ViewBuilder private var tasksList: some View {
        let open = store.open(in: selectedSpace)
        let done = store.done(in: selectedSpace)
        if open.isEmpty && done.isEmpty {
            VStack {
                emptyState(symbol: "checklist", title: "No tasks here yet", detail: "Anything you type above and send with Return lands here.")
            }
            .padding(Tokens.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List {
                ForEach(open) { task in
                    taskRow(task)
                        .itemProvider { NSItemProvider(object: task.id.uuidString as NSString) }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    var ordered = open
                    ordered.move(fromOffsets: source, toOffset: destination)
                    store.reorder(ordered)
                }
                if !done.isEmpty {
                    Button { withAnimation(Tokens.Motion.quick) { showDone.toggle() } } label: {
                        Label("Done (\(done.count))", systemImage: showDone ? "chevron.down" : "chevron.right")
                            .font(Tokens.TextRole.sectionTitle)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    if showDone {
                        ForEach(done) { task in
                            taskRow(task).listRowBackground(Color.clear).listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: Tokens.Spacing.s) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(Tokens.TextRole.sectionTitle)
            Text(detail).font(Tokens.TextRole.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.l * 2)
    }

    private var notesContent: some View {
        ForEach(Sample.notes) { note in
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack(spacing: Tokens.Spacing.xs) {
                    if note.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                    Text(note.title).font(Tokens.TextRole.sectionTitle)
                }
                Text(note.preview).font(Tokens.TextRole.detail).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(.vertical, density.rowPadding)
        }
    }

    private var linksContent: some View {
        Group {
            section("Saved links", tint: .secondary, symbol: "bookmark") { ForEach(Sample.saved) { linkRow($0) } }
            section("Watch later", tint: .secondary, symbol: "play.rectangle") { ForEach(Sample.watchLater) { linkRow($0) } }
        }
    }

    private func section<Rows: View>(_ title: String, tint: Color, symbol: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: density.rowPadding) {
            Label(title, systemImage: symbol).font(Tokens.TextRole.sectionTitle).foregroundStyle(tint)
            rows()
        }
    }

    private func linkRow(_ link: SampleLink) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: link.symbol).foregroundStyle(link.space.tint).frame(width: Tokens.Spacing.m + Tokens.Spacing.xs)
            VStack(alignment: .leading) {
                Text(link.title).font(Tokens.TextRole.row).lineLimit(1)
                Text(link.domain).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, density.rowPadding)
    }

    private var footer: some View {
        HStack {
            Label("Search", systemImage: "magnifyingglass")
            Text("⌘F").foregroundStyle(.tertiary)
            Spacer()
            Button { presentation.pinned.toggle() } label: {
                Image(systemName: presentation.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presentation.pinned ? "Unpin panel" : "Pin panel open")
            Image(systemName: "gearshape").accessibilityLabel("Settings")
        }
        .font(Tokens.TextRole.detail)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Tokens.Spacing.s)
        .frame(height: Tokens.Spacing.l)
    }
}

/// The capture field's text, shared so ⌘Z can tell whether anything is being typed.
final class CaptureText: ObservableObject {
    @Published var text = ""
}
