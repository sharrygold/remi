import XCTest

final class CaptureParserTests: XCTestCase {
    private let spaces = ["Clients", "Work", "Personal", "Learning", "Home Reno"]
    private let calendar = Calendar(identifier: .gregorian)
    /// A Monday.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10))! }

    private func parse(_ text: String) -> ParsedCapture {
        CaptureParser.parse(text, spaceNames: spaces, now: now, calendar: calendar)
    }

    private func day(_ value: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: value))! }

    func testPlainText() {
        XCTAssertEqual(parse("Send that invoice"), ParsedCapture(title: "Send that invoice"))
    }

    func testExistingSpaceIgnoresCaseAndSpacing() {
        XCTAssertEqual(parse("Call #CLIENTS client").space, .existing("Clients"))
        XCTAssertEqual(parse("Sketch logo #homereno").space, .existing("Home Reno"))
        XCTAssertEqual(parse("Sketch logo #home-reno").space, .existing("Home Reno"))
        XCTAssertEqual(parse("Call #clients client").title, "Call client")
    }

    func testNewSpace() {
        XCTAssertEqual(parse("Plan trip #somethingnew").space, .new("Somethingnew"))
        XCTAssertEqual(parse("Plan #side-project").space, .new("Side Project"))
    }

    func testLoneHashIsTitleText() {
        let parsed = parse("Item # five")
        XCTAssertEqual(parsed.space, .none)
        XCTAssertEqual(parsed.title, "Item # five")
    }

    func testTodayAndTomorrowAnywhere() {
        XCTAssertEqual(parse("today call Dana").due, day(9))
        XCTAssertEqual(parse("today call Dana").title, "call Dana")
        XCTAssertEqual(parse("Call Dana tomorrow please").due, day(10))
        XCTAssertEqual(parse("Call Dana TMRW").due, day(10))
    }

    func testPossessiveIsNotADate() {
        let parsed = parse("Review today's numbers")
        XCTAssertNil(parsed.due)
        XCTAssertEqual(parsed.title, "Review today's numbers")
    }

    func testWeekdayOnlyAsLastWord() {
        XCTAssertEqual(parse("Send invoice fri").due, day(13))
        XCTAssertEqual(parse("Send invoice friday #clients !").due, day(13))
        let parsed = parse("Sat exam prep")
        XCTAssertNil(parsed.due)
        XCTAssertEqual(parsed.title, "Sat exam prep")
    }

    func testSameWeekdayMeansNextWeek() {
        XCTAssertEqual(parse("Team call mon").due, day(16))
    }

    func testImportant() {
        XCTAssertTrue(parse("Pay rent !").important)
        XCTAssertEqual(parse("Pay rent !").title, "Pay rent")
        XCTAssertTrue(parse("! Pay rent").important)
        XCTAssertTrue(parse("Pay rent!").important)
        XCTAssertEqual(parse("Pay rent!").title, "Pay rent")
        XCTAssertFalse(parse("Wow! nice work").important)
    }

    func testEverythingTogether() {
        let parsed = parse("Send design invoice #clients tomorrow !")
        XCTAssertEqual(parsed, ParsedCapture(title: "Send design invoice", space: .existing("Clients"), due: day(10), important: true))
    }

    func testOnlyTokensCannotSave() {
        XCTAssertFalse(parse("today #clients !").canSave)
        XCTAssertFalse(parse("   ").canSave)
    }
}
