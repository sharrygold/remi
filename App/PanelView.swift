import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case today = "Today", tasks = "Tasks", notes = "Notes", links = "Links"
    var id: String { rawValue }
}

/// Drives the panel growing out of, and shrinking back into, the widget.
final class PanelPresentation: ObservableObject {
    @Published var presented = false
    /// True from opening until the window is ordered out, so closing doesn't fade the view.
    @Published var shown = false
    @Published var pinned = false
    @Published var anchor = UnitPoint.trailing
    /// Bumped by ⌘N and the widget's New Note item; the panel answers by opening a blank note.
    @Published var newNoteRequests = 0
    /// The "+" of the current tab, pressed from code (self-tests).
    @Published var addRequests = 0
    /// Opens the Links tab's "Add link" field.
    @Published var addLinkRequests = 0
    /// Opens a particular note, for example from search.
    @Published var noteToOpen: UUID?
    /// A message for the confirmation line, from outside the panel.
    @Published var message: String?
    /// The welcome card stands in for the lists on first launch.
    @Published var showWelcome = false
    var onWelcomeDone: () -> Void = {}
    /// Handed to the welcome card so the companion can be chosen there.
    var widget: CompanionSettings?
    /// Closes the panel after something opens elsewhere, unless it is pinned. Set by the app.
    var closeAfterOpening: () -> Void = {}
    var openSettings: () -> Void = {}
    /// Whether the morning review may appear: real sessions once a day, screenshots on demand.
    enum ReviewPolicy { case daily, always, never }
    var reviewPolicy = ReviewPolicy.daily
}

struct PanelView: View {
    let density: Density
    @ObservedObject var presentation: PanelPresentation
    @ObservedObject var capture: CaptureText
    @ObservedObject var store: LibraryStore
    @ObservedObject var search: SearchState
    @ObservedObject var nav: ListNavigation
    @State private var editRequest: UUID?
    @State var tab: PanelTab
    /// A task found by search, briefly highlighted in the Tasks list.
    @State private var highlightedTaskID: UUID?
    @State private var selectedSpaceID: UUID?
    @State private var showDone = false
    @State private var showSetAside = false
    /// The morning review stands in for Today until it is answered or closed.
    @State private var reviewing = false
    @State private var confirmingFreshStart = false
    @State private var confirmation: String?
    @State private var openNoteID: UUID?
    @State private var linkList: LinkList = .saved
    /// The "+ New task" field at the top of Today and Tasks.
    @State private var addingTask = false
    @State private var clipboardOffer: ClipboardOffer?
    /// Bumped on every open and close, so a slow clipboard check from an earlier open is ignored.
    @State private var clipboardCheck = 0
    /// The browser in front while the panel is open, offered as "Save this tab".
    @State private var frontBrowser: BrowserTab.Browser?
    /// The tab was saved this time round, so the chip steps aside.
    @State private var tabSaved = false
    @FocusState private var captureFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Read so the accent redraws when Plumage changes.
    @AppStorage(CompanionKeys.plumage) private var plumageName = Plumage.ivory.rawValue

    private let shape = RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)

    /// Between the close starting and the window being ordered out.
    private var closing: Bool { presentation.shown && !presentation.presented }

    private var selectedSpace: Space? { store.spaces.first { $0.id == selectedSpaceID } }

    private var parsed: ParsedCapture {
        CaptureParser.parse(capture.text, spaceNames: store.spaces.map(\.name))
    }

    // The chain is split in three because one long expression takes the compiler too long to check.
    var body: some View {
        answeringRequests(wired(layout))
    }

    private var layout: some View {
        // Browsing at the top, typing at the bottom: the capture bar is the main way in, like a message box.
        VStack(spacing: Tokens.Spacing.s) {
            header
            if store.isTemporary { storageWarning }
            if presentation.showWelcome, let widget = presentation.widget {
                WelcomeCard(widget: widget, shortcut: HotKeyCombo.saved.display, onDone: presentation.onWelcomeDone)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : Tokens.Surface.contentOpacity),
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
            } else if search.active {
                SearchPane(store: store, search: search, density: density, onOpen: openSearchHit, onClose: closeSearch)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : Tokens.Surface.contentOpacity),
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
            } else {
                tabs
                content
            }
            if showsTokens {
                tokenRow
            } else if let clipboardOffer {
                clipboardChip(clipboardOffer)
            } else if let tabOffer {
                browserChip(tabOffer)
            }
            captureBar
        }
        .padding(Tokens.Spacing.s)
        // Fills the window, which can be resized from its edges and remembers its size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
        // A growing mask rather than scaling the content, which knocks the text field out of position.
        // Opening grows out of the widget. Closing doesn't shrink the mask (the glass drops out under a
        // shrinking mask and leaves the darker list card behind as a box); the whole panel eases a
        // little toward the widget while the window fades (see hidePanel).
        .mask {
            shape.scaleEffect(presentation.presented || presentation.shown || reduceMotion ? 1 : 0.08, anchor: presentation.anchor)
        }
        .scaleEffect(closing && !reduceMotion ? 0.94 : 1, anchor: presentation.anchor)
        .opacity(presentation.shown ? 1 : 0)
        .animation(Tokens.Motion.panel, value: presentation.presented)
    }

    private func wired<Content: View>(_ content: Content) -> some View {
        content
        .environment(\.panelActions, PanelActions(open: openItem, confirm: { show(confirmation: $0) },
                                                   focusCapture: { captureFocused = true }, editRequest: editRequest))
        .environment(\.keyboardSelection, nav.selectedID)
        .tint(Color.brand)
        .onChange(of: tab) { _, _ in
            nav.clear()
            addingTask = false
        }
        .onChange(of: selectedSpaceID) { _, _ in nav.clear() }
        .onChange(of: linkList) { _, _ in nav.clear() }
        .onChange(of: openNoteID) { _, _ in nav.clear() }
        .onChange(of: search.active) { _, _ in nav.clear() }
        .onAppear {
            captureFocused = true
            capture.submitNote = submitNote
            capture.toggleLinkList = toggleLinkList
            nav.items = navItems
            nav.perform = performNav
            nav.switchTab = { index in
                guard PanelTab.allCases.indices.contains(index) else { return }
                closeSearch()
                tab = PanelTab.allCases[index]
            }
            nav.switchSpace = { step in
                let ids: [UUID?] = [nil] + store.spaces.map(\.id)
                let current = ids.firstIndex { $0 == selectedSpaceID } ?? 0
                selectedSpaceID = ids[(current + step + ids.count) % ids.count]
            }
            capture.saveTab = { saveTab(from: $0) }
            capture.dismissClipboardOffer = {
                if reviewing {
                    closeReview()
                    return true
                }
                guard let offer = clipboardOffer, capture.text.isEmpty else { return false }
                dismissClipboard(offer)
                return true
            }
        }
        .onChange(of: capture.text) { _, _ in capture.linkListOverride = nil }
        .onChange(of: reviewCount) { _, count in if count == 0, reviewing { closeReview() } }
        .onChange(of: captureFocused) { _, focused in capture.isFocused = focused }
        .onChange(of: presentation.presented) { _, presented in
            if presented {
                captureFocused = true
                store.reload()
                checkClipboard()
                refreshFrontBrowser()
                startMorningReviewIfDue()
            } else {
                clipboardCheck += 1
                clipboardOffer = nil
            }
        }
    }

    private func answeringRequests<Content: View>(_ content: Content) -> some View {
        content
        // A pinned panel stays open while you move between apps.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            if presentation.presented { refreshFrontBrowser() }
        }
        .onChange(of: presentation.message) { _, text in
            guard let text else { return }
            show(confirmation: text)
            presentation.message = nil
        }
        .onChange(of: presentation.addRequests) { _, _ in
            closeSearch()
            if tab == .notes { startNewNote() } else if tab == .links { presentation.addLinkRequests += 1 } else { addingTask = true }
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
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s) {
            Image(systemName: "plus").foregroundStyle(.secondary).accessibilityHidden(true)
            // Wraps as you type, grows to three lines, then scrolls. Return still saves.
            TextField("Capture a task, note or link", text: $capture.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Tokens.TextRole.row)
                .lineLimit(1...3)
                .focused($captureFocused)
                .brandTextInput()
                .onSubmit(submit)
                .accessibilityLabel("Capture")
        }
        .padding(.horizontal, Tokens.Spacing.m - Tokens.Spacing.xs)
        .padding(.vertical, Tokens.Spacing.s + 3)
        .frame(minHeight: 40)
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
                token(captureLinkList.title, symbol: captureLinkList.symbol, tint: .brand)
            } else {
                spaceToken
                if let rule = parsed.repeatRule {
                    token(rule.label(for: parsed.due), symbol: "repeat", tint: .secondary)
                } else if let due = parsed.due {
                    token(DueLabel.text(for: due), symbol: "calendar", tint: .secondary)
                }
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
            token("New space: \(name)", symbol: "plus", tint: .brand)
        case .existing(let name):
            let space = store.spaces.first { $0.name == name }
            token(name, symbol: space?.symbol ?? "folder", tint: space?.tint ?? .secondary)
        case .none:
            let space = selectedSpace ?? store.fallbackSpace
            token(space?.name ?? "", symbol: space?.symbol ?? "folder", tint: space?.tint ?? .secondary)
        }
    }

    private func token(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .lineLimit(1)
        .fixedSize()
        .font(Tokens.TextRole.detail)
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
            .foregroundStyle(Color.brand)
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
        .background(Color.brand.opacity(0.1), in: Capsule())
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

    // MARK: Browser tab

    private var tabOffer: BrowserTab.Browser? { tabSaved ? nil : frontBrowser }

    private func refreshFrontBrowser() {
        tabSaved = false
        frontBrowser = CommandLine.arguments.contains("--preview-tab-chip") ? BrowserTab.known[0] : BrowserTab.frontmost()
    }

    private func browserChip(_ browser: BrowserTab.Browser) -> some View {
        Button { saveTab(from: browser) } label: {
            HStack(spacing: Tokens.Spacing.s) {
                Image(systemName: "safari").foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Save this tab from \(browser.name)").lineLimit(1)
                Spacer(minLength: Tokens.Spacing.xs)
                Text(HotKeyCombo.savedSaveTab.display).fontWeight(.semibold).foregroundStyle(Color.brand)
            }
            .padding(.horizontal, Tokens.Spacing.s + Tokens.Spacing.xs)
            .frame(height: Tokens.Spacing.l + Tokens.Spacing.xs)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .font(Tokens.TextRole.detail)
        .background(Color.brand.opacity(0.1), in: Capsule())
        .help("Save the tab you're looking at to Links (\(HotKeyCombo.savedSaveTab.display))")
        .transition(.opacity)
    }

    private func saveTab(from browser: BrowserTab.Browser) {
        switch BrowserTab.read(browser) {
        case .success(let page):
            let saved = store.addLink(page.url, currentSpace: selectedSpace)
            if saved.isNew { store.setMetadata(for: saved.link.id, title: page.title, iconData: nil) }
            tabSaved = true
            show(confirmation: saved.isNew ? "Saved to \(saved.link.list.title)  ·  ⌘Z to undo" : "Already in \(saved.link.list.title)")
        case .failure(.notAllowed):
            show(confirmation: "Allow \(browser.name) in System Settings > Privacy & Security > Automation")
        case .failure(.notAWebPage):
            show(confirmation: "This tab isn't a web page")
        case .failure(.noTab):
            show(confirmation: "No open tab in \(browser.name)")
        }
    }

    /// Shown only if the saved library could not be opened and this session runs on a temporary copy.
    private var storageWarning: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityHidden(true)
            Text("Your library couldn't be opened, so changes now won't be kept. Quit and reopen; if this keeps happening, restore a backup in Settings > Data.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Tokens.TextRole.detail)
        .padding(Tokens.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Keyboard

    /// The current list in the order it is drawn.
    private func navItems() -> [NavItem] {
        if reviewing, tab == .today { return [] }
        switch tab {
        case .today:
            let today = store.dueToday(in: selectedSpace)
            let grouped = store.spaces.flatMap { space in today.filter { $0.space?.id == space.id } }
            return (grouped + store.overdue(in: selectedSpace)).map(NavItem.task)
        case .tasks:
            return (store.open(in: selectedSpace) + (showDone ? store.done(in: selectedSpace) : [])).map(NavItem.task)
        case .notes:
            return openNoteID == nil ? store.notes(in: selectedSpace).map(NavItem.note) : []
        case .links:
            return store.links(in: selectedSpace, list: linkList).map(NavItem.link)
        }
    }

    private func performNav(_ command: NavCommand, _ item: NavItem) {
        // Keep the cursor in the capture bar, unless this command moves it on purpose.
        defer {
            switch command {
            case .open, .rename: break
            default: captureFocused = true
            }
        }
        switch (command, item) {
        case (.open, .task(let task)), (.rename, .task(let task)):
            editRequest = task.id
            DispatchQueue.main.async { editRequest = nil }
        case (.rename, .link(let link)):
            editRequest = link.id
            DispatchQueue.main.async { editRequest = nil }
        case (.open, .note(let note)), (.action, .note(let note)):
            openNoteID = note.id
        case (.open, .link(let link)), (.action, .link(let link)):
            if let url = link.url { openItem(.url(url)) }
        case (.action, .task(let task)):
            if let action = task.action { openItem(action) } else { show(confirmation: "This task has no action") }
        case (.toggle, .task(let task)):
            withAnimation(reduceMotion ? nil : Tokens.Motion.quick) { store.toggleCompleted(task) }
            DispatchQueue.main.asyncAfter(deadline: .now() + LibraryStore.lingerSeconds + 0.05) {
                withAnimation(reduceMotion ? nil : Tokens.Motion.quick) { store.reload() }
            }
        case (.toggle, .link(let link)) where link.list == .watchLater:
            store.setWatched(link, !link.isWatched)
        case (.delete, .task(let task)):
            store.delete(task)
            show(confirmation: "Task deleted  ·  ⌘Z to undo")
        case (.delete, .note(let note)):
            store.delete(note)
            show(confirmation: "Note deleted  ·  ⌘Z to undo")
        case (.delete, .link(let link)):
            store.delete(link)
            show(confirmation: "Link deleted  ·  ⌘Z to undo")
        case (.pin, .task(let task)):
            store.setImportant(task, !task.isImportant)
        case (.pin, .note(let note)):
            store.setPinned(note, !note.isPinned)
        case (.pin, .link(let link)):
            store.setPinned(link, !link.isPinned)
        case (.moveSpace(let step), _):
            moveToSpace(item, step: step)
        case (.switchList, _) where tab == .links:
            linkList = linkList == .saved ? .watchLater : .saved
        default:
            break
        }
    }

    private func moveToSpace(_ item: NavItem, step: Int) {
        let spaces = store.spaces
        let currentID: UUID? = switch item {
        case .task(let task): task.space?.id
        case .note(let note): note.space?.id
        case .link(let link): link.space?.id
        }
        guard !spaces.isEmpty else { return }
        let index = spaces.firstIndex { $0.id == currentID } ?? 0
        let target = spaces[(index + step + spaces.count) % spaces.count]
        switch item {
        case .task(let task): store.move(task, to: target)
        case .note(let note): store.move(note, to: target)
        case .link(let link): store.move(link, to: target)
        }
        show(confirmation: "Moved to \(target.name)  ·  ⌘Z to undo")
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

    /// New Spaces come from the capture bar, so there is never a dialog.
    private func startNewSpace() {
        if !capture.text.contains("#") {
            capture.text = capture.text.isEmpty ? "#" : capture.text + " #"
        }
        captureFocused = true
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
                .help("\(item.rawValue) (⌘\((PanelTab.allCases.firstIndex(of: item) ?? 0) + 1))")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        Group {
            if tab == .tasks {
                VStack(spacing: 0) {
                    taskHeader
                    tasksList
                }
            } else if tab == .notes {
                NotesPane(store: store, density: density, space: selectedSpace, showsSpace: selectedSpaceID == nil,
                          openNoteID: $openNoteID, onNewNote: startNewNote, onClose: { captureFocused = true },
                          onConfirm: { show(confirmation: $0) })
            } else if tab == .links {
                LinksPane(store: store, density: density, space: selectedSpace, showsSpace: selectedSpaceID == nil, list: $linkList,
                          addRequests: presentation.addLinkRequests)
            } else if reviewing {
                MorningReviewCard(store: store, onFreshStart: letGoOfReview, onDone: closeReview)
            } else {
                VStack(spacing: 0) {
                    taskHeader
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: density.sectionGap) {
                                todayContent
                            }
                            .padding(Tokens.Spacing.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .modifier(FollowSelection(proxy: proxy))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : Tokens.Surface.contentOpacity),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
    }

    /// Today shows the date, Tasks how many are open; both add a task by hand on the right.
    @ViewBuilder private var taskHeader: some View {
        PaneHeader(addTitle: "New task", addHelp: tab == .today ? "Add a task due today" : "Add a task", onAdd: {
            closeSearch()
            addingTask = true
        }) {
            Group {
                if tab == .today {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                } else {
                    let count = store.open(in: selectedSpace).count
                    Text(count == 1 ? "1 open" : "\(count) open")
                }
            }
            .font(Tokens.TextRole.detail.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if tab == .tasks { tasksMenu }
        }
        if confirmingFreshStart, tab == .tasks { freshStartConfirmation }
        if addingTask {
            InlineAddField(placeholder: tab == .today ? "New task for today" : "New task", symbol: "circle",
                           onSave: addTask, onClose: closeAddTask)
        }
    }

    /// Typed by hand into the list's own field. The same words as the capture bar work:
    /// #space, today, tomorrow and !. On Today, a task without a date is due today.
    private func addTask(_ text: String) -> Bool {
        var parsed = CaptureParser.parse(text, spaceNames: store.spaces.map(\.name))
        if parsed.title.isEmpty, let url = parsed.url { parsed.title = LinkClassifier.displayHost(url) }
        if tab == .today, parsed.due == nil { parsed.due = Calendar.current.startOfDay(for: Date()) }
        guard let task = store.add(parsed, currentSpace: selectedSpace) else { return false }
        show(confirmation: "Added to \(task.space?.name ?? "Tasks")  ·  ⌘Z to undo")
        return true
    }

    private func closeAddTask() {
        addingTask = false
        captureFocused = true
    }

    @ViewBuilder private var todayContent: some View {
        let today = store.dueToday(in: selectedSpace)
        let overdue = store.overdue(in: selectedSpace)
        if today.isEmpty && overdue.isEmpty {
            emptyState(symbol: "sun.max", title: "Nothing planned for today",
                       detail: "Add a task, or type one below with “today” in it.")
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

    private var tasksMenu: some View {
        Menu {
            Button("Fresh start…") { withAnimation(Tokens.Motion.quick) { confirmingFreshStart = true } }
                .disabled(store.open(in: selectedSpace).isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle").font(Tokens.TextRole.detail).foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More task actions")
    }

    /// Asked in the list rather than in a dialog, which would pull focus from the app you're in.
    private var freshStartConfirmation: some View {
        let count = store.open(in: selectedSpace).count
        return HStack(spacing: Tokens.Spacing.s) {
            Text(count == 1 ? "Let go of 1 open task?" : "Let go of \(count) open tasks?").lineLimit(1)
            Spacer(minLength: Tokens.Spacing.xs)
            Button("Cancel") { withAnimation(Tokens.Motion.quick) { confirmingFreshStart = false } }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button("Let Go") {
                let total = store.freshStart(in: selectedSpace)
                confirmingFreshStart = false
                show(confirmation: "\(total) set aside  ·  ⌘Z to undo")
            }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(Color.brand)
        }
        .font(Tokens.TextRole.detail)
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.s)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
        .padding(.horizontal, Tokens.Spacing.s)
        .padding(.top, Tokens.Spacing.xs)
        .transition(.opacity)
    }

    // MARK: Morning review

    private var reviewCount: Int { store.leftFromBefore().count + store.pausedRepeating().count }

    private func startMorningReviewIfDue() {
        guard !presentation.showWelcome else { return }
        switch presentation.reviewPolicy {
        case .never: return
        case .always: break
        case .daily: guard MorningReviewSchedule.claimToday() else { return }
        }
        guard reviewCount > 0 else { return }
        closeSearch()
        tab = .today
        reviewing = true
    }

    private func closeReview() {
        withAnimation(reduceMotion ? nil : Tokens.Motion.quick) { reviewing = false }
        captureFocused = true
    }

    private func letGoOfReview(_ shown: [TaskItem]) {
        store.setAside(shown)
        closeReview()
        show(confirmation: "\(shown.count) set aside  ·  ⌘Z to undo")
    }

    @ViewBuilder private var tasksList: some View {
        let open = store.open(in: selectedSpace)
        let done = store.done(in: selectedSpace)
        let setAside = store.setAsideTasks(in: selectedSpace)
        if open.isEmpty && done.isEmpty && setAside.isEmpty {
            VStack {
                emptyState(symbol: "checklist", title: "No tasks here yet", detail: "Add one, or type below and press Return.")
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
                if !setAside.isEmpty {
                    Button { withAnimation(Tokens.Motion.quick) { showSetAside.toggle() } } label: {
                        Label("Set aside (\(setAside.count))", systemImage: showSetAside ? "chevron.down" : "chevron.right")
                            .font(Tokens.TextRole.sectionTitle)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Tasks you let go. Right-click one to bring it back.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    if showSetAside {
                        ForEach(setAside) { task in
                            taskRow(task).listRowBackground(Color.clear).listRowSeparator(.hidden).id(task.id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .modifier(FollowSelection(proxy: proxy))
            .onChange(of: highlightedTaskID) { _, id in
                guard let id else { return }
                withAnimation(Tokens.Motion.quick) { proxy.scrollTo(id, anchor: .center) }
            }
            }
        }
    }

    private func highlight(_ task: TaskItem) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
            .fill(task.id == highlightedTaskID ? (task.space?.tint ?? .brand).opacity(0.18) : .clear)
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

    /// One button for the current Space; the menu lists them all and starts a new one.
    /// It scales to any number of Spaces, where a row of chips ran out of room.
    private var spaceMenu: some View {
        let space = selectedSpace
        return Menu {
            Picker("Space", selection: $selectedSpaceID) {
                Label("All Spaces", systemImage: "square.grid.2x2").tag(UUID?.none)
                ForEach(store.spaces) { item in
                    Label(item.name, systemImage: item.symbol).tag(Optional(item.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("New Space…", systemImage: "plus", action: startNewSpace)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: space?.symbol ?? "square.grid.2x2")
                    .foregroundStyle(space?.tint ?? .brand)
                Text(space?.name ?? "All Spaces")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(Tokens.TextRole.detail.weight(.semibold))
            .padding(.horizontal, Tokens.Spacing.s + 2)
            .padding(.vertical, Tokens.Spacing.xs + 1)
            .background(.quaternary, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a Space (⌘[ and ⌘] switch)")
        .accessibilityLabel("Space: \(space?.name ?? "All Spaces")")
    }

    /// The Space menu on the left; search, pin and Settings as quiet icons on the right.
    private var header: some View {
        HStack(spacing: Tokens.Spacing.s) {
            spaceMenu
            Spacer(minLength: Tokens.Spacing.s)
            HStack(spacing: 2) {
                iconButton(search.active ? "magnifyingglass.circle.fill" : "magnifyingglass", help: "Search (⌘F)", label: "Search") {
                    if search.active { closeSearch() } else { search.requests += 1 }
                }
                iconButton(presentation.pinned ? "pin.fill" : "pin",
                           help: presentation.pinned ? "Unpin: close when you click away" : "Pin: keep open when you click away",
                           label: presentation.pinned ? "Unpin panel" : "Pin panel open") {
                    presentation.pinned.toggle()
                }
                iconButton("gearshape", help: "Settings (⌘,)", label: "Settings") { presentation.openSettings() }
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Tokens.TextRole.detail)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
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
    /// The save-tab shortcut while the panel is open, so the chip and the confirmation line stay right.
    var saveTab: ((BrowserTab.Browser) -> Void)?
}
