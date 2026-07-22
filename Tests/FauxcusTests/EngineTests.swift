import Combine
import XCTest
@testable import Fauxcus

@MainActor
final class EngineTests: XCTestCase {
    /// Deterministic clock + idle source injected into the engine.
    final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var idleSeconds: TimeInterval = 0

        func advance(_ seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    private func makeSUT() -> (FocusEngine, Store, TestClock) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fauxcus-engine-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store(fileURL: dir.appendingPathComponent("store.json"))
        let engine = FocusEngine(store: store)
        let clock = TestClock()
        engine.dateNow = { clock.now }
        engine.idleSecondsProvider = { clock.idleSeconds }
        return (engine, store, clock)
    }

    // MARK: - Starting

    func testStartTaskBeginsRunning() {
        let (engine, store, _) = makeSUT()
        engine.startTask(named: "  write tests  ")
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(store.currentTask?.name, "write tests")
        XCTAssertEqual(store.currentTask?.sessions.count, 1)
        XCTAssertNil(store.currentTask?.sessions.last?.end)
    }

    func testStartTaskWithEmptyNameDoesNothing() {
        let (engine, store, _) = makeSUT()
        engine.startTask(named: "   ")
        XCTAssertEqual(engine.phase, .picker)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testSecondStartTaskIsIgnoredWhileOneIsActive() {
        let (engine, store, _) = makeSUT()
        engine.startTask(named: "first")
        engine.startTask(named: "second")
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.currentTask?.name, "first")
    }

    func testResumeUnknownIDFallsBackToPicker() {
        let (engine, _, _) = makeSUT()
        engine.resume(UUID())
        XCTAssertEqual(engine.phase, .picker)
    }

    // MARK: - Check-in cadence

    func testCheckInFiresAtTenMinutes() {
        let (engine, _, clock) = makeSUT()
        engine.startTask(named: "focus")
        clock.advance(599)
        engine.tick()
        XCTAssertEqual(engine.phase, .running)
        clock.advance(1)
        engine.tick()
        XCTAssertEqual(engine.phase, .checkIn)
    }

    func testBreathFiresOnceAtIntervalMidpoint() {
        let (engine, _, clock) = makeSUT()
        var breaths = 0
        engine.breath.sink { breaths += 1 }.store(in: &cancellables)
        engine.startTask(named: "focus")
        clock.advance(299)
        engine.tick()
        XCTAssertEqual(breaths, 0)
        clock.advance(1)
        engine.tick()
        XCTAssertEqual(breaths, 1)
        clock.advance(60)
        engine.tick()
        XCTAssertEqual(breaths, 1, "breath fires once per interval")
    }

    func testIgnoredCheckInTimesOutAsYesAndCadenceStaysFlat() {
        let (engine, _, clock) = makeSUT()
        engine.startTask(named: "focus")
        clock.advance(600)
        engine.tick()
        XCTAssertEqual(engine.phase, .checkIn)
        clock.advance(60)
        engine.tick()
        XCTAssertEqual(engine.phase, .running, "60s of silence counts as Yes")
        // Flat cadence: next check-in is 10 minutes later, not backed off.
        clock.advance(599)
        engine.tick()
        XCTAssertEqual(engine.phase, .running)
        clock.advance(1)
        engine.tick()
        XCTAssertEqual(engine.phase, .checkIn)
    }

    func testConfirmingKeepsFlatTenMinuteCadence() {
        let (engine, _, clock) = makeSUT()
        engine.startTask(named: "focus")
        for _ in 0..<3 {
            clock.advance(600)
            engine.tick()
            XCTAssertEqual(engine.phase, .checkIn)
            engine.confirmStillOnIt()
        }
    }

    // MARK: - Idle & sleep

    func testIdleAutoPausesBackdatedToDeparture() {
        let (engine, store, clock) = makeSUT()
        engine.startTask(named: "focus")
        clock.advance(1000)
        clock.idleSeconds = 400
        engine.tick()
        XCTAssertEqual(engine.phase, .away)
        let end = store.tasks[0].sessions.last?.end
        XCTAssertNotNil(end)
        XCTAssertEqual(end, clock.now.addingTimeInterval(-400), "away time never counts")
        XCTAssertEqual(store.tasks[0].focusedSeconds(asOf: clock.now), 600)
    }

    func testShortIdleDoesNotPause() {
        let (engine, _, clock) = makeSUT()
        engine.startTask(named: "focus")
        clock.advance(200)
        clock.idleSeconds = 299
        engine.tick()
        XCTAssertEqual(engine.phase, .running)
    }

    func testResumeFromAwayReopensSessionAndRestartsCadence() {
        let (engine, store, clock) = makeSUT()
        engine.startTask(named: "focus")
        clock.advance(1000)
        clock.idleSeconds = 400
        engine.tick()
        clock.idleSeconds = 0
        engine.resumeFromAway()
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(store.tasks[0].sessions.count, 2)
        clock.advance(600)
        engine.tick()
        XCTAssertEqual(engine.phase, .checkIn, "cadence restarts from the resume")
    }

    // MARK: - Pause, break, park

    func testPauseClosesSessionAndBackToWorkReopens() {
        let (engine, store, clock) = makeSUT()
        engine.startTask(named: "focus")
        clock.advance(120)
        engine.requestPause()
        XCTAssertEqual(engine.phase, .pauseMenu)
        XCTAssertNotNil(store.tasks[0].sessions.last?.end)
        clock.advance(60)
        engine.backToWork()
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(store.tasks[0].sessions.count, 2)
        // The paused minute doesn't count.
        XCTAssertEqual(store.tasks[0].focusedSeconds(asOf: clock.now), 120)
    }

    func testBreakNudgesAtTenMinutesThenEveryFive() {
        let (engine, _, clock) = makeSUT()
        var waves = 0
        engine.wave.sink { waves += 1 }.store(in: &cancellables)
        engine.startTask(named: "focus")
        engine.requestPause()
        engine.takeBreak()
        XCTAssertEqual(engine.phase, .onBreak)
        clock.advance(599)
        engine.tick()
        XCTAssertEqual(waves, 0)
        clock.advance(1)
        engine.tick()
        XCTAssertEqual(waves, 1)
        clock.advance(300)
        engine.tick()
        XCTAssertEqual(waves, 2)
    }

    func testParkStoresBreadcrumbAndReturnsToPicker() {
        let (engine, store, _) = makeSUT()
        engine.startTask(named: "focus")
        engine.requestPause()
        engine.beginSwitchTask()
        XCTAssertEqual(engine.phase, .switchNote)
        engine.parkCurrent(notes: "resume at the auth refactor")
        XCTAssertEqual(engine.phase, .picker)
        XCTAssertEqual(store.parked.count, 1)
        XCTAssertEqual(store.parked[0].notes, "resume at the auth refactor")
        XCTAssertNil(store.currentTask)
    }

    func testParkingSixthTaskRequiresMigration() {
        let (engine, store, _) = makeSUT()
        for i in 1...5 {
            var task = TaskRecord(name: "parked \(i)")
            task.park()
            store.add(task)
        }
        engine.startTask(named: "sixth")
        engine.requestPause()
        engine.beginSwitchTask()
        engine.parkCurrent(notes: "the overflow")
        XCTAssertEqual(engine.phase, .parkingFull)
        XCTAssertEqual(store.parked.count, 5, "park is blocked at the cap")
        XCTAssertNotNil(store.currentTask, "task is still active while blocked")

        // Freeing a slot completes the pending park automatically.
        engine.migrate(store.parkedOldestFirst[0].id, to: .markdown)
        XCTAssertEqual(engine.phase, .picker)
        XCTAssertEqual(store.parked.count, 5)
        XCTAssertEqual(store.parked.first { $0.name == "sixth" }?.notes, "the overflow")
        XCTAssertNil(store.currentTask)
        XCTAssertEqual(store.history.filter { $0.status == .migrated }.count, 1)
    }

    func testDeleteParkedAlsoCompletesPendingPark() {
        let (engine, store, _) = makeSUT()
        for i in 1...5 {
            var task = TaskRecord(name: "parked \(i)")
            task.park()
            store.add(task)
        }
        engine.startTask(named: "sixth")
        engine.requestPause()
        engine.beginSwitchTask()
        engine.parkCurrent(notes: "overflow")
        engine.deleteParked(store.parkedOldestFirst[0].id)
        XCTAssertEqual(engine.phase, .picker)
        XCTAssertEqual(store.parked.count, 5)
        XCTAssertNil(store.currentTask)
    }

    func testCompleteParkedMovesToHistoryAndCompletesPendingPark() {
        let (engine, store, clock) = makeSUT()
        for i in 1...5 {
            var task = TaskRecord(name: "parked \(i)")
            task.park()
            store.add(task)
        }
        engine.startTask(named: "sixth")
        engine.requestPause()
        engine.beginSwitchTask()
        engine.parkCurrent(notes: "overflow")
        XCTAssertEqual(engine.phase, .parkingFull)

        let finished = store.parkedOldestFirst[0]
        engine.completeParked(finished.id)
        XCTAssertEqual(engine.phase, .picker, "freed slot completes the pending park")
        XCTAssertEqual(store.parked.count, 5)
        XCTAssertNil(store.currentTask)
        let record = store.tasks.first { $0.id == finished.id }
        XCTAssertEqual(record?.status, .completed)
        XCTAssertEqual(record?.completedAt, clock.now)
    }

    // MARK: - Completion & termination

    func testCompleteClosesTaskAndShowsFlourish() {
        let (engine, store, clock) = makeSUT()
        engine.startTask(named: "focus")
        clock.advance(300)
        engine.completeCurrent()
        XCTAssertEqual(engine.phase, .completion)
        XCTAssertEqual(engine.completedSnapshot?.name, "focus")
        XCTAssertEqual(store.tasks[0].status, .completed)
        XCTAssertEqual(store.tasks[0].focusedSeconds(asOf: clock.now), 300)
    }

    func testAppWillTerminateParksActiveTask() {
        let (engine, store, _) = makeSUT()
        engine.startTask(named: "focus")
        engine.appWillTerminate()
        XCTAssertEqual(store.tasks[0].status, .parked)
        XCTAssertNotNil(store.tasks[0].sessions.last?.end)
    }

    func testNotesLiveSaveReplacesBlob() {
        let (engine, store, _) = makeSUT()
        engine.startTask(named: "focus")
        engine.setNotesForCurrent("first draft")
        engine.setNotesForCurrent("first draft\nsecond thought")
        XCTAssertEqual(store.currentTask?.notes, "first draft\nsecond thought")
    }
}
