import XCTest
import SwiftData

@MainActor
final class TaskStoreTests: XCTestCase {
    private let calendar = Calendar.current
    private let now = Date()
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))! }
    private var today: Date { calendar.startOfDay(for: now) }

    private func parsed(_ title: String, space: ParsedCapture.SpaceMatch = .none, due: Date? = nil) -> ParsedCapture {
        ParsedCapture(title: title, space: space, due: due)
    }

    func testSeedsFiveSpacesOnce() {
        let store = TaskStore(directory: nil)
        XCTAssertEqual(store.spaces.map(\.name), ["Clients", "Work", "Personal", "Learning", "Home Reno"])
    }

    func testDataSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = TaskStore(directory: directory)
            store.add(parsed("Keep me", space: .new("Garden"), due: today), currentSpace: nil)
        }
        let reopened = TaskStore(directory: directory)
        XCTAssertFalse(reopened.isTemporary)
        XCTAssertEqual(reopened.tasks.map(\.title), ["Keep me"])
        XCTAssertEqual(reopened.tasks.first?.space?.name, "Garden")
        XCTAssertEqual(reopened.spaces.count, 6)
    }

    func testSpaceRules() {
        let store = TaskStore(directory: nil)
        let work = store.spaces.first { $0.name == "Work" }
        XCTAssertEqual(store.add(parsed("Current"), currentSpace: work)?.space?.name, "Work")
        XCTAssertEqual(store.add(parsed("Fallback"), currentSpace: nil)?.space?.name, "Personal")
        XCTAssertEqual(store.add(parsed("Tagged", space: .existing("Clients")), currentSpace: work)?.space?.name, "Clients")
    }

    func testUndoCaptureAlsoRemovesNewSpace() {
        let store = TaskStore(directory: nil)
        store.add(parsed("Temp", space: .new("Garden")), currentSpace: nil)
        XCTAssertEqual(store.spaces.count, 6)
        store.undo()
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertEqual(store.spaces.count, 5)
        XCTAssertFalse(store.canUndo)
    }

    func testNewestFirstAndReorder() throws {
        let store = TaskStore(directory: nil)
        store.add(parsed("A"), currentSpace: nil)
        store.add(parsed("B"), currentSpace: nil)
        store.add(parsed("C"), currentSpace: nil)
        XCTAssertEqual(store.tasks.map(\.title), ["C", "B", "A"])
        store.reorder([store.tasks[2], store.tasks[0], store.tasks[1]])
        XCTAssertEqual(store.tasks.map(\.title), ["A", "C", "B"])
        store.undo()
        XCTAssertEqual(store.tasks.map(\.title), ["C", "B", "A"])
    }

    func testTodayAndOverdueLists() {
        let store = TaskStore(directory: nil)
        store.add(parsed("Today", due: today), currentSpace: nil)
        store.add(parsed("Late", due: yesterday), currentSpace: nil)
        store.add(parsed("Someday"), currentSpace: nil)
        XCTAssertEqual(store.dueToday().map(\.title), ["Today"])
        XCTAssertEqual(store.overdue().map(\.title), ["Late"])
        XCTAssertEqual(store.todayOpenCount(), 1)
    }

    func testCompletedLingersThenMovesToDone() throws {
        let store = TaskStore(directory: nil)
        let task = try XCTUnwrap(store.add(parsed("Tick", due: today), currentSpace: nil))
        store.toggleCompleted(task, now: now)
        XCTAssertEqual(store.todayOpenCount(now: now), 0)
        XCTAssertEqual(store.open(now: now.addingTimeInterval(0.5)).count, 1)
        XCTAssertTrue(store.done(now: now.addingTimeInterval(0.5)).isEmpty)
        XCTAssertTrue(store.open(now: now.addingTimeInterval(2)).isEmpty)
        XCTAssertEqual(store.done(now: now.addingTimeInterval(2)).count, 1)
        store.undo()
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
    }

    func testDeleteHidesAndUndoRestores() throws {
        let store = TaskStore(directory: nil)
        let task = try XCTUnwrap(store.add(parsed("Gone"), currentSpace: nil))
        store.delete(task)
        XCTAssertTrue(store.tasks.isEmpty)
        store.undo()
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testRenameIgnoresBlank() throws {
        let store = TaskStore(directory: nil)
        let task = try XCTUnwrap(store.add(parsed("Old"), currentSpace: nil))
        store.rename(task, to: "   ")
        XCTAssertEqual(task.title, "Old")
        store.rename(task, to: " New ")
        XCTAssertEqual(task.title, "New")
    }

    func testMoveBetweenSpaces() throws {
        let store = TaskStore(directory: nil)
        let task = try XCTUnwrap(store.add(parsed("Move"), currentSpace: nil))
        let learning = try XCTUnwrap(store.spaces.first { $0.name == "Learning" })
        store.move(task, to: learning)
        XCTAssertEqual(store.open(in: learning).count, 1)
        store.undo()
        XCTAssertEqual(task.space?.name, "Personal")
    }
}
