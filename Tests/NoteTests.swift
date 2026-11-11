import XCTest
import SwiftData

final class NoteTextTests: XCTestCase {
    func testCheckboxLineGivesTaskTitle() {
        let box = String(NoteText.checkboxCharacter)
        XCTAssertEqual(NoteText.checkboxText(ofEditorLine: "  \(box) Call **Dana** back"), "Call Dana back")
        XCTAssertNil(NoteText.checkboxText(ofEditorLine: "\(box) "))
        XCTAssertNil(NoteText.checkboxText(ofEditorLine: "Just a line"))
    }

    func testTitleAndPreviewSkipMarkdown() {
        let body = "\n## Q4 **priorities**\n\n- [x] Reporting\n- Onboarding [flow](https://example.com)\nVendor review"
        XCTAssertEqual(NoteText.title(of: body), "Q4 priorities")
        XCTAssertEqual(NoteText.preview(of: body), "Reporting  Onboarding flow")
        XCTAssertEqual(NoteText.title(of: "   \n"), "")
    }

    func testMarkdownRoundTrip() {
        let markdown = "Groceries\n- milk\n  - [ ] eggs\n- [x] bread\n* [ ] jam\nplain - dash\n# Heading"
        let editor = NoteText.editorText(fromMarkdown: markdown)
        let box = String(NoteText.checkboxCharacter)
        XCTAssertEqual(editor.text, "Groceries\n• milk\n  \(box) eggs\n\(box) bread\n\(box) jam\nplain - dash\n# Heading")
        XCTAssertEqual(editor.checkboxes, [false, true, false])
        // "* [ ]" is normalised to "- [ ]" when saved.
        XCTAssertEqual(NoteText.markdown(fromEditor: editor.text, checkboxes: editor.checkboxes),
                       "Groceries\n- milk\n  - [ ] eggs\n- [x] bread\n- [ ] jam\nplain - dash\n# Heading")
    }

    func testLineKinds() {
        let box = String(NoteText.checkboxCharacter)
        XCTAssertEqual(NoteText.kind(ofEditorLine: "• item"), .bullet)
        XCTAssertEqual(NoteText.kind(ofEditorLine: "\t\(box) item"), .checkbox(checked: false))
        XCTAssertEqual(NoteText.kind(ofEditorLine: "## Plan"), .heading(level: 2))
        XCTAssertEqual(NoteText.kind(ofEditorLine: "#hashtag"), .plain)
        XCTAssertEqual(NoteText.kind(ofEditorLine: "#### Too deep"), .plain)
    }

    func testShortcuts() {
        XCTAssertEqual(NoteText.shortcut(beforeSpace: "-")?.kind, .bullet)
        XCTAssertEqual(NoteText.shortcut(beforeSpace: "  *")?.length, 1)
        XCTAssertEqual(NoteText.shortcut(beforeSpace: "[]")?.kind, .checkbox(checked: false))
        XCTAssertEqual(NoteText.shortcut(beforeSpace: "• []")?.length, 4)
        XCTAssertEqual(NoteText.shortcut(beforeSpace: "- [x]")?.kind, .checkbox(checked: true))
        XCTAssertNil(NoteText.shortcut(beforeSpace: "a -"))
        XCTAssertNil(NoteText.shortcut(beforeSpace: "--"))
    }
}

@MainActor
final class NoteStoreTests: XCTestCase {
    func testCaptureKeepsDateWordsAndUsesSpace() throws {
        let store = LibraryStore(directory: nil)
        let note = try XCTUnwrap(store.addNote(fromCapture: "Call notes for today #clients !", currentSpace: nil))
        XCTAssertEqual(note.body, "Call notes for today !")
        XCTAssertEqual(note.space?.name, "Clients")
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNil(store.addNote(fromCapture: "#work", currentSpace: nil))
    }

    func testCaptureUndoRemovesNoteAndNewSpace() {
        let store = LibraryStore(directory: nil)
        store.addNote(fromCapture: "Seeds to buy #garden", currentSpace: nil)
        XCTAssertEqual(store.spaces.count, 6)
        store.undo()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(store.spaces.count, 5)
    }

    func testPinnedFirstThenRecent() throws {
        let store = LibraryStore(directory: nil)
        let old = try XCTUnwrap(store.addNote(fromCapture: "Old", currentSpace: nil))
        let new = try XCTUnwrap(store.addNote(fromCapture: "New", currentSpace: nil))
        store.setBody(old, "Old", now: Date().addingTimeInterval(-60))
        store.setBody(new, "New edited", now: Date())
        XCTAssertEqual(store.notes(in: nil).map(\.title), ["New edited", "Old"])
        store.setPinned(old, true)
        XCTAssertEqual(store.notes(in: nil).map(\.title), ["Old", "New edited"])
        store.undo()
        XCTAssertFalse(old.isPinned)
    }

    func testBlankNoteIsDiscardedOnClose() {
        let store = LibraryStore(directory: nil)
        let note = store.newNote(in: nil)
        XCTAssertEqual(note.space?.name, "Personal")
        XCTAssertEqual(store.notes.count, 1)
        store.finishEditing(note)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(store.canUndo)
    }

    func testSpaceFilterMoveAndDelete() throws {
        let store = LibraryStore(directory: nil)
        let work = try XCTUnwrap(store.spaces.first { $0.name == "Work" })
        let learning = try XCTUnwrap(store.spaces.first { $0.name == "Learning" })
        let note = try XCTUnwrap(store.addNote(fromCapture: "Sprint", currentSpace: work))
        XCTAssertEqual(store.notes(in: work).count, 1)
        XCTAssertTrue(store.notes(in: learning).isEmpty)
        store.move(note, to: learning)
        XCTAssertEqual(store.notes(in: learning).count, 1)
        store.delete(note)
        XCTAssertTrue(store.notes.isEmpty)
        store.undo()
        XCTAssertEqual(store.notes.count, 1)
    }

    func testNotesSurviveReopeningAndBlankOnesAreCleared() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = LibraryStore(directory: directory)
            let note = store.newNote(in: nil)
            store.setBody(note, "Kept\n- [x] done")
            store.setPinned(note, true)
            _ = store.newNote(in: nil)
            store.save()
        }
        let reopened = LibraryStore(directory: directory)
        XCTAssertEqual(reopened.notes.map(\.body), ["Kept\n- [x] done"])
        XCTAssertEqual(reopened.notes.first?.isPinned, true)
    }
}
