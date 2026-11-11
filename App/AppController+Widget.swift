import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// The floating companion: placement, snapping, tucking, hit-testing and what it reacts to.
extension AppController {
    var perched: PerchedBirdView? { surface as? PerchedBirdView }
    var cord: CordCompanionView? { surface as? CordCompanionView }

    func makeHandleWindow(frame: NSRect) -> HandleWindow {
        let window = HandleWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(window)
        window.hasShadow = false
        // Without this, macOS lets clicks fall through wherever the window's pixels read as transparent.
        window.ignoresMouseEvents = false
        return window
    }

    /// Puts the companion back where it last was on the best available display.
    func widgetFrame() -> NSRect {
        let style = companion.style
        let screen = PlacementStore.preferredScreen(for: style)
        var placement = PlacementStore.load(prototype: style, on: screen) ?? .standard(for: style)
        if CommandLine.arguments.contains("--preview-left") { placement.onLeftEdge = true }
        onLeftEdge = placement.onLeftEdge
        return placement.frame(for: style, on: screen.visibleFrame)
    }

    @objc func screensChanged() {
        handle.setFrame(widgetFrame(), display: true)
        surface.configure(plumage: companion.plumage, onLeftEdge: onLeftEdge)
    }

    /// Snaps to the nearest edge with a soft overshoot, then remembers the spot.
    func finishDrag() {
        lastActivity = Date()
        perched?.setCarried(false)
        let style = companion.style
        let screen = handle.screen ?? NSScreen.screens[0]
        let placement = WidgetPlacement.nearest(to: handle.frame, prototype: style, on: screen.visibleFrame)
        PlacementStore.save(placement, prototype: style, on: screen)
        onLeftEdge = placement.onLeftEdge
        surface.configure(plumage: companion.plumage, onLeftEdge: onLeftEdge)
        let target = placement.frame(for: style, on: screen.visibleFrame)
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

    func idleTick() {
        if let until = hiddenUntil, Date() >= until { showWidgetNow() }
        guard let perched, !presentation.presented, NSEvent.pressedMouseButtons == 0, !isPointerNearWidget() else { return }
        let idle = Date().timeIntervalSince(lastActivity)
        if UserDefaults.standard.object(forKey: SettingsKey.autoTuck) as? Bool ?? true {
            if idle >= Self.idleSecondsBeforeTuck { perched.setTucked(true) }
        } else if idle >= Self.idleSecondsBeforeDoze {
            perched.setDozing(true)
        }
    }

    func isPointerNearWidget(_ point: NSPoint = NSEvent.mouseLocation) -> Bool {
        if let perched { return perched.notices(point) || handle.frame.contains(point) }
        return handle.frame.insetBy(dx: -48, dy: -48).contains(point)
    }

    func buildWidget() {
        CompanionArt.registerFont()
        handle = makeHandleWindow(frame: widgetFrame())
        let host = CompanionHostView(frame: NSRect(origin: .zero, size: handle.frame.size))
        host.autoresizingMask = [.width, .height]
        host.setAccessibilityRole(.button)
        host.setAccessibilityLabel(AppInfo.displayName)
        host.onClick = { [weak self] in
            self?.cord?.click()
            self?.togglePanel()
        }
        host.isPullMode = { [weak self] in self?.companion.style == .cord }
        host.onDragStart = { [weak self] in self?.perched?.setCarried(true) }
        host.onPullStart = { [weak self] in self?.cord?.beginPull() }
        host.onPull = { [weak self] amount in self?.cord?.drag(by: amount) }
        host.onPullEnd = { [weak self] in
            guard let self, self.cord?.endPull() == true else { return }
            self.togglePanel()
        }
        host.onSlide = { [weak self] left in self?.slideCord(toLeft: left) }
        host.onDragEnd = { [weak self] in self?.finishDrag() }
        host.onRightClick = { [weak self] event, view in self?.showRightClickMenu(event: event, view: view) }
        handle.contentView = host
        self.host = host
        handle.acceptsMouseMovedEvents = true
        installSurface()
        installPointerWatching()
        handle.orderFrontRegardless()
        applyPreviews()

        store.onTaskAdded = { [weak self] _ in self?.refreshCompanion(event: .taskAdded) }
        store.onTaskCompleted = { [weak self] _ in
            guard let self else { return }
            self.refreshCompanion(event: self.store.allKeptToday() ? .allDone : .taskDone)
        }
        watchers.append(store.$tasks.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshCompanion(event: nil) }
        })
        watchers.append(companion.$plumage.dropFirst().removeDuplicates().sink { [weak self] plumage in
            DispatchQueue.main.async {
                guard let self else { return }
                self.surface.configure(plumage: plumage, onLeftEdge: self.onLeftEdge)
            }
        })
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reduceMotionChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(macWoke), name: NSWorkspace.didWakeNotification, object: nil)
        macWoke()
    }

    /// Builds the view for the current style inside the window.
    func installSurface() {
        surface?.removeFromSuperview()
        let size = companion.style.windowSize
        let view: CompanionSurface = companion.style == .bird ? PerchedBirdView(frame: NSRect(origin: .zero, size: size))
                                                             : CordCompanionView(frame: NSRect(origin: .zero, size: size))
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
        surface = view
        view.configure(plumage: companion.plumage, onLeftEdge: onLeftEdge)
        view.setPanelOpen(presentation.presented)
        refreshCompanion(event: nil)
        updateMouseCatching()
    }

    func refreshCompanion(event: CompanionEvent?) {
        let count = store.todayOpenCount()
        host?.setAccessibilityLabel("\(AppInfo.displayName), \(count) tasks today")
        surface?.update(count: count, allKept: store.allKeptToday(), event: event)
    }

    @objc func reduceMotionChanged() { surface?.reduceMotionChanged() }

    /// Morning stretch on the cord: the first time the Mac wakes each day (or this app starts).
    @objc func macWoke() {
        guard !isScratchSession, cord != nil, claimDay("lastCordStretchDay") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.cord?.playMorningStretch() }
    }

    func claimDay(_ key: String) -> Bool {
        let today = MorningReviewSchedule.dayStamp(for: Date())
        guard UserDefaults.standard.string(forKey: key) != today else { return false }
        UserDefaults.standard.set(today, forKey: key)
        return true
    }

    func installPointerWatching() {
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in self?.pointerMoved() }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.pointerMoved()
            return event
        }
    }

    func pointerMoved(at point: NSPoint = NSEvent.mouseLocation) {
        updateMouseCatching()
        if isPointerNearWidget(point) {
            lastActivity = Date()
            perched?.setTucked(false)
            perched?.setDozing(false)
        }
        surface.pointerMoved(toScreen: point)
    }

    /// Clicks pass through wherever the companion draws nothing. Never changed mid-drag.
    func updateMouseCatching() {
        guard NSEvent.pressedMouseButtons == 0, let surface else { return }
        let mouse = NSEvent.mouseLocation
        guard handle.frame.contains(mouse) else { return }
        handle.ignoresMouseEvents = !surface.isHit(CGPoint(x: mouse.x - handle.frame.minX, y: handle.frame.maxY - mouse.y))
    }

    /// Slides along the top edge of whichever display the pointer is on.
    func slideCord(toLeft left: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? handle.screen ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = min(max(left, visible.minX), visible.maxX - handle.frame.width)
        cord?.carry(dx: x - handle.frame.minX)
        handle.setFrameOrigin(NSPoint(x: x, y: visible.maxY - handle.frame.height))
    }

    func applyStyle() {
        handle.setFrame(widgetFrame(), display: true)
        installSurface()
    }

    /// Launch flags for screenshots, so each pose can be captured without a mouse.
    func applyPreviews() {
        let arguments = CommandLine.arguments
        func value(_ key: String) -> String? { arguments.first { $0.hasPrefix("--\(key)=") }?.split(separator: "=").last.map(String.init) }
        if let look = options.previewLook { perched?.previewLook(at: look) }
        if let mood = value("preview-mood"), let perched {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                switch mood {
                case "tucked": perched.setMood(.tucked)
                case "doze": perched.setMood(.dozing)
                case "carried": perched.setMood(.carried)
                case "working": perched.setMood(.working)
                default: break
                }
            }
        }
        if let event = value("preview-event") {
            DispatchQueue.main.asyncAfter(deadline: .now() + (value("preview-event-delay").flatMap(Double.init) ?? 1)) { [self] in
                switch event {
                case "task": surface.update(count: store.todayOpenCount() + 1, allKept: false, event: .taskAdded)
                case "link": surface.update(count: store.todayOpenCount(), allKept: false, event: .linkCaught)
                case "done": surface.update(count: store.todayOpenCount() - 1, allKept: false, event: .taskDone)
                case "allkept": surface.update(count: 0, allKept: true, event: .allDone)
                case "stretch": surface.playMorningStretch()
                default: break
                }
            }
        }
        if let cord {
            cord.preview(state: value("preview-cord") ?? "", pull: options.previewPull.map(Double.init))
        }
    }
}
