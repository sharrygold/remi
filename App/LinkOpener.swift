import AppKit
import SwiftUI

/// Opens links in the preferred browser and runs task actions.
enum LinkOpener {
    /// Dia first, then Arc, Both bundle IDs were verified on a real Mac.
    static let browserOrder = ["company.thebrowser.dia", "company.thebrowser.Browser"]
    /// A bundle ID, or "system" for the default browser. Chosen in Settings from M5.
    static let preferenceKey = "preferredBrowser"

    /// The browser app links open in, or nil for the system default.
    static var browserURL: URL? {
        var ids = browserOrder
        if let chosen = UserDefaults.standard.string(forKey: preferenceKey) {
            if chosen == "system" { return nil }
            ids.insert(chosen, at: 0)
        }
        return ids.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let browser = browserURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: configuration)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func isAvailable(_ action: ItemAction) -> Bool {
        switch action {
        case .url: true
        case .app(let url), .file(let url): FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Returns false when the app or file has moved or been deleted.
    @discardableResult
    static func perform(_ action: ItemAction) -> Bool {
        guard isAvailable(action) else { return false }
        switch action {
        case .url(let url):
            open(url)
        case .app(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .file(let url):
            NSWorkspace.shared.open(url)
        }
        return true
    }

    /// The system file chooser, raised above the floating panel. Returns nil if cancelled.
    static func choose(app: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.canChooseFiles = true
        panel.canChooseDirectories = !app
        panel.allowsMultipleSelection = false
        if app {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.message = "Choose the app this task opens"
        } else {
            panel.message = "Choose the file or folder this task opens"
        }
        panel.prompt = "Choose"
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Lets rows open things and show a short confirmation without knowing about the panel.
struct PanelActions {
    var open: (ItemAction) -> Void = { LinkOpener.perform($0) }
    var confirm: (String) -> Void = { _ in }
    var focusCapture: () -> Void = {}
    /// A task whose title the keyboard asked to edit.
    var editRequest: UUID?
}

private struct PanelActionsKey: EnvironmentKey {
    static let defaultValue = PanelActions()
}

extension EnvironmentValues {
    var panelActions: PanelActions {
        get { self[PanelActionsKey.self] }
        set { self[PanelActionsKey.self] = newValue }
    }
}
