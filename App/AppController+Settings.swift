import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// The Settings window.
extension AppController {
    @objc func openSettings() {
        showSettings(tab: .general)
    }

    func showSettings(tab: SettingsTab) {
        if !presentation.pinned && presentation.presented { hidePanel() }
        let window = settingsWindow ?? makeSettingsWindow()
        settingsContext?.tab = tab
        // Open on the desktop you are looking at. A window left open on another desktop is
        // brought over rather than leaving you to go and find it.
        if window.isVisible && !window.isOnActiveSpace { window.orderOut(nil) }
        if !window.isVisible { centre(window, on: handle?.screen ?? NSScreen.main) }
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// Centres Settings on the screen where Remi lives, so with two displays it opens beside the companion
    /// rather than on whichever screen happened to be active.
    func centre(_ window: NSWindow, on screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { window.center(); return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.08))
    }

    /// Built once, a few seconds after launch, so the first open is instant.
    @discardableResult
    func makeSettingsWindow() -> NSWindow {
        if let settingsWindow { return settingsWindow }
        let context = SettingsContext(store: store, widget: companion, reminders: reminders, libraryDirectory: store.directory) { [weak self] combo in
            self?.hotKey?.register(combo) ?? false
        }
        context.showWelcome = { [weak self] in self?.showWelcome() }
        context.applySaveTabHotKey = { [weak self] combo in self?.saveTabHotKey?.register(combo) ?? false }
        let window = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                                   styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: SettingsView(context: context))
        window.title = "\(AppInfo.displayName) Settings"
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        settingsContext = context
        settingsWindow = window
        return window
    }
}
