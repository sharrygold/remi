import AppKit
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
    private var sliding = false
    private var grabOffset = NSPoint.zero
    private var downMouse = NSPoint.zero
    private var dragged = false
    private let dragThreshold: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

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
            if !sliding { onPullEnd?() }
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
        if options.open { showPanel() }
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

    private func widgetFrame() -> NSRect {
        let visible = NSScreen.screens[0].visibleFrame
        return NSRect(origin: debug.prototype.origin(in: visible), size: debug.prototype.windowSize)
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
        let point = CGPoint(x: mouse.x - handle.frame.minX, y: handle.frame.maxY - mouse.y)
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
        panel.contentView = FirstMouseHostingView(rootView: PanelView(density: options.density, tab: options.tab))
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
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func showPanel() {
        let visible = (handle.screen ?? NSScreen.screens[0]).visibleFrame
        let anchor = handle.frame
        let size = panel.frame.size
        let gap = Tokens.Size.handleGap
        let bounds = visible.insetBy(dx: gap, dy: gap)
        let x = anchor.midX > visible.midX ? anchor.minX - size.width - gap : anchor.maxX + gap
        let y = anchor.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: min(max(x, bounds.minX), bounds.maxX - size.width),
                                     y: min(max(y, bounds.minY), bounds.maxY - size.height)))
        panel.makeKeyAndOrderFront(nil)
        // Global monitors only see clicks in other apps, so the handle can still toggle the panel.
        outsideClickMonitor = outsideClickMonitor ?? NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
