import Foundation

struct ParsedCapture: Equatable {
    enum SpaceMatch: Equatable {
        case none
        case existing(String)
        case new(String)
    }

    var title: String
    var space: SpaceMatch = .none
    var due: Date?
    var important = false
    /// The first URL typed or pasted. With no other words it makes a link, otherwise the task's action.
    var url: URL?

    var canSave: Bool { !title.isEmpty }
    var isLink: Bool { url != nil && title.isEmpty }
}

enum CaptureParser {
    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3, "wed": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5, "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    static func normalized(_ name: String) -> String {
        name.lowercased().filter { !" -_".contains($0) }
    }

    /// `today` and `tomorrow` count anywhere. Weekdays count only as the last word, so "Sat exam prep" stays a title.
    static func parse(_ text: String, spaceNames: [String], now: Date = Date(), calendar: Calendar = .current) -> ParsedCapture {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var used = Set<Int>()
        var result = ParsedCapture(title: "")

        if let index = words.firstIndex(where: { LinkClassifier.url(from: $0) != nil }) {
            result.url = LinkClassifier.url(from: words[index])
            used.insert(index)
        }

        if let index = words.indices.first(where: { !used.contains($0) && words[$0].hasPrefix("#") && words[$0].count > 1 }) {
            let typed = String(words[index].dropFirst())
            if let match = spaceNames.first(where: { normalized($0) == normalized(typed) }) {
                result.space = .existing(match)
            } else {
                result.space = .new(typed.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized)
            }
            used.insert(index)
        }

        for (index, word) in words.enumerated() where word == "!" && !used.contains(index) {
            result.important = true
            used.insert(index)
        }
        if let last = words.indices.last, !used.contains(last), words[last].count > 1, words[last].hasSuffix("!") {
            words[last].removeLast()
            result.important = true
        }

        let today = calendar.startOfDay(for: now)
        for (index, word) in words.enumerated() where !used.contains(index) {
            let lowered = word.lowercased()
            if lowered == "today" {
                result.due = today
            } else if lowered == "tomorrow" || lowered == "tmrw" {
                result.due = calendar.date(byAdding: .day, value: 1, to: today)
            } else {
                continue
            }
            used.insert(index)
            break
        }

        if result.due == nil, let last = words.indices.last(where: { !used.contains($0) }),
           let weekday = weekdays[words[last].lowercased()] {
            result.due = calendar.nextDate(after: today, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)
            used.insert(last)
        }

        result.title = words.enumerated().filter { !used.contains($0.offset) }.map(\.element).joined(separator: " ")
        return result
    }
}
