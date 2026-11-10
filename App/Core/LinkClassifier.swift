import Foundation

/// Recognises URLs in typed text and decides which list a link belongs in.
enum LinkClassifier {
    /// Bare domains only count with a familiar ending, so "notes.md" or "e.g." stay words.
    private static let bareDomainEndings: Set<String> = [
        "com", "org", "net", "io", "app", "dev", "co", "ai", "me", "ng", "uk", "edu", "gov", "tv", "so", "ly", "gg", "xyz", "be",
    ]

    /// A URL if the whole word is one: with a scheme, starting with www., or a bare domain like example.com/jobs.
    static func url(from word: String) -> URL? {
        let text = word.trimmingCharacters(in: CharacterSet(charactersIn: "<>()\"'").union(.whitespacesAndNewlines))
        let lowered = text.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            guard let url = URL(string: text), let host = url.host(), host.contains(".") || host == "localhost" else { return nil }
            return url
        }
        let candidate: String
        if lowered.hasPrefix("www.") {
            candidate = text
        } else {
            let host = lowered.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lowered
            let parts = host.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 2, let ending = parts.last, bareDomainEndings.contains(String(ending)),
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else { return nil }
            candidate = text
        }
        guard let url = URL(string: "https://" + candidate), url.host() != nil else { return nil }
        return url
    }

    static func displayHost(_ url: URL) -> String {
        var host = url.host() ?? url.absoluteString
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        return host
    }

    /// Videos go to Watch later. Loom is left out on purpose: those are usually your own work links.
    static func isVideo(_ url: URL) -> Bool {
        let host = displayHost(url).lowercased()
        let path = url.path().lowercased()
        let first = path.split(separator: "/").first.map(String.init) ?? ""
        switch host {
        case "youtube.com", "music.youtube.com":
            return ["watch", "shorts", "live", "embed", "playlist"].contains(first)
        case "youtu.be":
            return !first.isEmpty
        case "vimeo.com":
            return !first.isEmpty && first.allSatisfy(\.isNumber)
        case "dailymotion.com":
            return first == "video"
        case "ted.com":
            return first == "talks"
        case "twitch.tv":
            return first == "videos"
        case "tiktok.com":
            return path.contains("/video/")
        default:
            return false
        }
    }

    static func list(for url: URL) -> LinkList {
        isVideo(url) ? .watchLater : .saved
    }

    /// Compares links loosely: ignores the scheme, "www.", a trailing slash and any #fragment.
    static func normalized(_ url: URL) -> String {
        var path = url.path()
        if path.hasSuffix("/") { path.removeLast() }
        let query = url.query().map { "?" + $0 } ?? ""
        return displayHost(url).lowercased() + path + query
    }
}
