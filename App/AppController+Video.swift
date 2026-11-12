import AppKit

/// Launch helpers for filming the app: a believable day of demo data and typing at a human pace.
extension AppController {
    /// `--video-data` (or `--video-data=evening`): an in-memory day for the launch film.
    /// Morning: three tasks carried over from yesterday, a few for today, pinned notes and links.
    /// Evening: the same day nearly done, with one task left to tick. Note: morning plus a filled-in launch note.
    var videoDataVariant: String? {
        CommandLine.arguments.first { $0 == "--video-data" || $0.hasPrefix("--video-data=") }
            .map { $0.contains("=") ? String($0.split(separator: "=", maxSplits: 1)[1]) : "morning" }
    }

    func seedVideoDay(_ store: LibraryStore, variant: String) {
        let evening = variant == "evening"
        func add(_ line: String) -> TaskItem? {
            store.add(CaptureParser.parse(line, spaceNames: store.spaces.map(\.name)), currentSpace: nil)
        }
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))
        if !evening {
            for (title, space) in [("Reply to the design feedback", "Work"), ("Renew the library books", "Personal"),
                                   ("Finish lesson three of the course", "Learning")] {
                store.add(ParsedCapture(title: title, space: .existing(space), due: yesterday), currentSpace: nil)
            }
        }
        let today = ["Review the slides before lunch #work today", "Water the plants #personal today",
                     "Read one chapter #learning today", "Plan next week #work today"]
        let added = today.compactMap(add)
        if evening {
            // Everything ticked off except the last one, so the final tick empties the egg.
            for task in added.dropLast() { store.toggleCompleted(task) }
        }
        _ = add("Pick up a birthday card #personal fri")
        _ = add("Sketch ideas for the newsletter #work tomorrow")

        let notes = [
            ("Personal", true, "Weekly plan\n- [x] Laundry on Sunday\n- [ ] Call home\n- [ ] Early night on Wednesday"),
            ("Learning", true, "Reading list\n- The Design of Everyday Things\n- Atomic Habits\n- A Pattern Language"),
        ]
        for (index, (spaceName, pinned, body)) in notes.enumerated() {
            let note = store.newNote(in: store.spaces.first { $0.name == spaceName })
            store.setBody(note, body, now: Date().addingTimeInterval(Double(-index - 1) * 5400))
            if pinned { store.setPinned(note, true) }
        }
        // `--video-data=note`: the note typed on camera, already filled in, so it can be opened and shown.
        if variant == "note" {
            let note = store.newNote(in: store.spaces.first { $0.name == "Personal" })
            store.setBody(note, "Ideas for the launch\nKeep it calm and short.\n- [x] Pick the opening line\n- [ ] Film a day with the app\n- [ ] Write the first post\n- [ ] Share with a few friends")
        }
        // Real public pages, renamed to short titles. Their icons are fetched when the panel opens.
        let links = [
            ("https://en.wikipedia.org/wiki/Sankofa", "Sankofa", "Learning", true),
            ("https://developer.apple.com/design/human-interface-guidelines", "Human Interface Guidelines", "Learning", false),
            ("https://www.gutenberg.org", "Free books to read", "Personal", false),
        ]
        for (address, title, spaceName, pinned) in links {
            guard let url = URL(string: address) else { continue }
            let link = store.addLink(url, currentSpace: store.spaces.first { $0.name == spaceName }).link
            store.rename(link, to: title)
            if pinned { store.setPinned(link, true) }
        }
        store.save()
        store.reload()
    }

    /// `--demo-type=TEXT` types into the capture bar, one letter at a time, then presses Return.
    /// Several lines are separated by `⏎`. A line ending in `⌘` saves as a note (⌘Return), and a line
    /// starting with `⌘V ` arrives all at once, like a paste.
    /// Pace, for filming: DEMO_TYPE_DELAY (first letter, s, 1.5), DEMO_TYPE_MS (per letter, 75),
    /// DEMO_TYPE_JITTER (± ms, 0), DEMO_TYPE_TOKEN_PAUSE (extra ms before # ! and links, 0),
    /// DEMO_TYPE_GAP (s between lines, 2.5). Defaults keep the old fixed 75 ms pace.
    func runDemoTyping(_ text: String) {
        let env = ProcessInfo.processInfo.environment
        func number(_ key: String, _ fallback: Double) -> Double { Double(env[key] ?? "") ?? fallback }
        let perLetter = number("DEMO_TYPE_MS", 75) / 1000
        let jitter = number("DEMO_TYPE_JITTER", 0) / 1000
        let tokenPause = number("DEMO_TYPE_TOKEN_PAUSE", 0) / 1000
        let gap = number("DEMO_TYPE_GAP", 2.5)
        // A fixed seed, so a retake types with exactly the same rhythm.
        var generator = SeededRandom(seed: 7)
        var time = number("DEMO_TYPE_DELAY", 1.5)

        func at(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        func moveCursorToEnd() {
            if let editor = panel.firstResponder as? NSTextView {
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
        let lines = text.components(separatedBy: "⏎").filter { !$0.isEmpty }
        for (number, rawLine) in lines.enumerated() {
            var line = rawLine
            let asNote = line.hasSuffix("⌘")
            if asNote { line.removeLast() }
            if line.hasPrefix("⌘V ") {
                let pasted = String(line.dropFirst(3))
                at(time) { [self] in capture.text.append(pasted); moveCursorToEnd() }
                time += 0.1
            } else {
                let letters = Array(line)
                for (index, letter) in letters.enumerated() {
                    let wordStart = index == 0 || letters[index - 1] == " "
                    let startsToken = wordStart && (letter == "#" || letter == "!" || String(letters[index...]).hasPrefix("http"))
                    if startsToken { time += tokenPause }
                    at(time) { [self] in capture.text.append(letter); moveCursorToEnd() }
                    time += max(0.02, perLetter + (jitter > 0 ? Double.random(in: -jitter...jitter, using: &generator) : 0))
                }
            }
            time += 0.7
            at(time) { [self] in (asNote ? capture.submitNote : capture.submit)?() }
            if number < lines.count - 1 { time += gap }
        }
    }
}

/// A tiny repeatable random source (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
