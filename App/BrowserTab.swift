import AppKit

/// Reads the address and title of the tab you are looking at, by asking the browser with AppleScript.
///
/// The panel never takes over as the active app, so the browser stays frontmost while it is open.
/// Nothing is read until you ask (⌘S or a click). macOS asks once for permission per browser.
enum BrowserTab {
    struct Browser: Equatable {
        let bundleID: String
        let name: String
        /// Safari says "current tab" and "name" where the Chromium family says "active tab" and "title".
        var isSafari: Bool { bundleID == "com.apple.Safari" }
    }

    struct Page: Equatable {
        let url: URL
        let title: String?
    }

    enum Failure: Error, Equatable {
        case notAllowed
        case noTab
        case notAWebPage
    }

    static let known = [
        Browser(bundleID: "company.thebrowser.dia", name: "Dia"),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc"),
        Browser(bundleID: "com.google.Chrome", name: "Chrome"),
        Browser(bundleID: "com.brave.Browser", name: "Brave"),
        Browser(bundleID: "com.microsoft.edgemac", name: "Edge"),
        Browser(bundleID: "com.apple.Safari", name: "Safari"),
    ]

    /// The browser in front, if the app in front is one.
    static func frontmost() -> Browser? {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return known.first { $0.bundleID == id }
    }

    static func script(for browser: Browser) -> String {
        let terms = browser.isSafari ? "{URL, name} of current tab" : "{URL, title} of active tab"
        return "tell application id \"\(browser.bundleID)\" to return \(terms) of front window"
    }

    /// Blocks while macOS shows its one-time permission prompt, so only call this when asked to.
    @MainActor
    static func read(_ browser: Browser) -> Result<Page, Failure> {
        guard let script = NSAppleScript(source: script(for: browser)) else { return .failure(.noTab) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743: the person said no, or has not been asked and macOS refused.
            let code = error[NSAppleScript.errorNumber] as? Int
            return .failure(code == -1743 ? .notAllowed : .noTab)
        }
        guard result.numberOfItems >= 1, let address = result.atIndex(1)?.stringValue else { return .failure(.noTab) }
        // Blank tabs and browser pages (chrome://, about:) have nothing worth saving.
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return .failure(.notAWebPage)
        }
        let title = result.numberOfItems >= 2 ? result.atIndex(2)?.stringValue : nil
        return .success(Page(url: url, title: title))
    }
}
