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

    /// What sits at each object replacement character in editor text, in order.
    enum Attachment: Equatable {
        case checkbox(checked: Bool)
        case image(name: String)
    }

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
        var text = NoteImages.removingReferences(from: line).trimmingCharacters(in: .whitespaces)
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

    /// Turns saved Markdown into editor text, plus what each object replacement character stands for:
    /// a checkbox at a line start, or an image anywhere.
    static func editorContent(fromMarkdown markdown: String) -> (text: String, attachments: [Attachment]) {
        var attachments: [Attachment] = []
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            var output = line
            let (indent, rest) = splitIndent(line)
            var matched = false
            for (prefix, checked) in [("- [ ] ", false), ("* [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [x] ", true)]
            where rest.hasPrefix(prefix) {
                attachments.append(.checkbox(checked: checked))
                output = indent + String(checkboxCharacter) + " " + rest.dropFirst(prefix.count)
                matched = true
                break
            }
            if !matched, rest.hasPrefix("- ") || rest.hasPrefix("* ") {
                output = indent + bullet + rest.dropFirst(2)
            }
            let references = NoteImages.references(in: output)
            guard !references.isEmpty else { return output }
            let result = NSMutableString(string: output)
            for reference in references.reversed() {
                result.replaceCharacters(in: reference.range, with: String(checkboxCharacter))
            }
            attachments.append(contentsOf: references.map { .image(name: $0.name) })
            return result as String
        }
        return (lines.joined(separator: "\n"), attachments)
    }

    /// The reverse of `editorContent(fromMarkdown:)`.
    static func markdown(fromEditor text: String, attachments: [Attachment]) -> String {
        var remaining = attachments[...]
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let (indent, rest) = splitIndent(line)
            let output = rest.hasPrefix(bullet) ? indent + "- " + rest.dropFirst(bullet.count) : line
            var result = ""
            for character in output {
                guard character == checkboxCharacter else {
                    result.append(character)
                    continue
                }
                switch remaining.popFirst() ?? .checkbox(checked: false) {
                case .checkbox(let checked): result += checked ? "- [x]" : "- [ ]"
                case .image(let name): result += NoteImages.markdown(for: name)
                }
            }
            return result
        }
        return lines.joined(separator: "\n")
    }

    /// Checkbox-only form, for notes without images.
    static func editorText(fromMarkdown markdown: String) -> (text: String, checkboxes: [Bool]) {
        let content = editorContent(fromMarkdown: markdown)
        return (content.text, content.attachments.compactMap { if case .checkbox(let checked) = $0 { checked } else { nil } })
    }

    static func markdown(fromEditor text: String, checkboxes: [Bool]) -> String {
        markdown(fromEditor: text, attachments: checkboxes.map { .checkbox(checked: $0) })
    }

    /// Readable text for sharing outside the app: checkboxes as ☐ and ☑, bullets as •, no Markdown marks,
    /// links as "label (address)", images left out (they travel as files alongside).
    static func plainText(fromMarkdown markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            let (indent, rest) = splitIndent(NoteImages.removingReferences(from: line))
            var text = String(rest)
            for (prefix, mark) in [("- [ ] ", "☐ "), ("* [ ] ", "☐ "), ("- [x] ", "☑ "), ("- [X] ", "☑ "), ("* [x] ", "☑ "), ("- ", "• "), ("* ", "• ")]
            where text.hasPrefix(prefix) {
                text = mark + text.dropFirst(prefix.count)
                break
            }
            let hashes = text.prefix { $0 == "#" }.count
            if (1...3).contains(hashes), text.dropFirst(hashes).first == " " { text = String(text.dropFirst(hashes + 1)) }
            text = text.replacingOccurrences(of: "**", with: "")
            text = text.replacingOccurrences(of: #"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#, with: "$1 ($2)", options: .regularExpression)
            return (indent + text).trimmingCharacters(in: .whitespaces).isEmpty ? "" : indent + text
        }
        // Image-only lines leave blanks behind; no more than one empty line in a row.
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) { result.append(line) }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
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
