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
    let handle = value("handle").flatMap(HandleStyle.init) ?? .edgeTab
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

final class AppController: NSObject, NSApplicationDelegate {
    private let options = Options()
    private var handle: HandleWindow!
    private var panel: PanelWindow!
    private var statusItem: NSStatusItem!
    private var outsideClickMonitor: Any?
    private var dragOffset: NSPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let name = options.appearance {
            NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
        }
        if options.gallery {
            buildGallery()
            return
        }
        buildHandle()
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

    private func buildHandle() {
        let screen = NSScreen.screens[0].visibleFrame
        let size = options.handle.size
        let inset = options.handle.attachesToEdge ? 0 : Tokens.Size.handleGap
        let frame = NSRect(x: screen.maxX - size.width - inset, y: screen.maxY - screen.height / 3 - size.height / 2,
                           width: size.width, height: size.height)
        handle = HandleWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(handle)
        let count = Sample.today.count + Sample.overdue.count
        handle.contentView = FirstMouseHostingView(rootView: HandleView(style: options.handle, count: count, nextTitle: Sample.today[0].title,
                                                                      onDrag: { [weak self] in self?.dragHandle() },
                                                                      onDragEnd: { [weak self] in self?.dragOffset = nil }) { [weak self] in
            self?.togglePanel()
        })
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
        let quit = menu.addItem(withTitle: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu
    }

    private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func dragHandle() {
        let mouse = NSEvent.mouseLocation
        let offset = dragOffset ?? NSPoint(x: mouse.x - handle.frame.minX, y: mouse.y - handle.frame.minY)
        dragOffset = offset
        handle.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
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
