import Foundation

struct SearchResults {
    var tasks: [TaskItem] = []
    var notes: [Note] = []
    var links: [LinkItem] = []

    var isEmpty: Bool { tasks.isEmpty && notes.isEmpty && links.isEmpty }
    var count: Int { tasks.count + notes.count + links.count }
}

enum SearchText {
    /// Ignores case and accents, so "cafe" finds "Café".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }.map { word in
            word.hasPrefix("#") && word.count > 1 ? String(word.dropFirst()) : word
        }
    }

    /// Every word must appear somewhere in the item.
    static func matches(_ words: [String], in text: String) -> Bool {
        let folded = fold(text)
        return words.allSatisfy { folded.contains($0) }
    }
}

extension LibraryStore {
    static let searchLimitPerGroup = 20

    /// Searches every Space. Items whose title matches come first, then the most recently changed.
    func search(_ query: String) -> SearchResults {
        let words = SearchText.words(query)
        guard !words.isEmpty else { return SearchResults() }

        func ranked<Item>(_ items: [Item], title: (Item) -> String, text: (Item) -> String, date: (Item) -> Date) -> [Item] {
            items.filter { SearchText.matches(words, in: text($0)) }
                .map { (item: $0, titleHit: SearchText.matches(words, in: title($0))) }
                .sorted { lhs, rhs in
                    if lhs.titleHit != rhs.titleHit { return lhs.titleHit }
                    return date(lhs.item) > date(rhs.item)
                }
                .prefix(Self.searchLimitPerGroup)
                .map(\.item)
        }

        // Open tasks before finished ones.
        let tasks = ranked(tasks.filter { !$0.isCompleted }, title: \.title, text: { "\($0.title) \($0.notes) \($0.space?.name ?? "")" },
                           date: \.updatedAt)
            + ranked(tasks.filter(\.isCompleted), title: \.title, text: { "\($0.title) \($0.notes) \($0.space?.name ?? "")" },
                     date: \.updatedAt)
        return SearchResults(
            tasks: Array(tasks.prefix(Self.searchLimitPerGroup)),
            notes: ranked(notes, title: \.title, text: { "\($0.body) \($0.space?.name ?? "")" }, date: \.updatedAt),
            links: ranked(links, title: \.title, text: { "\($0.title) \($0.urlString) \($0.space?.name ?? "")" }, date: \.createdAt)
        )
    }
}
