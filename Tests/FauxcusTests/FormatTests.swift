import XCTest
@testable import Fauxcus

final class FormatTests: XCTestCase {
    func testClockUnderAnHour() {
        XCTAssertEqual(Format.clock(0), "00:00")
        XCTAssertEqual(Format.clock(275), "04:35")
        XCTAssertEqual(Format.clock(3599), "59:59")
    }

    func testClockOverAnHour() {
        XCTAssertEqual(Format.clock(3600), "1:00:00")
        XCTAssertEqual(Format.clock(3661), "1:01:01")
    }

    func testClockClampsNegative() {
        XCTAssertEqual(Format.clock(-5), "00:00")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(30), "under a minute")
        XCTAssertEqual(Format.duration(47 * 60), "47 min")
        XCTAssertEqual(Format.duration(3600), "1 h")
        XCTAssertEqual(Format.duration(4320), "1 h 12 min")
    }

    func testMarkdownRenderIncludesNameStatusAndNotes() {
        var task = TaskRecord(name: "Ship the tests")
        task.sessions.append(TaskSession(start: Date().addingTimeInterval(-2820), end: Date()))
        task.notes = "remember the edge cases"
        task.complete()
        let rendered = Markdown.render(task)
        XCTAssertTrue(rendered.contains("## Ship the tests"))
        XCTAssertTrue(rendered.contains("- Status: completed"))
        XCTAssertTrue(rendered.contains("- Focused: 47 min"))
        XCTAssertTrue(rendered.contains("remember the edge cases"))
    }
}
