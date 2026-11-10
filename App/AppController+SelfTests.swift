import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// Demo data and the in-app self-tests (`--m2-selftest` and friends). They run on in-memory data and
/// press real keys in the panel, so leave the keyboard alone while one runs.
extension AppController {
    func seedDemo(_ store: LibraryStore) {
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

    func postKey(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    /// Types into the real capture field and presses real keys through the app's event loop.
    func runCaptureSelfTest() {
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
    func runNotesSelfTest() {
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

    func typeNote(then finish: @escaping (String) -> Void) {
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
    func runLinksSelfTest() {
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
    func runClipboardChipSelfTest() {
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
    func checkClipboardNudge(then done: @escaping () -> Void) {
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

    /// ⌘F search with real keys (type, ↓, Return opens a note, a task, Esc steps back), Settings via ⌘,,
    /// shortcut re-registration, a live window setting, and reminder timing.
    func runSearchSelfTest() {
        seedDemo(store)
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        func type(_ text: String) {
            (panel.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        after(1) { [self] in
            showPanel()
            after(0.4) { [self] in
                postKey("f", code: 3, flags: .command)
                after(0.4) { [self] in
                    print("cmd-f active=\(search.active) searchFocused=\(search.isFocused)")
                    type("invoice")
                    after(0.3) { [self] in
                        let found = store.search("invoice")
                        print("results tasks=\(found.tasks.count) notes=\(found.notes.count) links=\(found.links.count) counted=\(search.resultCount)")
                        postKey("", code: 125)
                        postKey("", code: 125)
                        after(0.3) { [self] in
                            print("selection after two downs=\(search.selection)")
                            postKey("\r", code: 36)
                            after(0.8) { [self] in
                                print("opened note editor=\(panel.firstResponder is NoteTextView) searchActive=\(search.active)")
                                postKey("\u{1b}", code: 53)
                                after(0.5) { [self] in
                                    postKey("f", code: 3, flags: .command)
                                    after(0.4) { [self] in
                                        type("dentist")
                                        after(0.3) { [self] in
                                            postKey("\r", code: 36)
                                            after(0.4) { [self] in
                                                print("task hit closes search=\(!search.active) panel visible=\(panel.isVisible)")
                                                postKey("f", code: 3, flags: .command)
                                                after(0.3) { [self] in
                                                    postKey("\u{1b}", code: 53)
                                                    after(0.3) { [self] in
                                                        print("esc closes search only: search=\(search.active) panel=\(presentation.presented)")
                                                        checkSettings()
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
        }
    }

    /// Records ⌥⌘K through a real key event in the Settings window, then puts the original back.
    func checkShortcutRecorder() {
        guard let context = settingsContext, let window = settingsWindow else { return print("recorder: no settings") }
        let original = HotKeyCombo.saved
        context.startRecording()
        guard let press = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, characters: "˚", charactersIgnoringModifiers: "k", isARepeat: false,
                                           keyCode: UInt16(kVK_ANSI_K)) else { return }
        NSApp.sendEvent(press)
        print("recorder recorded=\(context.shortcut.display) saved=\(HotKeyCombo.saved.display) stillRecording=\(context.recordingShortcut)")
        context.startRecording()
        if let plain = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: "k", charactersIgnoringModifiers: "k",
                                        isARepeat: false, keyCode: UInt16(kVK_ANSI_K)) {
            NSApp.sendEvent(plain)
        }
        print("recorder plain key refused=\(context.recordingShortcut) message=\(context.shortcutMessage ?? "nil")")
        context.stopRecording(with: original)
        print("recorder restored=\(HotKeyCombo.saved.display)")
    }

    /// The panel with the keyboard only: tabs, Spaces, moving through lists and acting on items.
    func runKeyboardSelfTest() {
        seedDemo(store)
        var steps: [(String, UInt16, NSEvent.ModifierFlags, () -> String)] = []
        func step(_ name: String, _ characters: String, _ code: Int, _ flags: NSEvent.ModifierFlags = [], check: @escaping () -> String) {
            steps.append((characters, UInt16(code), flags, { "\(name): \(check())" }))
        }
        func selected() -> String {
            switch nav.selected {
            case .task(let task): "task \(task.title)"
            case .note(let note): "note \(note.title)"
            case .link(let link): "link \(link.title)"
            case nil: "none"
            }
        }
        var ticked: TaskItem?
        step("⌘2 Tasks, ↓", "", kVK_DownArrow) { "selected=\(selected())" }
        step("↓", "", kVK_DownArrow) {
            if case .task(let task) = self.nav.selected { ticked = task }
            return "selected=\(selected())"
        }
        step("Space ticks", " ", kVK_Space) { "completed=\(ticked?.isCompleted ?? false) now selected=\(selected())" }
        step("⌘Z unticks", "z", kVK_ANSI_Z, .command) { "completed=\(ticked?.isCompleted ?? false)" }
        step("↓ reselect", "", kVK_DownArrow) {
            if case .task(let task) = self.nav.selected { ticked = task }
            return "selected=\(selected())"
        }
        step("⇧⌘] moves Space", "]", kVK_ANSI_RightBracket, [.command, .shift]) {
            "space=\(ticked?.space?.name ?? "-")"
        }
        step("⌘P marks important", "p", kVK_ANSI_P, .command) { "important=\(ticked?.isImportant ?? false)" }
        step("⌘⌫ deletes", "\u{8}", kVK_Delete, .command) { "deleted=\(ticked?.deletedAt != nil) tasks=\(self.store.tasks.count)" }
        step("Esc leaves list", "\u{1b}", kVK_Escape) { "selected=\(selected()) panel=\(self.presentation.presented)" }
        step("⌘Z undoes delete", "z", kVK_ANSI_Z, .command) { "deleted=\(ticked?.deletedAt != nil)" }
        step("⌘3 Notes", "3", kVK_ANSI_3, .command) { "notes tab" }
        step("↓", "", kVK_DownArrow) { "selected=\(selected())" }
        step("Return opens", "\r", kVK_Return) { "editor=\(self.panel.firstResponder is NoteTextView)" }
        step("Esc back", "\u{1b}", kVK_Escape) { "capture=\(self.capture.isFocused)" }
        step("⌘4 Links, ↓", "", kVK_DownArrow) { "selected=\(selected())" }
        step("→ Watch later", "", kVK_RightArrow) { "list switched, selected=\(selected())" }
        step("↓", "", kVK_DownArrow) { "selected=\(selected())" }
        step("Space watched", " ", kVK_Space) {
            "watchLater=\(self.store.watchLaterCount()) watched=\(self.store.links(in: nil, list: .watchLater, watched: true).count)"
        }
        step("typing returns to capture", "h", kVK_ANSI_H) { "selected=\(selected()) field=[\(self.capture.text)]" }
        step("⌘] next Space", "]", kVK_ANSI_RightBracket, .command) { "ok" }
        step("⌘1 Today, ↓", "", kVK_DownArrow) { "selected=\(selected())" }
        step("Return edits title", "\r", kVK_Return) { "capture focused=\(self.capture.isFocused) responder=\(String(describing: type(of: self.panel.firstResponder as Any)))" }
        step("Return keeps title", "\r", kVK_Return) { "capture=\(self.capture.isFocused)" }
        step("⌘[ back a Space", "[", kVK_ANSI_LeftBracket, .command) { "ok" }
        var renamed: LinkItem?
        step("⌘4 Links, ↓", "", kVK_DownArrow) {
            if case .link(let link) = self.nav.selected { renamed = link }
            return "selected=\(selected())"
        }
        step("⌘R renames", "r", kVK_ANSI_R, .command) { "capture=\(self.capture.isFocused) responder=\(String(describing: type(of: self.panel.firstResponder as Any)))" }
        step("type J", "J", kVK_ANSI_J) { "capture field=[\(self.capture.text)]" }
        step("Return saves name", "\r", kVK_Return) { "title=\(renamed?.title ?? "-") edited=\(renamed?.titleEdited ?? false) capture=\(self.capture.isFocused)" }
        step("↓ again", "", kVK_DownArrow) { "selected=\(selected())" }
        step("⌘R again", "r", kVK_ANSI_R, .command) { "editing" }
        step("type Q", "Q", kVK_ANSI_Q) { "typed" }
        step("Esc cancels", "\u{1b}", kVK_Escape) { "title=\(renamed?.title ?? "-") panel=\(self.presentation.presented) capture=\(self.capture.isFocused)" }

        // Some steps need a tab switch first.
        let before: [Int: (String, Int, NSEvent.ModifierFlags)] = [0: ("2", kVK_ANSI_2, .command), 14: ("4", kVK_ANSI_4, .command),
                                                                   20: ("1", kVK_ANSI_1, .command), 24: ("4", kVK_ANSI_4, .command)]
        func run(_ index: Int) {
            guard index < steps.count else {
                NSApp.terminate(nil)
                return
            }
            if let (characters, code, flags) = before[index] { postKey(characters, code: UInt16(code), flags: flags) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
                let (characters, code, flags, report) = steps[index]
                postKey(characters, code: code, flags: flags)
                // Ticking lingers before the list changes.
                DispatchQueue.main.asyncAfter(deadline: .now() + (code == UInt16(kVK_Space) ? 1.6 : 0.4)) {
                    print(report() + "  [focus=\(self.capture.isFocused ? "capture" : String(describing: type(of: self.panel.firstResponder as Any)))]")
                    run(index + 1)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            showPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { run(0) }
        }
    }

    func checkSettings() {
        postKey(",", code: 43, flags: .command)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            print("cmd-comma settings visible=\(settingsWindow?.isVisible ?? false) title=\(settingsWindow?.title ?? "nil") panelHidden=\(!presentation.presented)")
            checkShortcutRecorder()
            settingsWindow?.close()
            let other = HotKeyCombo(keyCode: kVK_ANSI_K, modifiers: cmdKey | optionKey, display: "⌥⌘K")
            let switched = hotKey?.register(other) ?? false
            let restored = hotKey?.register(HotKeyCombo.saved) ?? false
            print("hotkey switch=\(switched) restored=\(restored) saved=\(HotKeyCombo.saved.display)")
            let defaults = UserDefaults.standard
            let before = defaults.bool(forKey: SettingsKey.hideFromRecordings)
            defaults.set(false, forKey: SettingsKey.hideFromRecordings)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                let visibleToRecorders = panel.sharingType == .readOnly
                defaults.set(before, forKey: SettingsKey.hideFromRecordings)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                    print("recording setting live: off=\(visibleToRecorders) restored hidden=\(panel.sharingType == .none)")
                    let fires = Reminders.fireDates(for: store.tasks, minutes: 9 * 60)
                    let tomorrow = fires.first { $0.0.title.hasPrefix("Finish SwiftUI") }?.1
                    print("reminders planned=\(fires.count) swiftui fires=\(tomorrow.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "nil")")
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func runShellSelfTest() {
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

    func runCordSelfTest() {
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
        let resting = CordSimulation()
        resting.configure()
        resting.tucked = true
        for second in 1...20 {
            (0..<60).forEach { _ in resting.stepOnce() }
            if [2, 5, 10, 15, 20].contains(second) {
                print("rest t=\(second)s breeze=\(resting.breezeLevel) move=\(resting.largestMove) spanGap=\(resting.spanGap) settled=\(resting.isSettled)")
            }
        }
    }
}
