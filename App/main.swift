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
    private static let birdNoticeRadius: CGFloat = 260
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
        if let style = options.handle { buildGalleryHandle(style) } else { buildWidget() }
        buildPanel()
        buildStatusItem()
        registerHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.idleTick() }
        if options.open { showPanel() }
        if CommandLine.arguments.contains("--preview-tuck") { debug.tucked = true }
        if CommandLine.arguments.contains("--m1-selftest") { runShellSelfTest() }
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

    private func registerHotKey() {
        let key = HotKey { [weak self] in DispatchQueue.main.async { self?.togglePanel() } }
        hotKeyRegistered = key.register(keyCode: kVK_Space, modifiers: controlKey)
        hotKey = key
    }

    private func showRightClickMenu(event: NSEvent, view: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Task", action: #selector(openPanelFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide for 1 Hour", action: #selector(hideForAnHour), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func openPanelFromMenu() { showPanel() }

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
        let hosting = HandleHostingView(rootView: WidgetView(debug: debug, count: Sample.today.count))
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
        panel.onCancel = { [weak self] in self?.hidePanel() }
        // The system window shadow draws square dark corners around the glass in dark mode.
        panel.hasShadow = false
        panel.contentView = FirstMouseHostingView(rootView: PanelView(density: options.density, presentation: presentation, tab: options.tab))
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
