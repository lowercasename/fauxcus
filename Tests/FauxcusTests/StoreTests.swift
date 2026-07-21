import XCTest
@testable import Fauxcus

@MainActor
final class StoreTests: XCTestCase {
    private func tempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fauxcus-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    func testSaveLoadRoundtrip() {
        let url = tempStoreURL()
        let store = Store(fileURL: url)
        var task = TaskRecord(name: "roundtrip")
        task.notes = "some notes"
        task.complete()
        store.add(task)

        let loaded = Store.load(from: url)
        XCTAssertEqual(loaded.tasks.count, 1)
        XCTAssertEqual(loaded.tasks[0].name, "roundtrip")
        XCTAssertEqual(loaded.tasks[0].notes, "some notes")
        XCTAssertEqual(loaded.tasks[0].status, .completed)
        XCTAssertNil(loaded.loadWarning)
    }

    func testHealParksInterruptedTaskAtHeartbeat() {
        let url = tempStoreURL()
        let store = Store(fileURL: url)
        var task = TaskRecord(name: "interrupted")
        task.sessions.append(TaskSession(start: Date().addingTimeInterval(-600)))
        store.add(task)
        store.heartbeat()
        let heartbeatTime = Date()

        let loaded = Store.load(from: url)
        XCTAssertEqual(loaded.tasks[0].status, .parked)
        let end = loaded.tasks[0].sessions[0].end
        XCTAssertNotNil(end)
        // Session closed at the persisted heartbeat, within save/load tolerance.
        XCTAssertEqual(end!.timeIntervalSince(heartbeatTime), 0, accuracy: 2)
        XCTAssertNil(loaded.currentTask)
    }

    func testHealWithoutHeartbeatClosesAtSessionStart() {
        let url = tempStoreURL()
        let store = Store(fileURL: url)
        var task = TaskRecord(name: "no-heartbeat")
        let start = Date().addingTimeInterval(-600)
        task.sessions.append(TaskSession(start: start))
        store.add(task)
        // No heartbeat() call — payload persists with heartbeat == nil.

        let loaded = Store.load(from: url)
        XCTAssertEqual(loaded.tasks[0].status, .parked)
        XCTAssertEqual(loaded.tasks[0].sessions[0].end!.timeIntervalSince(start), 0, accuracy: 1)
        XCTAssertEqual(loaded.tasks[0].focusedSeconds(), 0, accuracy: 1)
    }

    func testCorruptStoreIsBackedUpNotOverwritten() throws {
        let url = tempStoreURL()
        try Data("this is not json".utf8).write(to: url)

        let loaded = Store.load(from: url)
        XCTAssertTrue(loaded.tasks.isEmpty)
        XCTAssertNotNil(loaded.loadWarning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let backups = try FileManager.default
            .contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("corrupt") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: backups[0], encoding: .utf8), "this is not json")
    }

    func testUpdateUnknownIDReturnsFalse() {
        let store = Store(fileURL: tempStoreURL())
        XCTAssertFalse(store.update(UUID()) { $0.name = "nope" })
    }

    func testDeleteRemovesEntirely() {
        let store = Store(fileURL: tempStoreURL())
        var task = TaskRecord(name: "doomed")
        task.park()
        store.add(task)
        store.delete(task.id)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testSuggestionMatchesPrefixCaseInsensitively() {
        let store = Store(fileURL: tempStoreURL())
        var task = TaskRecord(name: "Triage email")
        task.complete()
        store.add(task)
        XCTAssertEqual(store.suggestion(for: "tri"), "Triage email")
        XCTAssertNil(store.suggestion(for: "t"), "requires at least 2 characters")
        XCTAssertNil(store.suggestion(for: "email"), "prefix match only")
        XCTAssertNil(store.suggestion(for: "Triage email"), "exact match suggests nothing")
    }

    func testParkedSortedNewestFirstAndOldestFirstMirrors() {
        let store = Store(fileURL: tempStoreURL())
        var old = TaskRecord(name: "old")
        old.park(at: Date().addingTimeInterval(-100))
        var new = TaskRecord(name: "new")
        new.park(at: Date())
        store.add(old)
        store.add(new)
        XCTAssertEqual(store.parked.map(\.name), ["new", "old"])
        XCTAssertEqual(store.parkedOldestFirst.map(\.name), ["old", "new"])
    }
}
