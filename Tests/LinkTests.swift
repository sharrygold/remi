import XCTest
import SwiftData

final class LinkClassifierTests: XCTestCase {
    private func url(_ text: String) -> URL { URL(string: text)! }

    func testRecognisesURLs() {
        XCTAssertEqual(LinkClassifier.url(from: "https://youtu.be/abc")?.host(), "youtu.be")
        XCTAssertEqual(LinkClassifier.url(from: "www.example.com/jobs")?.absoluteString, "https://www.example.com/jobs")
        XCTAssertEqual(LinkClassifier.url(from: "example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(LinkClassifier.url(from: "<https://linear.app/x>")?.host(), "linear.app")
        for word in ["notes.md", "e.g.", "file.txt", "hello", "v1.2", "https://nohost", "#clients", "a..com"] {
            XCTAssertNil(LinkClassifier.url(from: word), word)
        }
    }

    func testVideoClassification() {
        for video in ["https://www.youtube.com/watch?v=x", "https://youtu.be/x", "https://m.youtube.com/shorts/x",
                      "https://vimeo.com/123456", "https://www.ted.com/talks/a_talk", "https://www.tiktok.com/@a/video/1"] {
            XCTAssertEqual(LinkClassifier.list(for: url(video)), .watchLater, video)
        }
        for saved in ["https://www.youtube.com/@channel", "https://youtube.com", "https://vimeo.com/channels/staff",
                      "https://www.loom.com/share/abc", "https://www.example.com/team/~01"] {
            XCTAssertEqual(LinkClassifier.list(for: url(saved)), .saved, saved)
        }
    }

    func testNormalisedComparison() {
        XCTAssertEqual(LinkClassifier.normalized(url("https://www.example.com/jobs/")), LinkClassifier.normalized(url("http://example.com/jobs#top")))
        XCTAssertNotEqual(LinkClassifier.normalized(url("https://youtube.com/watch?v=a")), LinkClassifier.normalized(url("https://youtube.com/watch?v=b")))
    }

    func testParserFindsURL() {
        let link = CaptureParser.parse("https://youtu.be/abc #learning", spaceNames: ["Learning"])
        XCTAssertTrue(link.isLink)
        XCTAssertEqual(link.space, .existing("Learning"))
        let task = CaptureParser.parse("Update profile example.com/team today", spaceNames: [])
        XCTAssertFalse(task.isLink)
        XCTAssertEqual(task.title, "Update profile")
        XCTAssertEqual(task.url?.host(), "example.com")
        XCTAssertNotNil(task.due)
        XCTAssertNil(CaptureParser.parse("Read notes.md", spaceNames: []).url)
    }
}

@MainActor
final class LinkStoreTests: XCTestCase {
    private func url(_ text: String) -> URL { URL(string: text)! }

    func testAddClassifiesDedupesAndUndoes() {
        let store = LibraryStore(directory: nil)
        var added: [String] = []
        store.onLinkAdded = { added.append($0.urlString) }
        let video = store.addLink(url("https://www.youtube.com/watch?v=a"), currentSpace: nil)
        XCTAssertTrue(video.isNew)
        XCTAssertEqual(video.link.list, .watchLater)
        XCTAssertEqual(video.link.title, "youtube.com")
        XCTAssertEqual(video.link.space?.name, "Personal")
        let again = store.addLink(url("https://youtube.com/watch?v=a"), currentSpace: nil)
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(store.links.count, 1)
        XCTAssertEqual(added.count, 1)
        let forced = store.addLink(url("https://example.com/article"), list: .watchLater, spaceMatch: .new("Reading"), currentSpace: nil)
        XCTAssertEqual(forced.link.list, .watchLater)
        XCTAssertEqual(store.spaces.count, 6)
        store.undo()
        XCTAssertEqual(store.links.count, 1)
        XCTAssertEqual(store.spaces.count, 5)
    }

    func testWatchedPinnedAndLists() {
        let store = LibraryStore(directory: nil)
        let a = store.addLink(url("https://a.com"), currentSpace: nil).link
        let b = store.addLink(url("https://b.com"), currentSpace: nil).link
        let video = store.addLink(url("https://youtu.be/x"), currentSpace: nil).link
        XCTAssertEqual(store.links(in: nil, list: .saved).map(\.urlString), [b.urlString, a.urlString])
        store.setPinned(a, true)
        XCTAssertEqual(store.links(in: nil, list: .saved).first?.id, a.id)
        XCTAssertEqual(store.watchLaterCount(), 1)
        store.setWatched(video, true)
        XCTAssertEqual(store.watchLaterCount(), 0)
        XCTAssertEqual(store.links(in: nil, list: .watchLater, watched: true).count, 1)
        store.undo()
        XCTAssertEqual(store.watchLaterCount(), 1)
        store.move(video, to: .saved)
        XCTAssertEqual(store.links(in: nil, list: .saved).count, 3)
        store.delete(b)
        XCTAssertEqual(store.links.count, 2)
    }

    func testMetadataAndSavedCheck() throws {
        let store = LibraryStore(directory: nil)
        let link = store.addLink(url("https://youtu.be/x"), currentSpace: nil).link
        store.setMetadata(for: link.id, title: "  Me at the zoo \n", iconData: Data([1]))
        XCTAssertEqual(link.title, "Me at the zoo")
        XCTAssertTrue(link.titleFetched)
        XCTAssertTrue(store.isSaved(url("https://youtu.be/x/")))
        let task = try XCTUnwrap(store.add(CaptureParser.parse("Profile https://example.com/me", spaceNames: []), currentSpace: nil))
        XCTAssertEqual(task.action, .url(url("https://example.com/me")))
        XCTAssertTrue(store.isSaved(url("https://www.example.com/me")))
        XCTAssertFalse(store.isSaved(url("https://other.com")))
    }

    func testTaskActionsRoundTripAndUndo() throws {
        let store = LibraryStore(directory: nil)
        let task = try XCTUnwrap(store.add(ParsedCapture(title: "Record Loom"), currentSpace: nil))
        let app = URL(fileURLWithPath: "/Applications/Loom.app")
        store.setAction(task, .app(app))
        XCTAssertEqual(task.action, .app(app))
        XCTAssertEqual(task.action?.label, "Loom")
        store.setAction(task, .file(URL(fileURLWithPath: "/Users/Shared/Documents")))
        store.undo()
        XCTAssertEqual(task.action, .app(app))
        store.setAction(task, nil)
        XCTAssertNil(task.actionKind)
        XCTAssertNil(task.actionTarget)
    }

    func testLinksSurviveReopening() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = LibraryStore(directory: directory)
            let link = store.addLink(url("https://youtu.be/x"), currentSpace: nil).link
            store.setMetadata(for: link.id, title: "Zoo", iconData: nil)
        }
        let reopened = LibraryStore(directory: directory)
        XCTAssertEqual(reopened.links.first?.title, "Zoo")
        XCTAssertEqual(reopened.links.first?.list, .watchLater)
    }
}
