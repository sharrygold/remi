import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

enum AppInfo {
    /// The single source for the name shown in UI; set by APP_DISPLAY_NAME in project.yml.
    static let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App"
}

/// Phase 1 review switches, e.g. --handle=tile --density=compact --tab=notes --open --appearance=dark
struct Options {
    private static func value(_ key: String) -> String? {
        CommandLine.arguments.first { $0.hasPrefix("--\(key)=") }?.split(separator: "=").last.map(String.init)
    }
    let handle = value("handle").flatMap(HandleStyle.init)
    let widget = value("widget").flatMap(WidgetPrototype.init)
    let colour = value("colour").flatMap(WidgetColour.init)
    let previewPull = value("preview-pull").flatMap { Double($0) }.map { CGFloat($0) }
    let previewLook: CGPoint? = value("preview-look").flatMap { text in
        let parts = text.split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }
    let density = value("density").flatMap(Density.init) ?? .comfortable
    let tab = value("tab").flatMap { name in PanelTab.allCases.first { $0.rawValue.lowercased() == name } } ?? .today
    let appearance = value("appearance")
    let open = CommandLine.arguments.contains("--open")
    let allowCapture = CommandLine.arguments.contains("--allow-capture")
    let gallery = CommandLine.arguments.contains("--gallery")
}

final class HandleWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns every mouse event on the handle, so clicks and drags never depend on SwiftUI gestures
/// or on how see-through the glass is at the pointer.
final class HandleHostingView<Content: View>: NSHostingView<Content> {
    var onClick: (() -> Void)?
    /// When this returns true, dragging pulls instead of moving the window.
    var isPullMode: () -> Bool = { false }
    var onPull: ((CGFloat, CGFloat) -> Void)?
    var onPullEnd: (() -> Void)?
    /// Receives the window's new left edge when a cord drag goes sideways.
    var onSlide: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var sliding = false
    private var grabOffset = NSPoint.zero
    private var downMouse = NSPoint.zero
    private var dragged = false
    private let dragThreshold: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event, self)
    }

    override func mouseDown(with event: NSEvent) {
        let origin = window?.frame.origin ?? .zero
        downMouse = NSEvent.mouseLocation
        grabOffset = NSPoint(x: downMouse.x - origin.x, y: downMouse.y - origin.y)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        if !dragged && hypot(mouse.x - downMouse.x, mouse.y - downMouse.y) < dragThreshold { return }
        if !dragged { sliding = abs(mouse.x - downMouse.x) > abs(mouse.y - downMouse.y) }
        dragged = true
        if isPullMode() {
            if sliding {
                onSlide?(mouse.x - grabOffset.x)
            } else {
                onPull?(mouse.x - downMouse.x, downMouse.y - mouse.y)
            }
            return
        }
        window?.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if isPullMode() && dragged {
            if sliding { onDragEnd?() } else { onPullEnd?() }
            return
        }
        if dragged {
            onDragEnd?()
            return
        }
        if !dragged && event.clickCount == 1 { onClick?() }
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    private let options = Options()
    private var handle: HandleWindow!
    private var panel: PanelWindow!
    private var statusItem: NSStatusItem!
    private var outsideClickMonitor: Any?
    private static let birdNoticeRadius: CGFloat = 130
    private var birdLookAway: DispatchWorkItem?
    private lazy var debug: WidgetDebug = {
        let debug = WidgetDebug(prototype: options.widget, colour: options.colour)
        debug.previewHover = CommandLine.arguments.contains("--preview-hover")
        debug.previewLook = options.previewLook
        return debug
    }()
    private let widgetMenu = NSMenu()
    private let colourMenu = NSMenu()
    private let presentation = PanelPresentation()
    private let capture = CaptureText()
    private lazy var store: LibraryStore = {
        let arguments = CommandLine.arguments
        let usesMemory = ["--demo-data", "--m2-selftest", "--m3-selftest", "--m4-selftest", "--clipboard-selftest"].contains { arguments.contains($0) }
        // --data-dir=PATH opens another library, used to check a copy of real data after a model change.
        let custom = arguments.first { $0.hasPrefix("--data-dir=") }.map { URL(fileURLWithPath: String($0.dropFirst("--data-dir=".count))) }
        let store = LibraryStore(directory: usesMemory ? nil : custom ?? LibraryStore.defaultDirectory)
        if custom != nil {
            print("data-dir temporary=\(store.isTemporary) spaces=\(store.spaces.count) tasks=\(store.tasks.count) notes=\(store.notes.count)")
        }
        if CommandLine.arguments.contains("--demo-data") { seedDemo(store) }
        return store
    }()
    private lazy var metadata = LinkMetadataFetcher(store: store)
    private var hotKey: HotKey?
    private var hotKeyRegistered = false
    private var lastActivity = Date()
    private var hiddenUntil: Date?
    private let showNowItem = NSMenuItem(title: "Show Widget Now", action: #selector(showWidgetNow), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private static let idleSecondsBeforeTuck: TimeInterval = 4

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        installEditMenu()
        installPanelKeys()
        NotificationCenter.default.addObserver(self, selector: #selector(dayChanged), name: .NSCalendarDayChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.idleTick() }
        if let text = CommandLine.arguments.first(where: { $0.hasPrefix("--capture=") }) {
            capture.text = String(text.dropFirst("--capture=".count))
        }
        if options.open { showPanel() }
        if CommandLine.arguments.contains("--open-note") {
            DispatchQueue.main.async { self.presentation.noteToOpen = self.store.notes(in: nil).dropFirst().first?.id }
        }
        if CommandLine.arguments.contains("--preview-tuck") { debug.tucked = true }
        if CommandLine.arguments.contains("--m1-selftest") { runShellSelfTest() }
        if CommandLine.arguments.contains("--m2-selftest") { runCaptureSelfTest() }
        if CommandLine.arguments.contains("--m3-selftest") { runNotesSelfTest() }
        if CommandLine.arguments.contains("--m4-selftest") { runLinksSelfTest() }
        if CommandLine.arguments.contains("--clipboard-selftest") { runClipboardChipSelfTest() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    private func configure(_ window: NSPanel) {
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.sharingType = options.allowCapture ? .readOnly : .none
    }

    private func makeHandleWindow(frame: NSRect) -> HandleWindow {
        let window = HandleWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(window)
        window.hasShadow = false
        // Without this, macOS lets clicks fall through wherever the window's pixels read as transparent.
        window.ignoresMouseEvents = false
        return window
    }

    /// Puts the widget back where it last was on the best available display.
    private func widgetFrame() -> NSRect {
        let prototype = debug.prototype
        let screen = PlacementStore.preferredScreen(for: prototype)
        var placement = PlacementStore.load(prototype: prototype, on: screen) ?? .standard(for: prototype)
        if CommandLine.arguments.contains("--preview-left") { placement.onLeftEdge = true }
        debug.onLeftEdge = placement.onLeftEdge
        return placement.frame(for: prototype, on: screen.visibleFrame)
    }

    @objc private func screensChanged() {
        guard options.handle == nil else { return }
        handle.setFrame(widgetFrame(), display: true)
    }

    /// Snaps to the nearest edge with a soft overshoot, then remembers the spot.
    private func finishDrag() {
        lastActivity = Date()
        let prototype = debug.prototype
        let screen = handle.screen ?? NSScreen.screens[0]
        let placement = WidgetPlacement.nearest(to: handle.frame, prototype: prototype, on: screen.visibleFrame)
        PlacementStore.save(placement, prototype: prototype, on: screen)
        debug.onLeftEdge = placement.onLeftEdge
        let target = placement.frame(for: prototype, on: screen.visibleFrame)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            handle.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.25, 0.5, 1)
            handle.animator().setFrame(target, display: true)
        }
    }

    private func idleTick() {
        if let until = hiddenUntil, Date() >= until { showWidgetNow() }
        guard options.handle == nil, !debug.tucked, !presentation.presented, NSEvent.pressedMouseButtons == 0,
              UserDefaults.standard.object(forKey: "autoTuck") as? Bool ?? true,
              !isPointerNearWidget(), Date().timeIntervalSince(lastActivity) >= Self.idleSecondsBeforeTuck else { return }
        debug.tucked = true
    }

    private func isPointerNearWidget() -> Bool {
        var zone = handle.frame
        if debug.prototype == .cord {
            zone = NSRect(x: zone.midX - 40, y: zone.maxY - 170, width: 80, height: 170)
        }
        return zone.insetBy(dx: -48, dy: -48).contains(NSEvent.mouseLocation)
    }

    /// Without a main menu, ⌘C, ⌘V and friends do nothing in text fields.
    private func installEditMenu() {
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

    /// Panel-wide keys:
    /// - ⌘Z with the capture field empty undoes the last change to tasks or notes. While typing,
    ///   or inside a note, it undoes the typing instead.
    /// - ⌘Return in the capture field saves a note.
    /// - ⌘N starts a new note.
    /// - Tab on a pasted link switches between Saved links and Watch later.
    private func installPanelKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == UInt16(kVK_Tab), flags.isEmpty, self.capture.isFocused,
               self.capture.toggleLinkList?() == true {
                return nil
            }
            guard flags == .command else { return event }
            let inNote = (self.panel.firstResponder as? NSTextView)?.isFieldEditor == false
            switch event.keyCode {
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                guard self.capture.isFocused, let submit = self.capture.submitNote else { return event }
                submit()
                return nil
            case UInt16(kVK_ANSI_N):
                self.presentation.newNoteRequests += 1
                return nil
            case UInt16(kVK_ANSI_Z):
                guard !inNote, self.capture.text.isEmpty, self.store.canUndo else { return event }
                self.store.undo()
                return nil
            default:
                return event
            }
        }
    }

    @objc private func dayChanged() {
        DispatchQueue.main.async { self.store.reload() }
    }

    private func seedDemo(_ store: LibraryStore) {
        let names = store.spaces.map(\.name)
        for line in ["Book dentist appointment #personal today", "Prepare sprint review notes #work today",
                     "Send design dashboard invoice #clients today", "Record Loom intro for invoice #clients today !",
                     "Tidy the shared drive #clients fri", "Finish SwiftUI layout module #learning tomorrow"] {
            store.add(CaptureParser.parse(line, spaceNames: names), currentSpace: nil)
        }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
        store.add(ParsedCapture(title: "Reply to Dana about the project timeline", space: .existing("Work"), due: yesterday), currentSpace: nil)
        let notes = [
            ("Clients", true, "Invoice opening lines\nStart with their problem, then **one** proof point.\n- Mirror their words\n- Keep it under 120 words"),
            ("Work", false, "Q4 priorities\n## This month\n- [x] Reporting cleanup\n- [ ] Onboarding flow\n- [ ] Vendor review"),
            ("Clients", false, "Loom checklist\n- [ ] Close tabs\n- [ ] Check mic\n- [ ] Keep it under two minutes"),
            ("Personal", false, "Trip ideas\nLisbon in December, ask about flights. https://www.visitlisboa.com"),
        ]
        for (index, (spaceName, pinned, body)) in notes.enumerated() {
            let note = store.newNote(in: store.spaces.first { $0.name == spaceName })
            store.setBody(note, body, now: Date().addingTimeInterval(Double(-index) * 5400))
            if pinned { store.setPinned(note, true) }
        }
        let links = [
            ("https://www.example.com/team/~01example", "Team handbook", "Clients", true),
            ("https://docs.google.com/spreadsheets/d/invoice-tracker", "Invoice tracker", "Clients", false),
            ("https://linear.app/team/dashboard", "Team dashboard", "Work", false),
            ("https://www.youtube.com/watch?v=invoices101", "How to write invoices that win", "Clients", false),
            ("https://www.youtube.com/watch?v=swiftuilayout", "SwiftUI layout, explained", "Learning", false),
        ]
        for (address, title, spaceName, pinned) in links {
            guard let url = URL(string: address) else { continue }
            let link = store.addLink(url, currentSpace: store.spaces.first { $0.name == spaceName }).link
            store.setMetadata(for: link.id, title: title, iconData: nil)
            if pinned { store.setPinned(link, true) }
        }
        if let task = store.tasks.first(where: { $0.title.hasPrefix("Record Loom") }),
           let loom = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.loom.desktop") ?? URL(string: "https://www.loom.com") {
            store.setAction(task, loom.isFileURL ? .app(loom) : .url(loom))
        }
        if let task = store.tasks.first(where: { $0.title.hasPrefix("Send design") }), let url = URL(string: "https://www.example.com/nx/invoices") {
            store.setAction(task, .url(url))
        }
        store.save()
        store.reload()
    }

    private func postKey(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    /// Types into the real capture field and presses real keys through the app's event loop.
    private func runCaptureSelfTest() {
        func describe() -> String {
            store.tasks.map { "\($0.title)|\($0.space?.name ?? "-")|due=\($0.dueDate != nil)|important=\($0.isImportant)" }.joined(separator: "; ")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            showPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                let editor = panel.firstResponder as? NSTextView
                print("field focused=\(editor != nil) widgetCount=\(store.todayOpenCount())")
                editor?.insertText("Send invoice today #newclient !", replacementRange: NSRange(location: NSNotFound, length: 0))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                    print("typed binding=\(capture.text)")
                    postKey("\r", code: 36)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                        print("after Return: \(describe()) spaces=\(store.spaces.count) widgetCount=\(store.todayOpenCount()) field=[\(capture.text)]")
                        postKey("z", code: 6, flags: .command)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                            print("after Cmd-Z: tasks=\(store.tasks.count) spaces=\(store.spaces.count)")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }

    /// Drives notes through real key and mouse events: ⌘Return capture, undo, ⌘N, typed Markdown
    /// shortcuts, a checkbox click, ⌘B, Esc back to the list, and a blank note being discarded.
    private func runNotesSelfTest() {
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        func finish(_ message: String) {
            print(message)
            NSApp.terminate(nil)
        }
        after(1) { [self] in
            showPanel()
            after(0.5) { [self] in
                (panel.firstResponder as? NSTextView)?.insertText("Ideas for today's call #clients", replacementRange: NSRange(location: NSNotFound, length: 0))
                after(0.2) { [self] in
                    postKey("\r", code: 36, flags: .command)
                    after(0.4) { [self] in
                        print("cmd-return notes=\(store.notes.map { "\($0.body)|\($0.space?.name ?? "-")" }) tasks=\(store.tasks.count) field=[\(capture.text)]")
                        postKey("z", code: 6, flags: .command)
                        after(0.4) { [self] in
                            print("after undo notes=\(store.notes.count)")
                            postKey("n", code: 45, flags: .command)
                            after(0.6) { [self] in typeNote(then: finish) }
                        }
                    }
                }
            }
        }
    }

    private func typeNote(then finish: @escaping (String) -> Void) {
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        guard let editor = panel.firstResponder as? NoteTextView else {
            return finish("FAIL editor not focused, responder=\(String(describing: panel.firstResponder))")
        }
        for character in "Groceries\n- milk\n[] eggs\n\nnotes in bold done" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
        let note = store.notes.first
        print("typed markdown=\(note?.body.debugDescription ?? "nil") title=\(note?.title ?? "nil") preview=\(note?.preview ?? "nil")")
        let text = editor.string as NSString
        let box = text.range(of: String(NoteText.checkboxCharacter))
        guard box.location != NSNotFound, let rect = editor.checkboxRect(at: box.location) else { return finish("FAIL no checkbox") }
        let point = editor.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        after(0.3) { [self] in
            print("after click markdown=\(store.notes.first?.body.debugDescription ?? "nil")")
            editor.setSelectedRange((editor.string as NSString).range(of: "bold"))
            postKey("b", code: 11, flags: .command)
            after(0.3) { [self] in
                print("after cmd-b markdown=\(store.notes.first?.body.debugDescription ?? "nil")")
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                editor.insertText("x", replacementRange: editor.selectedRange())
                postKey("z", code: 6, flags: .command)
                after(0.3) { [self] in
                    print("cmd-z in note keeps note=\(store.notes.count == 1) endsWith x=\(editor.string.hasSuffix("x"))")
                    postKey("\u{1b}", code: 53)
                    after(0.4) { [self] in
                        let fieldFocused = (panel.firstResponder as? NSTextView)?.isFieldEditor == true
                        print("after esc capture focused=\(fieldFocused) panel visible=\(panel.isVisible) notes=\(store.notes.count)")
                        postKey("n", code: 45, flags: .command)
                        after(0.5) { [self] in
                            postKey("\u{1b}", code: 53)
                            after(0.4) { [self] in
                                finish("blank note discarded=\(store.notes.count == 1) saved body=\(store.notes.first?.body.debugDescription ?? "nil")")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Pastes a YouTube link and checks its list, title and icon; uses Tab to switch a link's list;
    /// saves a task with a URL as its action; and offers a URL from a private test clipboard.
    private func runLinksSelfTest() {
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        func type(_ text: String) {
            (panel.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        func describe(_ link: LinkItem?) -> String {
            guard let link else { return "nil" }
            return "\(link.title)|\(link.list.rawValue)|\(link.space?.name ?? "-")|icon=\(link.iconData?.count ?? 0)B|fetched=\(link.titleFetched)"
        }
        print("browser=\(LinkOpener.browserURL?.lastPathComponent ?? "system default")")
        after(1) { [self] in
            showPanel()
            after(0.5) { [self] in
                type("https://www.youtube.com/watch?v=jNQXAC9IVRw")
                after(0.2) { [self] in
                    postKey("\r", code: 36)
                    after(0.3) { [self] in
                        print("youtube saved: \(describe(store.links.first)) field=[\(capture.text)]")
                        type("developer.apple.com/documentation/linkpresentation #learning")
                        postKey("\t", code: 48)
                        after(0.3) { [self] in
                            print("after tab override=\(capture.linkListOverride?.rawValue ?? "nil")")
                            postKey("\r", code: 36)
                            after(0.3) { [self] in
                                print("apple doc saved: \(describe(store.links.first))")
                                type("Update profile https://www.example.com/team/ today")
                                postKey("\r", code: 36)
                                after(0.3) { [self] in
                                    let task = store.tasks.first
                                    print("task: \(task?.title ?? "nil") action=\(task?.action?.label ?? "nil") due=\(task?.dueDate != nil)")
                                    type("https://www.youtube.com/watch?v=jNQXAC9IVRw")
                                    postKey("\r", code: 36)
                                    after(0.3) { [self] in
                                        print("duplicate kept count=\(store.links.count)")
                                        checkClipboardNudge {
                                            after(8) { [self] in
                                                print("after fetch: \(store.links.map { describe($0) })")
                                                NSApp.terminate(nil)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The chip in the real panel: Return saves it, and quick reopening never brings it back.
    private func runClipboardChipSelfTest() {
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        let board = NSPasteboard(name: NSPasteboard.Name("perch-chip-selftest"))
        board.clearContents()
        board.setString("https://www.youtube.com/watch?v=jNQXAC9IVRw", forType: .string)
        ClipboardNudge.board = board
        func chipShowing() -> Bool {
            // Asking to dismiss reports whether a chip is there; only used where it should not be.
            capture.dismissClipboardOffer?() ?? false
        }
        after(1) { [self] in
            showPanel()
            after(0.4) { [self] in
                postKey("\r", code: 36)
                after(0.3) { [self] in
                    print("after Return links=\(store.links.count) list=\(store.links.first?.list.rawValue ?? "nil")")
                    // Close and reopen quickly, several times, as a real user would.
                    for index in 0..<6 {
                        after(Double(index) * 0.1) { [self] in togglePanel() }
                    }
                    after(1.2) { [self] in
                        if !presentation.presented { showPanel() }
                        after(0.5) { [self] in
                            print("chip back after reopening=\(chipShowing()) links=\(store.links.count)")
                            board.clearContents()
                            board.setString("https://www.notion.so/new-page", forType: .string)
                            hidePanel()
                            after(0.4) { [self] in
                                showPanel()
                                after(0.4) { [self] in
                                    postKey("\u{1b}", code: 53)
                                    after(0.3) { [self] in
                                        print("esc dismissed chip, panel still open=\(presentation.presented) links=\(store.links.count)")
                                        hidePanel()
                                        after(0.4) { [self] in
                                            showPanel()
                                            after(0.4) {
                                                print("dismissed chip stays away=\(!chipShowing())")
                                                board.releaseGlobally()
                                                NSApp.terminate(nil)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Uses a private pasteboard, so the user's own clipboard is never touched.
    private func checkClipboardNudge(then done: @escaping () -> Void) {
        let board = NSPasteboard(name: NSPasteboard.Name("perch-selftest"))
        board.clearContents()
        board.setString("https://www.notion.so/invoice-template", forType: .string)
        Task { @MainActor in
            let offer = await ClipboardNudge.check(board) { [store] in store.isSaved($0) }
            print("clipboard behavior=\(board.accessBehavior.rawValue) offer url=\(offer?.url?.absoluteString ?? "nil") offered=\(offer != nil)")
            board.clearContents()
            board.setString("https://www.youtube.com/watch?v=jNQXAC9IVRw", forType: .string)
            let saved = await ClipboardNudge.check(board) { [store] in store.isSaved($0) }
            print("already saved url offered=\(saved != nil)")
            board.clearContents()
            board.setString("just some words", forType: .string)
            let words = await ClipboardNudge.check(board) { [store] in store.isSaved($0) }
            print("plain text offered=\(words != nil)")
            board.releaseGlobally()
            done()
        }
    }

    private func registerHotKey() {
        let key = HotKey { [weak self] in DispatchQueue.main.async { self?.togglePanel() } }
        hotKeyRegistered = key.register(keyCode: kVK_Space, modifiers: controlKey)
        hotKey = key
    }

    private func showRightClickMenu(event: NSEvent, view: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Task", action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Note", action: #selector(newNoteFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide for 1 Hour", action: #selector(hideForAnHour), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func openPanelFromMenu() { showPanel() }

    @objc private func newNoteFromMenu() {
        showPanel()
        presentation.newNoteRequests += 1
    }

    @objc private func hideForAnHour() {
        hiddenUntil = Date().addingTimeInterval(3600)
        handle.orderOut(nil)
        showNowItem.isHidden = false
    }

    @objc private func showWidgetNow() {
        hiddenUntil = nil
        handle.orderFrontRegardless()
        showNowItem.isHidden = true
        lastActivity = Date()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Launch at login change failed: \(error.localizedDescription)")
        }
        loginItem.state = service.status == .enabled ? .on : .off
    }

    private func runShellSelfTest() {
        print("hotkey registered=\(hotKeyRegistered) loginStatus=\(SMAppService.mainApp.status.rawValue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            let start = CACurrentMediaTime()
            showPanel()
            print(String(format: "first open ms=%.1f", (CACurrentMediaTime() - start) * 1000))
            print("immediately isKey=\(panel.isKeyWindow) canBecomeKey=\(panel.canBecomeKey) visible=\(panel.isVisible) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                print("after 0.6s isKey=\(panel.isKeyWindow) responder=\(panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") presented=\(presentation.presented)")
                hidePanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                    let reopen = CACurrentMediaTime()
                    print("closed visible=\(panel.isVisible)")
                    showPanel()
                    print(String(format: "second open ms=%.1f isKey=%d", (CACurrentMediaTime() - reopen) * 1000, panel.isKeyWindow))
                    hidePanel()
                    let screen = handle.screen ?? NSScreen.screens[0]
                    let visible = screen.visibleFrame
                    handle.setFrameOrigin(NSPoint(x: visible.minX + 100, y: visible.minY + 200))
                    finishDrag()
                    let stored = PlacementStore.load(prototype: debug.prototype, on: screen)
                    print("snap left=\(stored?.onLeftEdge ?? false) fraction=\(stored?.fraction ?? -1) mirrored=\(debug.onLeftEdge)")
                    let restored = widgetFrame()
                    print("restored minX-visibleMinX=\(restored.minX - visible.minX) onLeft=\(debug.onLeftEdge)")
                    PlacementStore.clear(prototype: debug.prototype, on: screen)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func buildWidget() {
        handle = makeHandleWindow(frame: widgetFrame())
        let hosting = HandleHostingView(rootView: WidgetView(debug: debug, store: store))
        hosting.onClick = { [weak self] in
            guard let self else { return }
            if self.debug.prototype == .cord { self.debug.cord.nudge() } else { self.togglePanel() }
        }
        hosting.isPullMode = { [weak self] in self?.debug.prototype == .cord }
        hosting.onPull = { [weak self] dx, dy in self?.debug.cord.pull(dx: dx, dy: dy) }
        hosting.onPullEnd = { [weak self] in
            guard let self, self.debug.cord.release() else { return }
            self.togglePanel()
        }
        hosting.onSlide = { [weak self] left in self?.slideCord(toLeft: left) }
        hosting.onDragEnd = { [weak self] in self?.finishDrag() }
        hosting.onRightClick = { [weak self] event, view in self?.showRightClickMenu(event: event, view: view) }
        handle.contentView = hosting
        handle.acceptsMouseMovedEvents = true
        installCordHitTesting()
        handle.orderFrontRegardless()
        if let pull = options.previewPull {
            debug.cord.configure()
            debug.cord.pull(dx: 0, dy: pull)
        }
    }

    /// The cord's window is wide so it never clips, so only the rope itself may catch the mouse.
    private func installCordHitTesting() {
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in self?.pointerMoved(event) }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.pointerMoved(event)
            return event
        }
        updateCordHitTesting()
    }

    private func pointerMoved(_ event: NSEvent) {
        updateCordHitTesting()
        if isPointerNearWidget() {
            lastActivity = Date()
            if debug.tucked { debug.tucked = false }
        }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - handle.frame.minX, y: handle.frame.maxY - mouse.y)
        switch debug.prototype {
        case .cord:
            if debug.cord.isNear(point, within: 6) { debug.cord.brush(at: point, dx: event.deltaX) }
        case .bird:
            followWithBird(point)
        case .pebble:
            break
        }
    }

    /// The bird notices the pointer from well outside its window, and pauses before looking away.
    private func followWithBird(_ point: CGPoint) {
        let distance = hypot(point.x - 32, point.y - 32)
        if distance <= Self.birdNoticeRadius {
            birdLookAway?.cancel()
            birdLookAway = nil
            debug.birdPointer = point
        } else if debug.birdPointer != nil, birdLookAway == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.debug.birdPointer = nil
                self?.birdLookAway = nil
            }
            birdLookAway = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func updateCordHitTesting() {
        guard debug.prototype == .cord else {
            handle.ignoresMouseEvents = false
            return
        }
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation
        let lifted = debug.tucked ? debug.prototype.tuckDistance : 0
        let point = CGPoint(x: mouse.x - handle.frame.minX, y: handle.frame.maxY - mouse.y + lifted)
        handle.ignoresMouseEvents = !debug.cord.isNear(point)
    }

    /// Slides along the top edge of whichever display the pointer is on.
    private func slideCord(toLeft left: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? handle.screen ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = min(max(left, visible.minX), visible.maxX - handle.frame.width)
        debug.cord.carry(dx: x - handle.frame.minX)
        handle.setFrameOrigin(NSPoint(x: x, y: visible.maxY - handle.frame.height))
    }

    private func applyPrototype() {
        guard options.handle == nil else { return }
        handle.setFrame(widgetFrame(), display: true)
        updateCordHitTesting()
        refreshDebugMenu()
    }

    /// Reached with --handle=name: the Phase 1 gallery styles.
    private func buildGalleryHandle(_ style: HandleStyle) {
        let screen = NSScreen.screens[0].visibleFrame
        let size = style.size
        let inset = style.attachesToEdge ? 0 : Tokens.Size.handleGap
        let frame = NSRect(x: screen.maxX - size.width - inset, y: screen.maxY - screen.height / 3 - size.height / 2,
                           width: size.width, height: size.height)
        handle = makeHandleWindow(frame: frame)
        let count = Sample.today.count + Sample.overdue.count
        let hosting = HandleHostingView(rootView: HandleView(style: style, count: count, nextTitle: Sample.today[0].title))
        hosting.onClick = { [weak self] in self?.togglePanel() }
        handle.contentView = hosting
        handle.orderFrontRegardless()
    }

    private func buildGallery() {
        let screen = NSScreen.screens[0].visibleFrame
        let size = NSSize(width: 1140, height: 520)
        let frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        let window = HandleWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(window)
        window.hasShadow = false
        window.contentView = FirstMouseHostingView(rootView: HandleGalleryView())
        window.orderFrontRegardless()
        handle = window
    }

    private func buildPanel() {
        let rect = NSRect(origin: .zero, size: Tokens.Size.panel)
        panel = PanelWindow(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel)
        panel.onCancel = { [weak self] in
            guard let self, self.capture.dismissClipboardOffer?() != true else { return }
            self.hidePanel()
        }
        // The system window shadow draws square dark corners around the glass in dark mode.
        panel.hasShadow = false
        panel.contentView = FirstMouseHostingView(rootView: PanelView(density: options.density, presentation: presentation, capture: capture, store: store, tab: options.tab))
        // Lays the panel out once while invisible, so the first real open is as quick as later ones.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: AppInfo.displayName)
        let menu = NSMenu()
        if options.handle == nil {
            let debugItem = menu.addItem(withTitle: "Debug", action: nil, keyEquivalent: "")
            let debugMenu = NSMenu()
            debugMenu.addItem(withTitle: "Widget", action: nil, keyEquivalent: "").submenu = widgetMenu
            debugMenu.addItem(withTitle: "Colour", action: nil, keyEquivalent: "").submenu = colourMenu
            debugItem.submenu = debugMenu
            refreshDebugMenu()
            menu.addItem(.separator())
        }
        showNowItem.target = self
        showNowItem.isHidden = true
        menu.addItem(showNowItem)
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu
    }

    private func refreshDebugMenu() {
        widgetMenu.removeAllItems()
        for prototype in WidgetPrototype.allCases {
            let item = widgetMenu.addItem(withTitle: prototype.title, action: #selector(chooseWidget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = prototype.rawValue
            item.state = prototype == debug.prototype ? .on : .off
        }
        colourMenu.removeAllItems()
        for colour in WidgetColour.allCases {
            let item = colourMenu.addItem(withTitle: colour.title, action: #selector(chooseColour(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = colour.rawValue
            item.state = colour == debug.colour ? .on : .off
        }
    }

    @objc private func chooseWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let prototype = WidgetPrototype(rawValue: raw) else { return }
        debug.prototype = prototype
        applyPrototype()
    }

    @objc private func chooseColour(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let colour = WidgetColour(rawValue: raw) else { return }
        debug.colour = colour
        refreshDebugMenu()
    }

    private func runCordSelfTest() {
        let cord = CordSimulation()
        cord.windEnabled = false
        cord.configure()
        func run(_ frames: Int) { (0..<frames).forEach { _ in cord.stepOnce() } }
        run(240)
        let rest = cord.tip.y
        print("rest tip y=\(rest)")
        for count in [1, 6, 14, 30] {
            print("knots requested=\(count) drawn=\(cord.knots(count: count).count) radius=\(cord.knotRadius(count: count)) lastY=\(cord.knots(count: count).last?.y ?? 0)")
        }
        cord.pull(dx: 0, dy: 10)
        run(60)
        print("short pull y=\(cord.tip.y) opens=\(cord.release())")
        run(240)
        cord.pull(dx: 8, dy: 500)
        run(60)
        print("max pull y=\(cord.tip.y) opens=\(cord.release())")
        var highest = cord.tip.y
        var biggestStep: CGFloat = 0
        var lastY = cord.tip.y
        for _ in 0..<180 {
            cord.stepOnce()
            highest = min(highest, cord.tip.y)
            biggestStep = max(biggestStep, abs(cord.tip.y - lastY))
            lastY = cord.tip.y
        }
        print("after release highest=\(highest) rest=\(rest) overshoot=\(rest - highest) biggestFrameMove=\(biggestStep) settledY=\(cord.tip.y)")
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for _ in 0..<60 {
            cord.carry(dx: 12)
            cord.stepOnce()
            minX = min(minX, cord.points.map(\.x).min() ?? 0)
            maxX = max(maxX, cord.points.map(\.x).max() ?? 0)
        }
        print("fast slide rope x range=\(minX)...\(maxX) window=\(CordSimulation.width)")
    }

    private func togglePanel() {
        presentation.presented ? hidePanel() : showPanel()
    }

    private func hidePanel() {
        lastActivity = Date()
        store.save()
        presentation.presented = false
        presentation.pinned = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Tokens.Motion.panelCloseSeconds) { [weak self] in
            guard let self, !self.presentation.presented else { return }
            self.panel.orderOut(nil)
        }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func showPanel() {
        metadata.fetchMissing()
        debug.tucked = false
        lastActivity = Date()
        let visible = (handle.screen ?? NSScreen.screens[0]).visibleFrame
        let anchor = handle.frame
        let size = panel.frame.size
        let gap = Tokens.Size.handleGap
        let bounds = visible.insetBy(dx: gap, dy: gap)
        let x = anchor.midX > visible.midX ? anchor.minX - size.width - gap : anchor.maxX + gap
        let y = anchor.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: min(max(x, bounds.minX), bounds.maxX - size.width),
                                     y: min(max(y, bounds.minY), bounds.maxY - size.height)))
        let origin = panel.frame.origin
        presentation.anchor = UnitPoint(x: min(max((anchor.midX - origin.x) / size.width, 0), 1),
                                        y: min(max(1 - (anchor.midY - origin.y) / size.height, 0), 1))
        panel.makeKeyAndOrderFront(nil)
        presentation.presented = true
        // Global monitors only see clicks in other apps, so the handle can still toggle the panel.
        outsideClickMonitor = outsideClickMonitor ?? NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard self?.presentation.pinned == false else { return }
            self?.hidePanel()
        }
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
