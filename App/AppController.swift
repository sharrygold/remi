import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate {
    let options = Options()

    var handle: HandleWindow!

    var panel: PanelWindow!

    var statusItem: NSStatusItem!

    var outsideClickMonitor: Any?

    lazy var companion = CompanionSettings(style: options.widget, plumage: options.plumage)

    /// The companion's view, which is swapped when the style changes.
    var surface: CompanionSurface!

    var host: CompanionHostView!

    var onLeftEdge = false

    let presentation = PanelPresentation()

    let capture = CaptureText()

    let search = SearchState()

    let nav = ListNavigation()

    lazy var reminders = Reminders(store: store)

    var settingsWindow: NSWindow?

    var watchers: [AnyCancellable] = []

    /// Self-tests and demos keep everything in memory and must not show permission prompts or write backups.
    var isScratchSession: Bool {
        ["--demo-data", "--m2-selftest", "--m3-selftest", "--m4-selftest", "--m5-selftest", "--m6-selftest", "--clipboard-selftest", "--add-selftest"]
            .contains { CommandLine.arguments.contains($0) }
    }

    lazy var store: LibraryStore = {
        let arguments = CommandLine.arguments
        let usesMemory = ["--demo-data", "--m2-selftest", "--m3-selftest", "--m4-selftest", "--m5-selftest", "--m6-selftest", "--clipboard-selftest", "--add-selftest"].contains { arguments.contains($0) }
        // --data-dir=PATH opens another library, used to check a copy of real data after a model change.
        let custom = arguments.first { $0.hasPrefix("--data-dir=") }.map { URL(fileURLWithPath: String($0.dropFirst("--data-dir=".count))) }
        let store = LibraryStore(directory: usesMemory ? nil : custom ?? LibraryStore.defaultDirectory)
        if custom != nil {
            print("data-dir temporary=\(store.isTemporary) spaces=\(store.spaces.count) tasks=\(store.tasks.count) notes=\(store.notes.count)")
        }
        if CommandLine.arguments.contains("--demo-data") { seedDemo(store) }
        return store
    }()

    lazy var metadata = LinkMetadataFetcher(store: store)

    var hotKey: HotKey?

    var hotKeyRegistered = false

    var saveTabHotKey: HotKey?

    var appearanceMenu: NSMenu?

    var lastActivity = Date()

    var hiddenUntil: Date?

    let showNowItem = NSMenuItem(title: "Show Widget Now", action: #selector(showWidgetNow), keyEquivalent: "")

    /// The same as the cord, so both companions tuck away at the same moment.
    static let idleSecondsBeforeTuck: TimeInterval = CordMotion.awayDelay

    static let idleSecondsBeforeDoze: TimeInterval = 45

    static let panelSizeKey = "panelSize"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // --export-json=PATH writes the same JSON as Settings > Data > Export. Use with --data-dir=.
        if let path = CommandLine.arguments.first(where: { $0.hasPrefix("--export-json=") })?.dropFirst("--export-json=".count) {
            do {
                let archive = store.makeArchive()
                try LibraryArchive.encoder().encode(archive).write(to: URL(fileURLWithPath: String(path)), options: .atomic)
                print("exported tasks=\(archive.tasks.count) notes=\(archive.notes.count) links=\(archive.links.count) spaces=\(archive.spaces.count)")
            } catch {
                print("export failed: \(error.localizedDescription)")
            }
            exit(0)
        }
        if !isScratchSession { CompanionSize.keepChosenSizeAfterRescale() }
        SettingsKey.registerDefaults()
        store.rollForwardRepeating()
        applyAppearance()
        store.onLinkAdded = { [weak self] link in
            self?.metadata.fetch(link)
            self?.refreshCompanion(event: .linkCaught)
        }
        presentation.closeAfterOpening = { [weak self] in
            guard let self, !self.presentation.pinned else { return }
            self.hidePanel()
        }
        buildWidget()
        buildPanel()
        buildStatusItem()
        applyAppearance()
        registerHotKey()
        applyWindowSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        watchers.append(companion.$style.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyStyle() }
        })
        watchers.append(companion.$size.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyStyle() }
        })
        presentation.openSettings = { [weak self] in self?.openSettings() }
        presentation.close = { [weak self] in self?.hidePanel() }
        presentation.reviewPolicy = CommandLine.arguments.contains("--preview-review") ? .always : isScratchSession ? .never : .daily
        reminders.onOpen = { [weak self] in self?.showPanel() }
        if !isScratchSession {
            reminders.start()
            runDailyMaintenance()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.makeSettingsWindow() }
        installEditMenu()
        installPanelKeys()
        NotificationCenter.default.addObserver(self, selector: #selector(dayChanged), name: .NSCalendarDayChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.idleTick() }
        if let text = CommandLine.arguments.first(where: { $0.hasPrefix("--capture=") }) {
            capture.text = String(text.dropFirst("--capture=".count))
            // For screenshots: the cursor at the end of the typed line, not the whole line selected.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                guard let editor = panel.firstResponder as? NSTextView else { return }
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
        if let text = CommandLine.arguments.first(where: { $0.hasPrefix("--search=") }) {
            search.active = true
            search.query = String(text.dropFirst("--search=".count))
        }
        presentation.widget = companion
        presentation.onWelcomeDone = { [weak self] in self?.finishWelcome() }
        if options.open { showPanel() }
        showWelcomeOnFirstRun()
        // For screenshots of the closing animation: --close-at=SECONDS closes the panel then.
        if let text = CommandLine.arguments.first(where: { $0.hasPrefix("--close-at=") }),
           let seconds = Double(text.dropFirst("--close-at=".count)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { self.hidePanel() }
        }
        // For screenshots: --add opens the current tab's "+" field once the panel is up.
        if CommandLine.arguments.contains("--add") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.presentation.addRequests += 1 }
        }
        // For screenshots: --space-step=1 picks the first Space after All.
        if let step = CommandLine.arguments.first(where: { $0.hasPrefix("--space-step=") }).flatMap({ Int($0.dropFirst("--space-step=".count)) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.nav.switchSpace(step) }
        }
        // For screenshots: show the keyboard selection on the first row.
        // For checking motion: switch tab 2 s after opening, so frames can be captured mid-glide.
        if CommandLine.arguments.contains("--preview-tab-switch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.nav.switchTab(3) }
        }
        if CommandLine.arguments.contains("--select-first") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.nav.move(1) }
        }
        // --settings=Spaces opens Settings on that section, without the widget, for screenshots.
        if let name = CommandLine.arguments.first(where: { $0.hasPrefix("--settings=") })?.dropFirst("--settings=".count) {
            handle.orderOut(nil)
            showSettings(tab: SettingsTab.allCases.first { $0.rawValue.replacingOccurrences(of: " ", with: "").lowercased() == name.lowercased() } ?? .general)
        }
        if CommandLine.arguments.contains("--open-note") {
            DispatchQueue.main.async { self.presentation.noteToOpen = self.store.notes(in: nil).dropFirst().first?.id }
        }
        if CommandLine.arguments.contains("--m1-selftest") { runShellSelfTest() }
        if CommandLine.arguments.contains("--m2-selftest") { runCaptureSelfTest() }
        if CommandLine.arguments.contains("--m3-selftest") { runNotesSelfTest() }
        if CommandLine.arguments.contains("--m4-selftest") { runLinksSelfTest() }
        if CommandLine.arguments.contains("--m5-selftest") { runSearchSelfTest() }
        if CommandLine.arguments.contains("--m6-selftest") { runKeyboardSelfTest() }
        if CommandLine.arguments.contains("--size-selftest") {
            // Hidden, so it never takes keyboard focus.
            print("start content=\(panel.contentLayoutRect.size) temporary=\(store.isTemporary)")
            panel.setContentSize(NSSize(width: 460, height: 760))
            panel.layoutIfNeeded()
            print("resized content=\(panel.contentLayoutRect.size) hosting=\(panel.contentView?.frame.size ?? .zero)")
            panel.setContentSize(NSSize(width: 100, height: 100))
            print("too small asked, got=\(panel.contentLayoutRect.size) (min \(Tokens.Size.panelMin))")
            NSApp.terminate(nil)
        }
        if CommandLine.arguments.contains("--hit-selftest") {
            // A coarse map of the widget window: # catches clicks, . lets them through.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                let size = handle.frame.size
                for row in stride(from: 4, through: size.height, by: 8) {
                    print(stride(from: 4, through: size.width, by: 8).map { x in
                        surface.isHit(CGPoint(x: x, y: row)) ? "#" : "."
                    }.joined())
                }
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--head-selftest") { runHeadSelfTest() }
        if CommandLine.arguments.contains("--motion-selftest") { runMotionSelfTest() }
        if CommandLine.arguments.contains("--tuck-selftest") { runTuckSelfTest() }
        if CommandLine.arguments.contains("--clipboard-selftest") { runClipboardChipSelfTest() }
        if CommandLine.arguments.contains("--add-selftest") { runAddSelfTest() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    func configure(_ window: NSPanel) {
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
    }

    /// Applies the Settings that change windows: screen-recording visibility and full-screen apps.
    func applyWindowSettings() {
        let defaults = UserDefaults.standard
        let hidden = defaults.bool(forKey: SettingsKey.hideFromRecordings) && !options.allowCapture
        for window in [handle, panel].compactMap({ $0 }) {
            window.sharingType = hidden ? .none : .readOnly
        }
        guard let handle else { return }
        if defaults.bool(forKey: SettingsKey.showOverFullScreen) {
            handle.collectionBehavior.insert(.fullScreenAuxiliary)
        } else {
            handle.collectionBehavior.remove(.fullScreenAuxiliary)
        }
    }

    /// Light, dark or following the Mac. A launch flag wins, for screenshots.
    func applyAppearance() {
        let choice = options.appearance ?? UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "system"
        let wanted: NSAppearance? = switch choice {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
        if NSApp.appearance?.name != wanted?.name { NSApp.appearance = wanted }
        for item in appearanceMenu?.items ?? [] { item.state = (item.representedObject as? String) == choice ? .on : .off }
        refreshStatusMenu()
    }

    /// Companion, size and colour, for changing the bird while you're looking at it.
    func companionMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Companion", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Companion")
        func add(_ title: String, _ value: String, _ selector: Selector, on: Bool) {
            let entry = menu.addItem(withTitle: title, action: selector, keyEquivalent: "")
            entry.target = self
            entry.representedObject = value
            entry.state = on ? .on : .off
        }
        for style in CompanionStyle.allCases { add(style.title, style.rawValue, #selector(chooseStyle(_:)), on: companion.style == style) }
        menu.addItem(.sectionHeader(title: "Size"))
        for size in CompanionSize.allCases { add(size.title, size.rawValue, #selector(chooseSize(_:)), on: companion.size == size) }
        menu.addItem(.sectionHeader(title: "Colour"))
        for plumage in Plumage.allCases { add(plumage.title, plumage.rawValue, #selector(choosePlumage(_:)), on: companion.plumage == plumage) }
        item.submenu = menu
        return item
    }

    @objc func chooseStyle(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let style = CompanionStyle(rawValue: value) { companion.style = style }
        refreshStatusMenu()
    }

    @objc func chooseSize(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let size = CompanionSize(rawValue: value) { companion.size = size }
        refreshStatusMenu()
    }

    @objc func choosePlumage(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let plumage = Plumage(rawValue: value) { companion.plumage = plumage }
        refreshStatusMenu()
    }

    /// The menu bar menu is built once, so its Companion ticks are rebuilt after a change.
    func refreshStatusMenu() {
        guard let menu = statusItem?.menu, let index = menu.items.firstIndex(where: { $0.title == "Companion" }) else { return }
        menu.removeItem(at: index)
        menu.insertItem(companionMenuItem(), at: index)
    }

    @objc func chooseAppearance(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        UserDefaults.standard.set(value, forKey: SettingsKey.appearance)
    }

    @objc func settingsChanged() {
        DispatchQueue.main.async {
            self.applyWindowSettings()
            self.applyAppearance()
            self.refreshCompanion(event: nil)
        }
    }

    /// Clears Recently deleted items older than 30 days and writes today's backup, once per day.
    func runDailyMaintenance() {
        store.purgeDeleted()
        guard let directory = store.directory else { return }
        do {
            try Backups.backUp({ store.makeArchive() }, to: Backups.directory(in: directory))
        } catch {
            NSLog("Daily backup failed: \(error.localizedDescription)")
        }
    }

    var settingsContext: SettingsContext?

    /// Without a main menu, ⌘C, ⌘V and friends do nothing in text fields.
    func installEditMenu() {
        let main = NSMenu()
        let editItem = main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    /// First launch only. Someone who already has things saved has no need of it.
    func showWelcomeOnFirstRun() {
        if CommandLine.arguments.contains("--preview-welcome") {
            showWelcome()
            return
        }
        guard !isScratchSession, !UserDefaults.standard.bool(forKey: SettingsKey.welcomeSeen) else { return }
        if store.tasks.isEmpty && store.notes.isEmpty && store.links.isEmpty {
            showWelcome()
        } else {
            UserDefaults.standard.set(true, forKey: SettingsKey.welcomeSeen)
        }
    }

    func showWelcome() {
        presentation.showWelcome = true
        showPanel()
    }

    func finishWelcome() {
        presentation.showWelcome = false
        if !CommandLine.arguments.contains("--preview-welcome") {
            UserDefaults.standard.set(true, forKey: SettingsKey.welcomeSeen)
        }
    }

    @objc func dayChanged() {
        DispatchQueue.main.async {
            self.store.reload()
            self.store.rollForwardRepeating()
            if !self.isScratchSession { self.runDailyMaintenance() }
        }
    }

    func registerHotKey() {
        let key = HotKey { [weak self] in DispatchQueue.main.async { self?.togglePanel() } }
        hotKeyRegistered = key.register(HotKeyCombo.saved)
        if !hotKeyRegistered { NSLog("Global shortcut \(HotKeyCombo.saved.display) could not be registered") }
        hotKey = key
        let saveKey = HotKey { [weak self] in Task { @MainActor in self?.saveFrontTab() } }
        if !saveKey.register(HotKeyCombo.savedSaveTab) { NSLog("Save-tab shortcut \(HotKeyCombo.savedSaveTab.display) could not be registered") }
        saveTabHotKey = saveKey
    }

    /// The save-tab shortcut, from anywhere. With the panel closed, the companion is the confirmation.
    @MainActor func saveFrontTab() {
        guard let browser = BrowserTab.frontmost() else {
            NSSound.beep()
            return
        }
        if presentation.presented, capture.saveTab?(browser) != nil { return }
        switch BrowserTab.read(browser) {
        case .success(let page):
            lastActivity = Date()
            perched?.setTucked(false)
            perched?.setDozing(false)
            let saved = store.addLink(page.url, currentSpace: nil)
            if saved.isNew {
                store.setMetadata(for: saved.link.id, title: page.title, iconData: nil)
            } else {
                refreshCompanion(event: .linkCaught)
            }
        case .failure(.notAllowed):
            presentation.showWelcome = false
            showPanel()
            presentation.message = "Allow \(browser.name) in System Settings > Privacy & Security > Automation"
        case .failure:
            NSSound.beep()
        }
    }

    func showRightClickMenu(event: NSEvent, view: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Task", action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Note", action: #selector(newNoteFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(companionMenuItem())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide for 1 Hour", action: #selector(hideForAnHour), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc func openPanelFromMenu() { showPanel() }

    @objc func checkForUpdates() { AppInfo.checkForUpdates() }

    @objc func newNoteFromMenu() {
        showPanel()
        presentation.newNoteRequests += 1
    }

    @objc func hideForAnHour() {
        hiddenUntil = Date().addingTimeInterval(3600)
        handle.orderOut(nil)
        showNowItem.isHidden = false
    }

    @objc func showWidgetNow() {
        hiddenUntil = nil
        handle.orderFrontRegardless()
        showNowItem.isHidden = true
        lastActivity = Date()
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Black on transparent; as a template image macOS recolours it for light and dark menu bars.
        let glyph = Bundle.main.url(forResource: "menubar-template", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        glyph?.size = NSSize(width: 19, height: 18)
        glyph?.isTemplate = true
        glyph?.accessibilityDescription = AppInfo.displayName
        statusItem.button?.image = glyph
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Panel", action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        showNowItem.target = self
        showNowItem.isHidden = true
        menu.addItem(showNowItem)
        menu.addItem(.separator())
        let appearanceItem = menu.addItem(withTitle: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "Appearance")
        for (title, value) in [("Automatic", "system"), ("Light", "light"), ("Dark", "dark")] {
            let item = appearanceMenu.addItem(withTitle: title, action: #selector(chooseAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
        }
        appearanceItem.submenu = appearanceMenu
        self.appearanceMenu = appearanceMenu
        menu.addItem(companionMenuItem())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu
    }
}
