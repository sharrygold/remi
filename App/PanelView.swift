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
    /// Bumped by ⌘N and the widget's New Note item; the panel answers by opening a blank note.
    @Published var newNoteRequests = 0
    /// Opens a particular note, for example from search.
    @Published var noteToOpen: UUID?
    /// Closes the panel after something opens elsewhere, unless it is pinned. Set by the app.
    var closeAfterOpening: () -> Void = {}
    var openSettings: () -> Void = {}
}

struct PanelView: View {
    let density: Density
    @ObservedObject var presentation: PanelPresentation
    @ObservedObject var capture: CaptureText
    @ObservedObject var store: LibraryStore
    @ObservedObject var search: SearchState
    @State var tab: PanelTab
    /// A task found by search, briefly highlighted in the Tasks list.
    @State private var highlightedTaskID: UUID?
    @State private var selectedSpaceID: UUID?
    @State private var showDone = false
    @State private var confirmation: String?
    @State private var openNoteID: UUID?
    @State private var linkList: LinkList = .saved
    @State private var clipboardOffer: ClipboardOffer?
    /// Bumped on every open and close, so a slow clipboard check from an earlier open is ignored.
    @State private var clipboardCheck = 0
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
            if showsTokens { tokenRow } else if let clipboardOffer { clipboardChip(clipboardOffer) }
            if search.active {
                SearchPane(store: store, search: search, density: density, onOpen: openSearchHit, onClose: closeSearch)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : Tokens.Surface.contentOpacity),
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
            } else {
                spaceSwitcher
                tabs
                content
            }
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
        .environment(\.panelActions, PanelActions(open: openItem, confirm: { show(confirmation: $0) }))
        .onAppear {
            captureFocused = true
            capture.submitNote = submitNote
            capture.toggleLinkList = toggleLinkList
            capture.dismissClipboardOffer = {
                guard let offer = clipboardOffer, capture.text.isEmpty else { return false }
                dismissClipboard(offer)
                return true
            }
        }
        .onChange(of: capture.text) { _, _ in capture.linkListOverride = nil }
        .onChange(of: captureFocused) { _, focused in capture.isFocused = focused }
        .onChange(of: presentation.presented) { _, presented in
            if presented {
                captureFocused = true
                store.reload()
                checkClipboard()
            } else {
                clipboardCheck += 1
                clipboardOffer = nil
            }
        }
        .onChange(of: presentation.newNoteRequests) { _, _ in
            closeSearch()
            startNewNote()
        }
        .onChange(of: search.requests) { _, _ in search.active = true }
        .onChange(of: search.active) { _, active in if !active { captureFocused = true } }
        .onChange(of: presentation.noteToOpen) { _, id in
            guard let id else { return }
            tab = .notes
            openNoteID = id
            presentation.noteToOpen = nil
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
            } else if parsed.isLink {
                spaceToken
                token(captureLinkList.title, symbol: captureLinkList.symbol, tint: .accentColor)
            } else {
                spaceToken
                if let due = parsed.due { token(DueLabel.text(for: due), symbol: "calendar", tint: .secondary) }
                if parsed.important { token("Important", symbol: "exclamationmark", tint: .secondary) }
                if let url = parsed.url { token(LinkClassifier.displayHost(url), symbol: "arrow.up.right", tint: .secondary)
                    .accessibilityLabel("Opens \(LinkClassifier.displayHost(url))") }
            }
            Spacer()
            if confirmation == nil || !capture.text.isEmpty {
                Text(parsed.isLink ? "Tab switches list" : "⌘↩ saves as a note").font(Tokens.TextRole.detail).foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
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
            .lineLimit(1)
            .fixedSize()
            .font(Tokens.TextRole.detail)
            .foregroundStyle(tint)
            .padding(.horizontal, Tokens.Spacing.s)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }

    /// The list a captured link will go to: Watch later for videos, unless Tab switched it.
    private var captureLinkList: LinkList {
        capture.linkListOverride ?? parsed.url.map(LinkClassifier.list(for:)) ?? .saved
    }

    /// Tab in the capture bar flips a link between Saved links and Watch later. Returns false when not a link.
    private func toggleLinkList() -> Bool {
        guard parsed.isLink else { return false }
        capture.linkListOverride = captureLinkList == .saved ? .watchLater : .saved
        return true
    }

    private func submit() {
        if capture.text.trimmingCharacters(in: .whitespaces).isEmpty, let offer = clipboardOffer {
            saveClipboard(offer)
            return
        }
        let result = parsed
        if result.isLink, let url = result.url {
            let saved = store.addLink(url, list: captureLinkList, spaceMatch: result.space, currentSpace: selectedSpace)
            capture.text = ""
            show(confirmation: saved.isNew ? "Saved to \(saved.link.list.title)  ·  ⌘Z to undo"
                                           : "Already in \(saved.link.list.title)")
            return
        }
        guard let task = store.add(result, currentSpace: selectedSpace) else { return }
        capture.text = ""
        show(confirmation: "Added to \(task.space?.name ?? "Tasks")  ·  ⌘Z to undo")
    }

    /// ⌘Return: the same text becomes a note, keeping words like "today" as written.
    private func submitNote() {
        guard let note = store.addNote(fromCapture: capture.text, currentSpace: selectedSpace) else { return }
        capture.text = ""
        show(confirmation: "Note added to \(note.space?.name ?? "Notes")  ·  ⌘Z to undo")
    }

    private func startNewNote() {
        if let open = store.notes.first(where: { $0.id == openNoteID }) { store.finishEditing(open) }
        let note = store.newNote(in: selectedSpace)
        tab = .notes
        openNoteID = note.id
    }

    private func openItem(_ action: ItemAction) {
        if LinkOpener.perform(action) {
            presentation.closeAfterOpening()
        } else {
            show(confirmation: "Can't find \(action.label). It may have moved.")
        }
    }

    // MARK: Clipboard

    private func checkClipboard() {
        clipboardCheck += 1
        let check = clipboardCheck
        Task { @MainActor in
            let offer = await ClipboardNudge.check(isSaved: store.isSaved)
            guard check == clipboardCheck, presentation.presented, let offer, !ClipboardNudge.isHandled(offer.changeCount) else { return }
            clipboardOffer = offer
        }
    }

    private func clipboardChip(_ offer: ClipboardOffer) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(offer.url.map { "Save link from clipboard? \(LinkClassifier.displayHost($0))" } ?? "Save link from clipboard?")
                .lineLimit(1)
            Spacer(minLength: Tokens.Spacing.xs)
            Button { saveClipboard(offer) } label: {
                Text("Save  ↩").fontWeight(.semibold)
                    .padding(.horizontal, Tokens.Spacing.s)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Save this link (Return)")
            .accessibilityLabel("Save link")
            Button { dismissClipboard(offer) } label: {
                Image(systemName: "xmark")
                    .frame(width: Tokens.Spacing.l, height: Tokens.Spacing.l)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Not this one (Esc)")
            .accessibilityLabel("Dismiss")
        }
        .font(Tokens.TextRole.detail)
        .padding(.leading, Tokens.Spacing.s + Tokens.Spacing.xs)
        .padding(.trailing, Tokens.Spacing.xs)
        .frame(height: Tokens.Spacing.l + Tokens.Spacing.xs)
        .background(Color.accentColor.opacity(0.1), in: Capsule())
        .transition(.opacity)
    }

    private func saveClipboard(_ offer: ClipboardOffer) {
        ClipboardNudge.markHandled(offer)
        clipboardOffer = nil
        guard let url = offer.url ?? ClipboardNudge.readURL() else {
            show(confirmation: "The clipboard no longer holds a link")
            return
        }
        let saved = store.addLink(url, currentSpace: selectedSpace)
        show(confirmation: saved.isNew ? "Saved to \(saved.link.list.title)  ·  ⌘Z to undo" : "Already in \(saved.link.list.title)")
    }

    private func dismissClipboard(_ offer: ClipboardOffer) {
        ClipboardNudge.markHandled(offer)
        withAnimation(Tokens.Motion.quick) { clipboardOffer = nil }
    }

    // MARK: Search

    private func closeSearch() {
        guard search.active else { return }
        search.active = false
        search.query = ""
        captureFocused = true
    }

    private func openSearchHit(_ hit: SearchHit) {
        closeSearch()
        switch hit {
        case .task(let task):
            selectedSpaceID = nil
            if task.isCompleted { showDone = true }
            tab = .tasks
            DispatchQueue.main.async { highlightedTaskID = task.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if highlightedTaskID == task.id { withAnimation(Tokens.Motion.quick) { highlightedTaskID = nil } }
            }
        case .note(let note):
            presentation.noteToOpen = note.id
        case .link(let link):
            if let url = link.url { openItem(.url(url)) }
        }
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
            } else if tab == .notes {
                NotesPane(store: store, density: density, space: selectedSpace, showsSpace: selectedSpaceID == nil,
                          openNoteID: $openNoteID, onNewNote: startNewNote, onClose: { captureFocused = true },
                          onConfirm: { show(confirmation: $0) })
            } else if tab == .links {
                LinksPane(store: store, density: density, space: selectedSpace, showsSpace: selectedSpaceID == nil, list: $linkList)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: density.sectionGap) {
                        todayContent
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
        watchLaterShortcut
    }

    /// A quiet count that jumps to the Watch later list.
    @ViewBuilder private var watchLaterShortcut: some View {
        let count = store.watchLaterCount(in: selectedSpace)
        if count > 0 {
            Button {
                linkList = .watchLater
                tab = .links
            } label: {
                Label(count == 1 ? "1 to watch later" : "\(count) to watch later", systemImage: "play.rectangle")
                    .font(Tokens.TextRole.detail)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, Tokens.Spacing.xs)
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
            ScrollViewReader { proxy in
            List {
                ForEach(open) { task in
                    taskRow(task)
                        .itemProvider { NSItemProvider(object: task.id.uuidString as NSString) }
                        .listRowBackground(highlight(task))
                        .listRowSeparator(.hidden)
                        .id(task.id)
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
                            taskRow(task).listRowBackground(highlight(task)).listRowSeparator(.hidden).id(task.id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: highlightedTaskID) { _, id in
                guard let id else { return }
                withAnimation(Tokens.Motion.quick) { proxy.scrollTo(id, anchor: .center) }
            }
            }
        }
    }

    private func highlight(_ task: TaskItem) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
            .fill(task.id == highlightedTaskID ? (task.space?.tint ?? .accentColor).opacity(0.18) : .clear)
            .padding(.horizontal, Tokens.Spacing.xs)
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

    private func section<Rows: View>(_ title: String, tint: Color, symbol: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: density.rowPadding) {
            Label(title, systemImage: symbol).font(Tokens.TextRole.sectionTitle).foregroundStyle(tint)
            rows()
        }
    }

    private var footer: some View {
        HStack {
            Button { search.requests += 1 } label: {
                HStack(spacing: Tokens.Spacing.xs) {
                    Label("Search", systemImage: "magnifyingglass")
                    Text("⌘F").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            Spacer()
            Button { presentation.pinned.toggle() } label: {
                Image(systemName: presentation.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presentation.pinned ? "Unpin panel" : "Pin panel open")
            Button { presentation.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
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
    /// Mirrors the field's focus, so ⌘Return is only taken while typing a capture.
    var isFocused = false
    var submitNote: (() -> Void)?
    /// Tab on a pasted link; returns false when the text is not a link, so Tab behaves normally.
    var toggleLinkList: (() -> Bool)?
    @Published var linkListOverride: LinkList?
    /// Esc first dismisses the clipboard chip; returns false when there is none, so Esc closes the panel.
    var dismissClipboardOffer: (() -> Bool)?
}
