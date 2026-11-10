import AppKit

/// "Save link from clipboard?" Checked only when the panel opens, never in the background.
///
/// macOS can ask before an app reads the clipboard. Spotting a URL uses `detectedPatterns`, which never
/// asks. The text itself is only read without asking when macOS already allows it; otherwise the chip
/// shows without the address and reading waits until you click Save.
struct ClipboardOffer: Equatable {
    let changeCount: Int
    /// Nil when reading would need permission, so the address is not known yet.
    let url: URL?
}

enum ClipboardNudge {
    static let preferenceKey = "clipboardNudge"
    /// The clipboard contents already offered and answered, so the same copy is never offered twice.
    private static var handledChangeCount: Int?
    /// The clipboard to watch. Self-tests swap in a private one so the user's clipboard is never touched.
    static var board: NSPasteboard = .general

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true }

    @MainActor
    static func check(_ board: NSPasteboard = ClipboardNudge.board, isSaved: @escaping (URL) -> Bool) async -> ClipboardOffer? {
        guard isEnabled, board.accessBehavior != .alwaysDeny else { return nil }
        let count = board.changeCount
        guard !isHandled(count) else { return nil }
        // When reading is already allowed, read straight away: it takes a few milliseconds.
        if board.accessBehavior == .alwaysAllow {
            guard let url = readURL(board), !isSaved(url) else {
                handledChangeCount = count
                return nil
            }
            return ClipboardOffer(changeCount: count, url: url)
        }
        guard let found = try? await board.detectedPatterns(for: [\.probableWebURL]),
              found.contains(\NSPasteboard.DetectedValues.probableWebURL) else { return nil }
        // The answer may arrive after the chip was answered or the clipboard changed.
        guard !isHandled(count), board.changeCount == count else { return nil }
        return ClipboardOffer(changeCount: count, url: nil)
    }

    /// Reads the clipboard; only call this without permission after the person asks for it.
    static func readURL(_ board: NSPasteboard = ClipboardNudge.board) -> URL? {
        guard let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace) else { return nil }
        return LinkClassifier.url(from: text)
    }

    static func isHandled(_ changeCount: Int) -> Bool {
        changeCount == handledChangeCount
    }

    static func markHandled(_ offer: ClipboardOffer) {
        handledChangeCount = offer.changeCount
    }
}
