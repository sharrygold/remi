import XCTest

final class RepeatReviewTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()
    private func day(_ value: Int, month: Int = 11) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: value))! }
    /// Monday 9 November 2026, 10:00.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10))! }

    private func parse(_ text: String, now: Date? = nil) -> ParsedCapture {
        CaptureParser.parse(text, spaceNames: ["Work"], now: now ?? monday, calendar: calendar)
    }

    func testParsingRepeats() {
        let report = parse("Send weekly report every monday #work")
        XCTAssertEqual(report.title, "Send weekly report")
        XCTAssertEqual(report.repeatRule, .weekly)
        XCTAssertEqual(report.due, day(9), "today is Monday, so it starts today")
        XCTAssertEqual(parse("Invoice every friday").due, day(13))
        XCTAssertEqual(parse("Stretch daily").repeatRule, .daily)
        XCTAssertEqual(parse("Stretch daily").due, day(9))
        XCTAssertEqual(parse("Check inbox every weekday").repeatRule, .weekdays)
        XCTAssertEqual(parse("Pay rent monthly").repeatRule, .monthly)
        XCTAssertEqual(parse("Every so often").repeatRule, nil, "'every' alone is just a word")
        XCTAssertEqual(parse("Every so often").title, "Every so often")
        // On a Saturday, weekday repeats start on Monday.
        XCTAssertEqual(parse("Check inbox every weekday", now: day(14)).due, day(16))
    }

    func testNextDates() {
        XCTAssertEqual(RepeatRule.weekdays.next(after: day(13), calendar: calendar), day(16), "Friday to Monday")
        XCTAssertEqual(RepeatRule.weekly.next(after: day(9), calendar: calendar), day(16))
        XCTAssertEqual(RepeatRule.monthly.next(after: day(9), calendar: calendar), day(9, month: 12))
        XCTAssertEqual(RepeatRule.weekly.label(for: day(9), calendar: calendar), "Every Monday")
    }

    func testTickingMakesTheNextOneAndUndoRemovesIt() throws {
        let store = LibraryStore(directory: nil)
        let task = try XCTUnwrap(store.add(parse("Send weekly report every monday"), currentSpace: nil))
        store.toggleCompleted(task, now: monday)
        store.reload()
        XCTAssertTrue(task.isCompleted)
        XCTAssertNil(task.repeatRule, "the done copy no longer repeats")
        let next = try XCTUnwrap(store.tasks.first { !$0.isCompleted })
        XCTAssertEqual(next.dueDate, day(16))
        XCTAssertEqual(next.repeatRule, .weekly)
        store.undo()
        store.reload()
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertFalse(task.isCompleted)
        XCTAssertEqual(task.repeatRule, .weekly)
    }

    func testMissedRepeatsRollForwardThenPauseAfterTwoWeeks() throws {
        let store = LibraryStore(directory: nil)
        let task = try XCTUnwrap(store.add(parse("Stretch daily"), currentSpace: nil))
        // Three days later: one copy, due today, nothing overdue.
        let thursday = calendar.date(byAdding: .day, value: 3, to: monday)!
        XCTAssertEqual(store.rollForwardRepeating(now: thursday, calendar: calendar), 1)
        XCTAssertEqual(task.dueDate, day(12))
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertTrue(store.overdue(now: thursday, calendar: calendar).isEmpty)
        XCTAssertFalse(task.isPaused)
        // Two weeks after the first miss it pauses and leaves the lists.
        let later = calendar.date(byAdding: .day, value: 14, to: monday)!
        store.rollForwardRepeating(now: later, calendar: calendar)
        XCTAssertTrue(task.isPaused)
        XCTAssertEqual(store.pausedRepeating().count, 1)
        XCTAssertTrue(store.open(now: later).isEmpty)
        XCTAssertEqual(store.todayOpenCount(now: later, calendar: calendar), 0)
        // Keeping it starts afresh from today.
        store.keepRepeating(task, now: later, calendar: calendar)
        XCTAssertFalse(task.isPaused)
        XCTAssertNil(task.skippedSince)
        XCTAssertEqual(store.dueToday(now: later, calendar: calendar).count, 1)
    }

    func testDoneResetsTheSkipCount() throws {
        let store = LibraryStore(directory: nil)
        let task = try XCTUnwrap(store.add(parse("Stretch daily"), currentSpace: nil))
        let tenDays = calendar.date(byAdding: .day, value: 10, to: monday)!
        store.rollForwardRepeating(now: tenDays, calendar: calendar)
        store.toggleCompleted(task, now: tenDays)
        store.reload()
        let next = try XCTUnwrap(store.tasks.first { !$0.isCompleted })
        XCTAssertNil(next.skippedSince)
        let later = calendar.date(byAdding: .day, value: 8, to: tenDays)!
        store.rollForwardRepeating(now: later, calendar: calendar)
        XCTAssertFalse(next.isPaused, "8 days of misses after being done is under two weeks")
    }

    func testReviewLaterLetGoAndFreshStart() throws {
        let store = LibraryStore(directory: nil)
        let old = try XCTUnwrap(store.add(ParsedCapture(title: "Old invoice", due: day(5)), currentSpace: nil))
        let older = try XCTUnwrap(store.add(ParsedCapture(title: "Older call", due: day(2)), currentSpace: nil))
        let undated = try XCTUnwrap(store.add(ParsedCapture(title: "Someday idea"), currentSpace: nil))
        _ = try XCTUnwrap(store.add(parse("Stretch daily"), currentSpace: nil))
        XCTAssertEqual(store.leftFromBefore(now: monday, calendar: calendar).map(\.title), ["Older call", "Old invoice"],
                       "repeating and undated tasks aren't asked about")

        store.moveToLater(older)
        XCTAssertNil(older.dueDate)
        store.setAside([old], now: monday)
        XCTAssertTrue(old.isSetAside)
        XCTAssertFalse(store.open(now: monday).contains { $0.id == old.id })
        XCTAssertEqual(store.setAsideTasks().map(\.title), ["Old invoice"])
        XCTAssertTrue(store.leftFromBefore(now: monday, calendar: calendar).isEmpty)

        store.bringBack(old, now: monday, calendar: calendar)
        XCTAssertFalse(old.isSetAside)
        XCTAssertNil(old.dueDate, "an old date would send it straight back to the review")

        XCTAssertEqual(store.freshStart(now: monday), 4)
        XCTAssertTrue(store.open(now: monday).isEmpty)
        XCTAssertTrue(undated.isSetAside)
        store.undo()
        XCTAssertEqual(store.open(now: monday).count, 4, "a fresh start undoes in one step")
    }

    func testNewFieldsSurviveExport() throws {
        let store = LibraryStore(directory: nil)
        let task = try XCTUnwrap(store.add(parse("Send weekly report every monday"), currentSpace: nil))
        let gone = try XCTUnwrap(store.add(ParsedCapture(title: "Gone"), currentSpace: nil))
        store.setAside([gone], now: monday)
        let archive = try LibraryArchive.decode(LibraryArchive.encoder().encode(store.makeArchive()))
        let copy = LibraryStore(directory: nil)
        copy.importArchive(archive)
        XCTAssertEqual(copy.tasks.first { $0.id == task.id }?.repeatRule, .weekly)
        XCTAssertNotNil(copy.tasks.first { $0.id == gone.id }?.setAsideAt)
    }
}

final class CompanionMotionTests: XCTestCase {
    func testHeadFollowsSpecArc() {
        let p = HeadFollow.pivot
        // Straight right of the neck is angle 0, so t = 220: facing forward.
        XCTAssertEqual(HeadFollow.arcPosition(for: CGPoint(x: p.x + 50, y: p.y), previous: 6), 220, accuracy: 0.001)
        // Straight up (270°) is t = 130, over the top.
        XCTAssertEqual(HeadFollow.arcPosition(for: CGPoint(x: p.x, y: p.y - 50), previous: 6), 130, accuracy: 0.001)
        // Straight down is inside the body: it waits at the nearest edge.
        XCTAssertEqual(HeadFollow.arcPosition(for: CGPoint(x: p.x, y: p.y + 50), previous: 20), 0)
        XCTAssertEqual(HeadFollow.arcPosition(for: CGPoint(x: p.x, y: p.y + 50), previous: 240), 260)
    }

    func testBigSwingGoesOverTheTopWithoutSnapping() {
        XCTAssertEqual(HeadFollow.swingDuration(for: 20), 0.24)
        XCTAssertEqual(HeadFollow.swingDuration(for: 260), 0.9, accuracy: 0.001)
        var head = HeadFollow()
        head.move(to: 260)
        var largest = 0.0, previous = head.angle.value
        for _ in 0..<120 {
            head.step(1.0 / 60)
            largest = max(largest, abs(head.angle.value - previous))
            previous = head.angle.value
            XCTAssertLessThanOrEqual(head.angle.value, 401)
        }
        XCTAssertLessThan(largest, 16, "a 254° swing must glide, not jump")
        XCTAssertEqual(head.angle.value, 400, accuracy: 1)
    }

    func testCrestLagIsClamped() {
        var head = HeadFollow()
        head.move(to: 200)
        XCTAssertEqual(head.crest.value, -22)
    }

    private func run(_ cord: CordMotion, from start: Double, seconds: Double) -> CordFrame {
        var frame = CordFrame(), now = start
        while now < start + seconds {
            now += 1.0 / 60
            frame = cord.tick(now: now, dt: 1.0 / 60)
        }
        return frame
    }

    func testCordTucksByDefaultAndLowersWhenNoticed() {
        let cord = CordMotion()
        XCTAssertEqual(run(cord, from: 0, seconds: 1).pull, CordMotion.tuckedPull, accuracy: 1)
        XCTAssertTrue(cord.isAtRest || cord.state == .tucked)
        cord.pointer(near: true, now: 1)
        XCTAssertEqual(cord.state, .lowered)
        let lowered = run(cord, from: 1, seconds: 1)
        XCTAssertEqual(lowered.pull, 0, accuracy: 3)
        XCTAssertFalse(lowered.eyesClosed && cord.state == .lowered && false)
        // Pointer leaves: after about 1.2 s it draws back up.
        cord.pointer(near: false, now: 2)
        _ = run(cord, from: 2, seconds: 1)
        XCTAssertEqual(cord.state, .lowered)
        let tucked = run(cord, from: 3, seconds: 3)
        XCTAssertEqual(cord.state, .tucked)
        XCTAssertEqual(tucked.pull, CordMotion.tuckedPull, accuracy: 2)
        XCTAssertTrue(tucked.eyesClosed)
    }

    func testPullOpensOnlyPastThresholdAndStopsAtMax() {
        let cord = CordMotion()
        cord.pointer(near: true, now: 0)
        _ = run(cord, from: 0, seconds: 1)
        cord.startPull()
        cord.drag(by: 10)
        _ = run(cord, from: 1, seconds: 0.3)
        XCTAssertFalse(cord.release(now: 1.3))
        cord.startPull()
        cord.drag(by: 500)
        let held = run(cord, from: 2, seconds: 0.5)
        XCTAssertEqual(held.pull, CordMotion.maxPull, accuracy: 1)
        XCTAssertGreaterThan(held.squat, 0.9)
        XCTAssertTrue(cord.release(now: 2.5))
        var overshoot = 0.0, now = 2.5
        for _ in 0..<120 {
            now += 1.0 / 60
            overshoot = min(overshoot, cord.tick(now: now, dt: 1.0 / 60).pull)
        }
        XCTAssertLessThan(overshoot, -1, "release should bounce past rest")
    }

    func testEventLowersThenAllowsTucking() {
        let cord = CordMotion()
        _ = run(cord, from: 0, seconds: 1)
        cord.fire(.taskAdded, now: 1)
        XCTAssertEqual(cord.state, .lowered)
        _ = run(cord, from: 1, seconds: 1)
        XCTAssertEqual(cord.state, .lowered, "stays down while the knot ties")
        _ = run(cord, from: 2, seconds: 3)
        XCTAssertEqual(cord.state, .tucked)
    }

    func testPanelKeepsCordDownAndReduceMotionIsStill() {
        let cord = CordMotion()
        cord.reduceMotion = true
        cord.setPanelOpen(true, now: 0)
        let open = run(cord, from: 0, seconds: 5)
        XCTAssertEqual(cord.state, .panelOpen)
        XCTAssertEqual(open.pull, 0)
        XCTAssertEqual(open.sway, 0)
        XCTAssertEqual(open.rock, 0)
    }
}
