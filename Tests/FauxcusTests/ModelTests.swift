import XCTest
@testable import Fauxcus

final class ModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testSessionSecondsClampedNonNegative() {
        let session = TaskSession(start: t0, end: t0.addingTimeInterval(-100))
        XCTAssertEqual(session.seconds(asOf: t0), 0)
    }

    func testOpenSessionCountsUpToNow() {
        let session = TaskSession(start: t0)
        XCTAssertEqual(session.seconds(asOf: t0.addingTimeInterval(90)), 90)
    }

    func testCloseOpenSessionClampsToStart() {
        var task = TaskRecord(name: "x")
        task.sessions.append(TaskSession(start: t0))
        task.closeOpenSession(at: t0.addingTimeInterval(-500))
        XCTAssertEqual(task.sessions[0].end, t0)
    }

    func testCloseOpenSessionIgnoresClosedSessions() {
        var task = TaskRecord(name: "x")
        task.sessions.append(TaskSession(start: t0, end: t0.addingTimeInterval(60)))
        task.closeOpenSession(at: t0.addingTimeInterval(999))
        XCTAssertEqual(task.sessions[0].end, t0.addingTimeInterval(60))
    }

    func testParkClosesSessionAndStamps() {
        var task = TaskRecord(name: "x")
        task.sessions.append(TaskSession(start: t0))
        let parkDate = t0.addingTimeInterval(300)
        task.park(at: parkDate)
        XCTAssertEqual(task.status, .parked)
        XCTAssertEqual(task.parkedAt, parkDate)
        XCTAssertEqual(task.sessions[0].end, parkDate)
    }

    func testCompleteClosesSessionAndStamps() {
        var task = TaskRecord(name: "x")
        task.sessions.append(TaskSession(start: t0))
        let doneDate = t0.addingTimeInterval(300)
        task.complete(at: doneDate)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.completedAt, doneDate)
        XCTAssertEqual(task.sessions[0].end, doneDate)
    }

    func testBeginSessionClearsParkedAtAndOpensSession() {
        var task = TaskRecord(name: "x")
        task.sessions.append(TaskSession(start: t0))
        task.park(at: t0.addingTimeInterval(10))
        let resumeDate = t0.addingTimeInterval(100)
        task.beginSession(at: resumeDate)
        XCTAssertEqual(task.status, .active)
        XCTAssertNil(task.parkedAt)
        XCTAssertEqual(task.sessions.count, 2)
        XCTAssertEqual(task.sessions[1].start, resumeDate)
        XCTAssertNil(task.sessions[1].end)
    }

    func testMarkMigratedStampsDestination() {
        var task = TaskRecord(name: "x")
        task.markMigrated(to: .todoist)
        XCTAssertEqual(task.status, .migrated)
        XCTAssertEqual(task.exportedTo, .todoist)
    }

    func testFocusedSecondsSumsAllSessions() {
        var task = TaskRecord(name: "x")
        task.sessions.append(TaskSession(start: t0, end: t0.addingTimeInterval(60)))
        task.sessions.append(TaskSession(start: t0.addingTimeInterval(120), end: t0.addingTimeInterval(180)))
        XCTAssertEqual(task.focusedSeconds(asOf: t0.addingTimeInterval(999)), 120)
    }

    func testNoteTailSkipsBlankLines() {
        var task = TaskRecord(name: "x")
        task.notes = "first line\nsecond line\n   \n"
        XCTAssertEqual(task.noteTail, "second line")
    }

    func testNoteTailNilWhenEmpty() {
        XCTAssertNil(TaskRecord(name: "x").noteTail)
    }
}
