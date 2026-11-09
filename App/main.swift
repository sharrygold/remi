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
        dragged = true
        window?.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged && event.clickCount == 1 { onClick?() }
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    private let options = Options()
    private var handle: HandleWindow!
    private var panel: PanelWindow!
    private var statusItem: NSStatusItem!
    private var outsideClickMonitor: Any?
    private lazy var debug: WidgetDebug = {
        let debug = WidgetDebug(prototype: options.widget, colour: options.colour)
        debug.previewHover = CommandLine.arguments.contains("--preview-hover")
        return debug
    }()
    private let widgetMenu = NSMenu()
    private let colourMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let name = options.appearance {
            NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
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
        hosting.onClick = { [weak self] in self?.togglePanel() }
        handle.contentView = hosting
        handle.orderFrontRegardless()
    }

    private func applyPrototype() {
        guard options.handle == nil else { return }
        handle.setFrame(widgetFrame(), display: true)
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
