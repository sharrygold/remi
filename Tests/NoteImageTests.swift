import XCTest
import SwiftData

final class NoteImageTextTests: XCTestCase {
    private let box = String(NoteText.checkboxCharacter)

    func testImagesRoundTripWithCheckboxes() {
        let markdown = "Trip\n![image](remi-image:A1.jpg)\n- [x] passport ![image](remi-image:B2.png)\n- bag"
        let editor = NoteText.editorContent(fromMarkdown: markdown)
        XCTAssertEqual(editor.text, "Trip\n\(box)\n\(box) passport \(box)\n• bag")
        XCTAssertEqual(editor.attachments, [.image(name: "A1.jpg"), .checkbox(checked: true), .image(name: "B2.png")])
        XCTAssertEqual(NoteText.markdown(fromEditor: editor.text, attachments: editor.attachments), markdown)
    }

    func testTitleAndPreviewSkipImages() {
        let body = "![image](remi-image:A1.jpg)\nReceipt\n![image](remi-image:B2.jpg)\nPaid in full"
        XCTAssertEqual(NoteText.title(of: body), "Receipt")
        XCTAssertEqual(NoteText.preview(of: body), "Paid in full")
    }

    func testPlainTextForSharing() {
        let body = "# Plan\n![image](remi-image:A1.jpg)\n\n- [ ] Book **hotel**\n- [x] Flights\n- See [the map](https://example.com/map)"
        XCTAssertEqual(NoteText.plainText(fromMarkdown: body),
                       "Plan\n\n☐ Book hotel\n☑ Flights\n• See the map (https://example.com/map)")
    }

    func testOnlyRealReferencesCount() {
        XCTAssertEqual(NoteImages.names(in: "![x](remi-image:../etc) ![y](https://a.com/b.png) ![image](remi-image:C3.jpg)"), ["C3.jpg"])
    }

    func testPurgeKeepsUsedAndRecentFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["used.jpg", "old.jpg", "new.jpg"] { try Data([1]).write(to: folder.appendingPathComponent(name)) }
        let old = Date().addingTimeInterval(-3 * 86_400)
        for name in ["used.jpg", "old.jpg"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.appendingPathComponent(name).path)
        }
        XCTAssertEqual(NoteImages.purgeUnused(in: folder, keeping: ["used.jpg"]), 1)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["used.jpg", "new.jpg"])
    }
}

@MainActor
final class NoteImageArchiveTests: XCTestCase {
    func testExportAndImportCarryPictures() throws {
        let source = LibraryStore(directory: nil)
        let name = "\(UUID().uuidString).jpg"
        try Data([0xFF, 0xD8, 0xFF]).write(to: source.noteImageURL(name))
        let note = try XCTUnwrap(source.addNote(fromCapture: "Receipt", currentSpace: nil))
        source.setBody(note, "Receipt\n" + NoteImages.markdown(for: name))
        let archive = try LibraryArchive.decode(LibraryArchive.encoder().encode(source.makeArchive()))
        XCTAssertEqual(archive.images?.map(\.name), [name])

        // A note without pictures writes no images field at all, as before.
        XCTAssertNil(LibraryStore(directory: nil).makeArchive().images)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = LibraryStore(directory: folder)
        target.importArchive(archive)
        XCTAssertEqual(try Data(contentsOf: target.noteImageURL(name)), Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(target.notes.first?.body.contains(name), true)
    }
}
