import XCTest
import SwiftData

@MainActor
final class SearchTests: XCTestCase {
    func testFindsAcrossTypesIgnoringCaseAndAccents() throws {
        let store = LibraryStore(directory: nil)
        let names = store.spaces.map(\.name)
        store.add(CaptureParser.parse("Send café invoice #work", spaceNames: names), currentSpace: nil)
        store.add(CaptureParser.parse("Invoice review notes", spaceNames: names), currentSpace: nil)
        store.addNote(fromCapture: "Ideas\nThe invoice should open with their problem", currentSpace: nil)
        store.addLink(URL(string: "https://example.com/invoice-guide")!, currentSpace: nil)

        let results = store.search("INVOICE")
        XCTAssertEqual(results.tasks.count, 2)
        XCTAssertEqual(results.notes.count, 1)
        XCTAssertEqual(results.links.count, 1)
        XCTAssertEqual(store.search("cafe").tasks.map(\.title), ["Send café invoice"])
        // Every word must match, and a Space name counts.
        XCTAssertEqual(store.search("invoice #work").tasks.count, 1)
        XCTAssertTrue(store.search("invoice banana").isEmpty)
        XCTAssertTrue(store.search("   ").isEmpty)
    }

    func testTitleHitsComeFirstAndDoneTasksLast() throws {
        let store = LibraryStore(directory: nil)
        let done = try XCTUnwrap(store.add(ParsedCapture(title: "Loom intro"), currentSpace: nil))
        store.toggleCompleted(done, now: Date().addingTimeInterval(-10))
        store.add(ParsedCapture(title: "Record Loom video"), currentSpace: nil)
        XCTAssertEqual(store.search("loom").tasks.map(\.title), ["Record Loom video", "Loom intro"])

        let bodyHit = try XCTUnwrap(store.addNote(fromCapture: "Weekly plan mentions budget", currentSpace: nil))
        let titleHit = try XCTUnwrap(store.addNote(fromCapture: "Budget", currentSpace: nil))
        store.setBody(bodyHit, "Weekly plan\nmentions budget", now: Date().addingTimeInterval(100))
        XCTAssertEqual(store.search("budget").notes.map(\.id), [titleHit.id, bodyHit.id])
    }

    func testDeletedItemsAreNotFound() throws {
        let store = LibraryStore(directory: nil)
        let task = try XCTUnwrap(store.add(ParsedCapture(title: "Hidden"), currentSpace: nil))
        store.delete(task)
        XCTAssertTrue(store.search("hidden").isEmpty)
    }
}

@MainActor
final class ArchiveTests: XCTestCase {
    private func populated() throws -> LibraryStore {
        let store = LibraryStore(directory: nil)
        let names = store.spaces.map(\.name)
        let task = try XCTUnwrap(store.add(CaptureParser.parse("Update profile example.com today ! #garden", spaceNames: names), currentSpace: nil))
        store.toggleCompleted(task)
        let note = try XCTUnwrap(store.addNote(fromCapture: "Loom checklist", currentSpace: nil))
        store.setBody(note, "Loom checklist\n- [ ] Close tabs\n- [x] Check mic")
        store.setPinned(note, true)
        let link = store.addLink(URL(string: "https://youtu.be/x")!, currentSpace: nil).link
        store.setMetadata(for: link.id, title: "Zoo [video]", iconData: Data([1, 2, 3]))
        let gone = try XCTUnwrap(store.add(ParsedCapture(title: "Deleted one"), currentSpace: nil))
        store.delete(gone)
        return store
    }

    func testJSONRoundTripRestoresIntoEmptyLibrary() throws {
        let source = try populated()
        let data = try LibraryArchive.encoder().encode(source.makeArchive())
        let archive = try LibraryArchive.decode(data)
        XCTAssertEqual(archive.spaces.count, 4)
        XCTAssertEqual(archive.tasks.count, 2, "deleted items are kept")

        let target = LibraryStore(directory: nil)
        let summary = target.importArchive(archive)
        XCTAssertEqual(target.spaces.count, 4, "starter Spaces are matched by name, not duplicated")
        XCTAssertEqual(target.tasks.map(\.title), ["Update profile"])
        let task = try XCTUnwrap(target.tasks.first)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(task.isImportant)
        XCTAssertEqual(task.space?.name, "Garden")
        XCTAssertEqual(task.action, .url(URL(string: "https://example.com")!))
        XCTAssertEqual(target.notes.first?.body, "Loom checklist\n- [ ] Close tabs\n- [x] Check mic")
        XCTAssertEqual(target.notes.first?.isPinned, true)
        XCTAssertEqual(target.links.first?.title, "Zoo [video]")
        XCTAssertEqual(target.links.first?.iconData, Data([1, 2, 3]))
        XCTAssertEqual(target.links.first?.list, .watchLater)
        XCTAssertEqual(target.deletedItems().map(\.title), ["Deleted one"])
        XCTAssertEqual(summary.added, 1 + 2 + 1 + 1)

        // Importing the same file again changes nothing.
        let again = target.importArchive(archive)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.updated, 0)
        XCTAssertEqual(target.tasks.count, 1)
    }

    func testNewerCopyWins() throws {
        let store = try populated()
        let archive = store.makeArchive()
        let note = try XCTUnwrap(store.notes.first)
        store.setBody(note, "Edited after export", now: Date().addingTimeInterval(60))
        store.importArchive(archive)
        XCTAssertEqual(note.body, "Edited after export")
    }

    func testRejectsOtherJSON() {
        XCTAssertThrowsError(try LibraryArchive.decode(Data(#"{"hello": 1}"#.utf8)))
        var archive = LibraryArchive(exportedAt: Date(), spaces: [], tasks: [], notes: [], links: [])
        archive.format = "something-else"
        let data = try! LibraryArchive.encoder().encode(archive)
        XCTAssertThrowsError(try LibraryArchive.decode(data))
    }

    func testMarkdownIsReadable() throws {
        let markdown = ArchiveMarkdown.render(try populated().makeArchive(), appName: "Remi")
        XCTAssertTrue(markdown.hasPrefix("# Remi export"))
        XCTAssertTrue(markdown.contains("## Garden"))
        XCTAssertTrue(markdown.contains("- [x] Update profile (important) · due "))
        XCTAssertTrue(markdown.contains("#### Loom checklist (pinned)\n\n- [ ] Close tabs\n- [x] Check mic"))
        XCTAssertTrue(markdown.contains("### Watch later\n\n- [Zoo [video)](https://youtu.be/x)"))
        XCTAssertFalse(markdown.contains("Deleted one"))
    }
}

@MainActor
final class MaintenanceTests: XCTestCase {
    func testBackupsOncePerDayKeepingFourteen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: nil)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<20 {
            let when = start.addingTimeInterval(Double(day) * 86_400)
            XCTAssertNotNil(try Backups.backUp({ store.makeArchive() }, to: directory, now: when))
            XCTAssertNil(try Backups.backUp({ store.makeArchive() }, to: directory, now: when.addingTimeInterval(60)), "once a day")
        }
        let files = Backups.list(in: directory)
        XCTAssertEqual(files.count, 14)
        XCTAssertEqual(files.first?.lastPathComponent, Backups.fileName(for: start.addingTimeInterval(19 * 86_400)))
        XCTAssertNoThrow(try LibraryArchive.decode(Data(contentsOf: try XCTUnwrap(files.first))))
        XCTAssertNotNil(try Backups.backUp({ store.makeArchive() }, to: directory, now: start.addingTimeInterval(19 * 86_400), force: true))
    }

    func testRecentlyDeletedRestoreAndPurge() throws {
        let store = LibraryStore(directory: nil)
        let now = Date()
        let old = try XCTUnwrap(store.add(ParsedCapture(title: "Old"), currentSpace: nil))
        let recent = try XCTUnwrap(store.addNote(fromCapture: "Recent", currentSpace: nil))
        let link = store.addLink(URL(string: "https://a.com")!, currentSpace: nil).link
        store.delete(old, now: now.addingTimeInterval(-31 * 86_400))
        store.delete(recent, now: now.addingTimeInterval(-2 * 86_400))
        store.delete(link, now: now)
        XCTAssertEqual(store.deletedItems().map(\.title), ["a.com", "Recent", "Old"])
        XCTAssertEqual(store.purgeDeleted(now: now), 1)
        XCTAssertEqual(store.deletedItems().count, 2)
        store.restore(.note(recent))
        XCTAssertEqual(store.notes.count, 1)
        store.deleteForever(.link(link))
        XCTAssertTrue(store.deletedItems().isEmpty)
    }

    func testSpaceManagement() throws {
        let store = LibraryStore(directory: nil)
        let added = try XCTUnwrap(store.addSpace(named: "Side Projects"))
        XCTAssertNil(store.addSpace(named: "side-projects"), "names stay unique")
        XCTAssertFalse(store.rename(added, to: "Work"))
        XCTAssertTrue(store.rename(added, to: "Side Work"))
        store.setLook(added, symbol: "bolt", tint: "learning")
        XCTAssertEqual(added.symbol, "bolt")

        let task = try XCTUnwrap(store.add(ParsedCapture(title: "Ship it"), currentSpace: added))
        let note = try XCTUnwrap(store.addNote(fromCapture: "Plan", currentSpace: added))
        store.delete(note)
        let personal = try XCTUnwrap(store.spaces.first { $0.name == "Personal" })
        store.deleteSpace(added, movingItemsTo: personal)
        XCTAssertEqual(task.space?.name, "Personal")
        XCTAssertEqual(note.space?.name, "Personal", "deleted items move too")
        XCTAssertFalse(store.spaces.contains { $0.name == "Side Work" })
        XCTAssertFalse(store.canUndo)

        let reversed = Array(store.spaces.reversed())
        store.reorderSpaces(reversed)
        XCTAssertEqual(store.spaces.map(\.name), reversed.map(\.name))
    }

    func testNewSpaceKeepsChosenLook() throws {
        let store = LibraryStore(directory: nil)
        let space = try XCTUnwrap(store.addSpace(named: "Garden", symbol: "leaf", tint: "learning"))
        XCTAssertEqual(space.symbol, "leaf")
        XCTAssertEqual(space.tintName, "learning")
        XCTAssertNil(store.addSpace(named: "garden"), "names stay unique")
    }
}
