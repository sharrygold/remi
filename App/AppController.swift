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

    static let birdNoticeRadius: CGFloat = 130

    var birdLookAway: DispatchWorkItem?

    lazy var debug: WidgetDebug = {
        let debug = WidgetDebug(prototype: options.widget, colour: options.colour)
        debug.previewHover = CommandLine.arguments.contains("--preview-hover")
        debug.previewLook = options.previewLook
        return debug
    }()

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

    var lastActivity = Date()

    var hiddenUntil: Date?

    let showNowItem = NSMenuItem(title: "Show Widget Now", action: #selector(showWidgetNow), keyEquivalent: "")

    static let idleSecondsBeforeTuck: TimeInterval = 4

    static let panelSizeKey = "panelSize"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A login item can only be removed by the app that added it, so the last build under the
        // old identity does this once and leaves a note for the rename's migration.
        if CommandLine.arguments.contains("--retire-login-item") {
            let service = SMAppService.mainApp
            let wasEnabled = service.status == .enabled
            UserDefaults.standard.set(wasEnabled, forKey: "loginItemWasEnabled")
            UserDefaults.standard.synchronize()
            do { try service.unregister() } catch { print("unregister: \(error.localizedDescription)") }
            print("login item was enabled=\(wasEnabled), now status=\(service.status.rawValue)")
            exit(0)
        }
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
        SettingsKey.registerDefaults()
        store.rollForwardRepeating()
        if let name = options.appearance {
            NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
        }
        if CommandLine.arguments.contains("--cord-selftest") {
            runCordSelfTest()
            exit(0)
        }
        if options.gallery {
            buildGallery()
            return
        }
        store.onLinkAdded = { [weak self] link in self?.metadata.fetch(link) }
        presentation.closeAfterOpening = { [weak self] in
            guard let self, !self.presentation.pinned else { return }
            self.hidePanel()
        }
        if let style = options.handle { buildGalleryHandle(style) } else { buildWidget() }
        buildPanel()
        buildStatusItem()
        registerHotKey()
        applyWindowSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        watchers.append(debug.$prototype.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyPrototype() }
        })
        presentation.openSettings = { [weak self] in self?.openSettings() }
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
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.idleTick() }
        if let text = CommandLine.arguments.first(where: { $0.hasPrefix("--capture=") }) {
            capture.text = String(text.dropFirst("--capture=".count))
        }
        if let text = CommandLine.arguments.first(where: { $0.hasPrefix("--search=") }) {
            search.active = true
            search.query = String(text.dropFirst("--search=".count))
        }
        presentation.widget = debug
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
        if CommandLine.arguments.contains("--preview-tuck") { debug.tucked = true }
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
                guard let view = handle.contentView else { return }
                let size = view.bounds.size
                for row in stride(from: size.height - 4, through: 0, by: -8) {
                    print(stride(from: 4, through: size.width, by: 8).map { x in
                        WidgetHitTest.isDrawn(at: NSPoint(x: x, y: row), in: view) ? "#" : "."
                    }.joined())
                }
                NSApp.terminate(nil)
            }
        }
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

    @objc func settingsChanged() {
        DispatchQueue.main.async { self.applyWindowSettings() }
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
    }

    func showRightClickMenu(event: NSEvent, view: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Task", action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Note", action: #selector(newNoteFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide for 1 Hour", action: #selector(hideForAnHour), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc func openPanelFromMenu() { showPanel() }

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
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: AppInfo.displayName)
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Panel", action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        showNowItem.target = self
        showNowItem.isHidden = true
        menu.addItem(showNowItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu
    }
}
