import Foundation

/// Plain-text rules for notes, shared by the list, the editor and the tests.
///
/// Notes are saved as Markdown. In the editor, list markers are shown the Apple Notes way:
/// `- ` becomes a `• ` bullet and `- [ ] ` becomes a checkbox, which the editor draws in place of
/// `NoteText.checkboxCharacter`. These functions convert between the two forms.
enum NoteText {
    /// The object replacement character, which the editor turns into a checkbox image.
    static let checkboxCharacter: Character = "\u{FFFC}"
    static let bullet = "• "

    enum LineKind: Equatable {
        case plain
        case heading(level: Int)
        case bullet
        case checkbox(checked: Bool)
    }

    // MARK: Title and preview

    static func title(of body: String) -> String {
        visibleLines(body).first ?? ""
    }

    static func preview(of body: String) -> String {
        visibleLines(body).dropFirst().prefix(2).joined(separator: "  ")
    }

    private static func visibleLines(_ body: String) -> [String] {
        body.split(whereSeparator: \.isNewline).map { stripped(String($0)) }.filter { !$0.isEmpty }
    }

    /// A line as it reads, without Markdown marks.
    static func stripped(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "- ", "* ", bullet] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        while text.hasPrefix("#") { text.removeFirst() }
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)\s]+\)"#, with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Markdown and editor text

    /// Turns saved Markdown into editor text, plus the checked state of each checkbox in order.
    static func editorText(fromMarkdown markdown: String) -> (text: String, checkboxes: [Bool]) {
        var checkboxes: [Bool] = []
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            let (indent, rest) = splitIndent(line)
            for (prefix, checked) in [("- [ ] ", false), ("* [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [x] ", true)]
            where rest.hasPrefix(prefix) {
                checkboxes.append(checked)
                return indent + String(checkboxCharacter) + " " + rest.dropFirst(prefix.count)
            }
            if rest.hasPrefix("- ") || rest.hasPrefix("* ") {
                return indent + bullet + rest.dropFirst(2)
            }
            return line
        }
        return (lines.joined(separator: "\n"), checkboxes)
    }

    /// The reverse of `editorText(fromMarkdown:)`.
    static func markdown(fromEditor text: String, checkboxes: [Bool]) -> String {
        var remaining = checkboxes[...]
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let (indent, rest) = splitIndent(line)
            var output = ""
            if rest.hasPrefix(bullet) {
                output = indent + "- " + rest.dropFirst(bullet.count)
            } else {
                output = line
            }
            // Any checkbox character becomes Markdown; one not at a line start is kept as a box too.
            var result = ""
            for character in output {
                if character == checkboxCharacter {
                    let checked = remaining.popFirst() ?? false
                    result += checked ? "- [x]" : "- [ ]"
                } else {
                    result.append(character)
                }
            }
            return result
        }
        return lines.joined(separator: "\n")
    }

    static func splitIndent(_ line: String) -> (indent: String, rest: Substring) {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        return (String(indent), line.dropFirst(indent.count))
    }

    /// What an editor line is, judged after its indent.
    static func kind(ofEditorLine line: String) -> LineKind {
        let rest = splitIndent(line).rest
        if rest.first == checkboxCharacter { return .checkbox(checked: false) }
        if rest.hasPrefix(bullet) { return .bullet }
        let hashes = rest.prefix { $0 == "#" }.count
        if (1...3).contains(hashes), rest.dropFirst(hashes).first == " " { return .heading(level: hashes) }
        return .plain
    }

    /// A checkbox line's words, for turning it into a task. Nil for any other line or an empty box.
    static func checkboxText(ofEditorLine line: String) -> String? {
        guard case .checkbox = kind(ofEditorLine: line) else { return nil }
        let text = stripped(String(splitIndent(line).rest.dropFirst()))
        return text.isEmpty ? nil : text
    }

    /// The marker typed at the start of a line that should turn into a bullet or checkbox, if any.
    /// Returns the length of the typed marker (before the trailing space) and what it becomes.
    static func shortcut(beforeSpace typed: String) -> (length: Int, kind: LineKind)? {
        let rest = splitIndent(typed).rest
        switch rest {
        case "-", "*": return (rest.count, .bullet)
        case "[]", "[ ]", "- []", "- [ ]", "* [ ]", "• []", "• [ ]": return (rest.count, .checkbox(checked: false))
        case "[x]", "- [x]", "• [x]": return (rest.count, .checkbox(checked: true))
        default: return nil
        }
    }
}
