import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// The panel: building it, showing and hiding it, and its keyboard handling.
extension AppController {
    /// List keys while the capture bar has the cursor. Returns nil when the key isn't a list key,
    /// true when it was used, false to let it through after leaving the list (typing resumes capture).
    func handleListKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool? {
        // The capture bar normally has the cursor, but a list can take focus when it redraws.
        // Text being edited elsewhere (a note, a task title, search) keeps its keys.
        let editingElsewhere = panel.firstResponder is NSTextView && !capture.isFocused
        guard !editingElsewhere, !search.active, panel.isKeyWindow else { return nil }
        let code = Int(event.keyCode)
        if flags.isEmpty, code == kVK_DownArrow { return nav.move(1) }
        guard nav.isActive else { return nil }
        switch (code, flags) {
        case (kVK_UpArrow, []): nav.move(-1)
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []): nav.run(.open)
        case (kVK_Space, []): nav.run(.toggle)
        case (kVK_Escape, []): nav.clear()
        case (kVK_LeftArrow, []), (kVK_RightArrow, []): nav.run(.switchList)
        case (kVK_ANSI_O, [.command]): nav.run(.action)
        case (kVK_Delete, [.command]), (kVK_ForwardDelete, []): nav.run(.delete)
        case (kVK_ANSI_P, [.command]): nav.run(.pin)
        case (kVK_ANSI_R, [.command]): nav.run(.rename)
        case (kVK_ANSI_LeftBracket, [.command, .shift]): nav.run(.moveSpace(-1))
        case (kVK_ANSI_RightBracket, [.command, .shift]): nav.run(.moveSpace(1))
        default:
            // Anything else is typing: hand it back to the capture bar.
            nav.clear()
            return false
        }
        return true
    }

    /// Panel-wide keys:
    /// - ⌘Z with the capture field empty undoes the last change to tasks or notes. While typing,
    ///   or inside a note, it undoes the typing instead.
    /// - ⌘Return in the capture field saves a note.
    /// - ⌘N starts a new note.
    /// - Tab on a pasted link switches between Saved links and Watch later.
    func installPanelKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if self.handleListKey(event, flags: flags) == true { return nil }
            if event.keyCode == UInt16(kVK_Tab), flags.isEmpty, self.capture.isFocused,
               self.capture.toggleLinkList?() == true {
                return nil
            }
            if self.search.active, self.search.isFocused, flags.isEmpty || flags == .function || flags == [.function, .numericPad] {
                switch Int(event.keyCode) {
                case kVK_DownArrow:
                    self.search.selection = min(self.search.selection + 1, max(self.search.resultCount - 1, 0))
                    return nil
                case kVK_UpArrow:
                    self.search.selection = max(self.search.selection - 1, 0)
                    return nil
                default:
                    break
                }
            }
            guard flags == .command else { return event }
            let inNote = (self.panel.firstResponder as? NSTextView)?.isFieldEditor == false
            switch event.keyCode {
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                guard self.capture.isFocused, let submit = self.capture.submitNote else { return event }
                submit()
                return nil
            case UInt16(kVK_ANSI_F):
                self.search.requests += 1
                return nil
            case UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_4):
                let order = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4]
                self.nav.switchTab(order.firstIndex(of: Int(event.keyCode)) ?? 0)
                return nil
            case UInt16(kVK_ANSI_LeftBracket), UInt16(kVK_ANSI_RightBracket):
                guard !(self.panel.firstResponder is NoteTextView) else { return event }
                self.nav.switchSpace(event.keyCode == UInt16(kVK_ANSI_LeftBracket) ? -1 : 1)
                return nil
            case UInt16(kVK_ANSI_Comma):
                self.openSettings()
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

    func buildPanel() {
        let rect = NSRect(origin: .zero, size: Tokens.Size.panel)
        panel = PanelWindow(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.contentMinSize = Tokens.Size.panelMin
        panel.contentMaxSize = Tokens.Size.panelMax
        if let saved = UserDefaults.standard.string(forKey: Self.panelSizeKey) {
            let size = NSSizeFromString(saved)
            if size.width >= Tokens.Size.panelMin.width, size.height >= Tokens.Size.panelMin.height { panel.setContentSize(size) }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self else { return }
            UserDefaults.standard.set(NSStringFromSize(self.panel.frame.size), forKey: Self.panelSizeKey)
            self.panel.invalidateShadow()
        }
        configure(panel)
        // Esc steps back one layer at a time: the clipboard chip, then search, then the panel.
        panel.onCancel = { [weak self] in
            guard let self, self.capture.dismissClipboardOffer?() != true else { return }
            if self.search.active {
                self.search.active = false
                self.search.query = ""
                return
            }
            self.hidePanel()
        }
        // On macOS 27 the system shadow follows the rounded glass cleanly (it drew square corners in the
        // Phase 1 build). It is recomputed once the panel has finished growing and after a resize.
        panel.hasShadow = true
        let hosting = FirstMouseHostingView(rootView: PanelView(density: options.density, presentation: presentation, capture: capture, store: store,
                                                                                search: search, nav: nav, tab: options.tab))
        // The window decides the size, so the edges can be dragged.
        hosting.sizingOptions = []
        panel.contentView = hosting
        // Lays the panel out once while invisible, so the first real open is as quick as later ones.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func togglePanel() {
        presentation.presented ? hidePanel() : showPanel()
    }

    func hidePanel() {
        lastActivity = Date()
        store.save()
        presentation.presented = false
        presentation.pinned = false
        // The glass, the list card and the shadow all leave together: the window fades as one
        // while the mask shrinks back into the widget.
        panel.hasShadow = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Tokens.Motion.panelCloseSeconds
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Tokens.Motion.panelCloseSeconds) { [weak self] in
            guard let self, !self.presentation.presented else { return }
            self.panel.orderOut(nil)
            self.presentation.shown = false
        }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    func showPanel() {
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
        // --no-focus shows the panel without taking the keyboard, for screenshots while the user works.
        if CommandLine.arguments.contains("--no-focus") { panel.orderFrontRegardless() } else { panel.makeKeyAndOrderFront(nil) }
        panel.alphaValue = 1
        presentation.shown = true
        presentation.presented = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.presentation.presented else { return }
            self.panel.hasShadow = true
            self.panel.invalidateShadow()
        }
        // Global monitors only see clicks in other apps, so the handle can still toggle the panel.
        outsideClickMonitor = outsideClickMonitor ?? NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard self?.presentation.pinned == false else { return }
            self?.hidePanel()
        }
    }
}
