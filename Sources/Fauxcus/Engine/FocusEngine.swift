import AppKit
import Combine

@MainActor
final class FocusEngine: ObservableObject {
    enum Phase: Equatable {
        case firstRun
        case picker
        case running
        case checkIn
        case pauseMenu
        case switchNote
        case onBreak
        case away
        case completion
        case parkingFull
    }

    // Fixed, opinionated defaults — deliberately not user-configurable.
    static let checkInIntervals: [TimeInterval] = [600, 900, 1200, 1500] // 10 → 15 → 20 → 25 min
    static let checkInTimeout: TimeInterval = 60
    static let idleThreshold: TimeInterval = 300
    static let breakFirstNudge: TimeInterval = 600
    static let breakRepeatNudge: TimeInterval = 300
    static let parkedCap = 5
    static let completionFlourishDuration: TimeInterval = 1.8
    static let heartbeatInterval: TimeInterval = 30

    @Published private(set) var phase: Phase
    @Published private(set) var now = Date()
    @Published var focusNoteRequest = 0
    @Published var focusTaskRequest = 0
    @Published private(set) var completedSnapshot: TaskRecord?
    @Published var migrationError: String?
    @Published private(set) var migratingIDs: Set<UUID> = []

    /// Fires the 2-second "breath" animation in whichever view is listening.
    let breath = PassthroughSubject<Void, Never>()

    /// Fires the more obvious sheen-wave across the whole panel — used for
    /// alerts that would like an answer (check-in, break nudge). Still silent.
    let wave = PassthroughSubject<Void, Never>()

    let store: Store

    private var intervalIndex = 0
    private var anchor = Date()
    private var breathFired = false
    private var checkInDeadline: Date?
    private var breakStart: Date?
    private var nextBreakNudge: Date?
    private var pendingParkNote: String?
    private var lastHeartbeat = Date.distantPast
    private var ticker: Timer?

    init(store: Store) {
        self.store = store
        phase = UserDefaults.standard.bool(forKey: "hasCompletedFirstRun") ? .picker : .firstRun
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        observeSleep()
    }

    // MARK: - Clock

    private func tick() {
        now = Date()
        switch phase {
        case .running:
            maintainHeartbeat()
            if checkIdle() { return }
            let interval = Self.checkInIntervals[intervalIndex]
            if !breathFired && now >= anchor.addingTimeInterval(interval / 2) {
                breathFired = true
                breath.send()
            }
            if now >= anchor.addingTimeInterval(interval) {
                checkInDeadline = now.addingTimeInterval(Self.checkInTimeout)
                phase = .checkIn
                wave.send()
            }
        case .checkIn:
            maintainHeartbeat()
            if checkIdle() { return }
            // Ignoring the check-in is a legitimate answer meaning "still working".
            if let deadline = checkInDeadline, now >= deadline {
                confirmStillOnIt()
            }
        case .onBreak:
            if let nudge = nextBreakNudge, now >= nudge {
                breath.send()
                wave.send()
                nextBreakNudge = now.addingTimeInterval(Self.breakRepeatNudge)
            }
        default:
            break
        }
    }

    private func maintainHeartbeat() {
        guard now.timeIntervalSince(lastHeartbeat) >= Self.heartbeatInterval else { return }
        lastHeartbeat = now
        store.heartbeat()
    }

    /// Returns true if we auto-paused (caller should stop processing this tick).
    private func checkIdle() -> Bool {
        let idle = IdleMonitor.systemIdleSeconds()
        guard idle >= Self.idleThreshold else { return false }
        autoPause(backdatingBy: idle)
        return true
    }

    private func autoPause(backdatingBy idle: TimeInterval) {
        guard let task = store.currentTask else { return }
        let cutoff = Date().addingTimeInterval(-idle)
        store.update(task.id) { Self.closeSession(&$0, at: cutoff) }
        checkInDeadline = nil
        phase = .away
    }

    private func observeSleep() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .running || self.phase == .checkIn else { return }
                self.autoPause(backdatingBy: 0)
            }
        }
    }

    // MARK: - Actions

    func completeFirstRun() {
        UserDefaults.standard.set(true, forKey: "hasCompletedFirstRun")
        phase = .picker
    }

    func startTask(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var task = TaskRecord(name: name)
        task.sessions.append(TaskSession(start: Date()))
        store.add(task)
        beginFocus()
    }

    func resume(_ id: UUID) {
        store.update(id) { t in
            t.status = .active
            t.parkedAt = nil
            t.sessions.append(TaskSession(start: Date()))
        }
        beginFocus()
    }

    private func beginFocus() {
        intervalIndex = 0
        anchor = Date()
        breathFired = false
        checkInDeadline = nil
        phase = .running
    }

    func confirmStillOnIt() {
        intervalIndex = min(intervalIndex + 1, Self.checkInIntervals.count - 1)
        anchor = Date()
        breathFired = false
        checkInDeadline = nil
        phase = .running
    }

    func requestPause() {
        closeCurrentSession(at: Date())
        checkInDeadline = nil
        phase = .pauseMenu
    }

    func backToWork() {
        reopenSession()
        beginFocus()
    }

    func takeBreak() {
        breakStart = Date()
        nextBreakNudge = Date().addingTimeInterval(Self.breakFirstNudge)
        phase = .onBreak
    }

    func endBreak() {
        breakStart = nil
        nextBreakNudge = nil
        reopenSession()
        beginFocus()
    }

    func resumeFromAway() {
        reopenSession()
        beginFocus()
    }

    func beginSwitchTask() { phase = .switchNote }
    func cancelSwitchTask() { phase = .pauseMenu }

    /// `notes` is the task's complete notes blob (the park screen edits it in
    /// full) — it replaces, never appends, so what you saw is what's saved.
    func parkCurrent(notes: String) {
        guard let task = store.currentTask else {
            phase = .picker
            return
        }
        if store.parked.count >= Self.parkedCap {
            pendingParkNote = notes
            phase = .parkingFull
            return
        }
        finishParking(taskID: task.id, notes: notes)
    }

    private func finishParking(taskID: UUID, notes: String) {
        store.update(taskID) { t in
            t.notes = notes
            Self.closeSession(&t, at: Date())
            t.status = .parked
            t.parkedAt = Date()
        }
        pendingParkNote = nil
        phase = .picker
    }

    func completeCurrent() {
        guard let task = store.currentTask else { return }
        store.update(task.id) { t in
            Self.closeSession(&t, at: Date())
            t.status = .completed
            t.completedAt = Date()
        }
        completedSnapshot = store.tasks.first { $0.id == task.id }
        checkInDeadline = nil
        phase = .completion
        let snapshotID = task.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.completionFlourishDuration) { [weak self] in
            guard let self, self.phase == .completion, self.completedSnapshot?.id == snapshotID else { return }
            self.phase = .picker
        }
    }

    /// Live-saves the notes editor as the user types (debounced write).
    func setNotesForCurrent(_ text: String) {
        guard let task = store.currentTask else { return }
        store.updateDebounced(task.id) { $0.notes = text }
    }

    var currentNotes: String { store.currentTask?.notes ?? "" }

    // MARK: - Migration (parked → Todoist / Markdown)

    enum MigrationDestination: String, CaseIterable {
        case todoist, reminders, things, markdown

        var label: String {
            switch self {
            case .todoist: "Todoist"
            case .reminders: "Reminders"
            case .things: "Things"
            case .markdown: "clipboard"
            }
        }

        var isAvailable: Bool {
            self == .things ? Things.isInstalled : true
        }
    }

    func migrate(_ id: UUID, to destination: MigrationDestination) {
        guard let task = store.tasks.first(where: { $0.id == id }) else { return }
        switch destination {
        case .markdown:
            Markdown.copyToPasteboard(task)
            finishMigration(id, to: destination)
        case .things:
            do {
                try Things.addTask(name: task.name, notes: task.notes)
                finishMigration(id, to: destination)
            } catch {
                migrationError = "Things doesn't seem to be installed."
            }
        case .todoist:
            let token = UserDefaults.standard.string(forKey: "todoistToken") ?? ""
            guard !token.isEmpty else {
                migrationError = "Add your Todoist token in Settings first."
                return
            }
            runAsyncMigration(id, to: .todoist) {
                try await Todoist.createTask(name: task.name, notes: task.notes, token: token)
            } onFailure: { error in
                switch error as? Todoist.TodoistError {
                case .unauthorized: "Todoist rejected the token — check it in Settings."
                case .network: "Couldn't reach Todoist — check your connection and try again."
                case .rateLimited: "Todoist asked for a breather — try again in a minute."
                case .badResponse(let code): "Todoist had a problem (error \(code)) — try again."
                case nil: "Sending to Todoist failed — try again."
                }
            }
        case .reminders:
            runAsyncMigration(id, to: .reminders) {
                try await Reminders.createReminder(name: task.name, notes: task.notes)
            } onFailure: { error in
                switch error as? Reminders.RemindersError {
                case .accessDenied:
                    "Fauxcus needs access — System Settings → Privacy & Security → Reminders."
                case .noDefaultList:
                    "Reminders has no default list — pick one in the Reminders app's settings."
                case nil:
                    "Couldn't save to Reminders — try again."
                }
            }
        }
    }

    private func runAsyncMigration(
        _ id: UUID,
        to destination: MigrationDestination,
        _ work: @escaping () async throws -> Void,
        onFailure: @escaping (Error) -> String
    ) {
        migratingIDs.insert(id)
        Task {
            do {
                try await work()
                await MainActor.run { self.finishMigration(id, to: destination) }
            } catch {
                await MainActor.run {
                    self.migratingIDs.remove(id)
                    self.migrationError = onFailure(error)
                }
            }
        }
    }

    private func finishMigration(_ id: UUID, to destination: MigrationDestination) {
        migratingIDs.remove(id)
        migrationError = nil
        store.update(id) { t in
            t.status = .migrated
            t.exportedTo = destination.rawValue
        }
        // If we were blocked on a full parking lot, the freed slot completes the park.
        if phase == .parkingFull, let note = pendingParkNote, let current = store.currentTask {
            finishParking(taskID: current.id, notes: note)
        }
    }

    /// Permanently removes a parked task (it doesn't go to history).
    func deleteParked(_ id: UUID) {
        store.delete(id)
        migrationError = nil
        if phase == .parkingFull, let note = pendingParkNote, let current = store.currentTask {
            finishParking(taskID: current.id, notes: note)
        }
    }

    func cancelParkingFull() {
        pendingParkNote = nil
        phase = .pauseMenu
    }

    // MARK: - App lifecycle

    func appWillTerminate() {
        guard let task = store.currentTask else { return }
        store.update(task.id) { t in
            Self.closeSession(&t, at: Date())
            t.status = .parked
            t.parkedAt = Date()
        }
    }

    // MARK: - Session helpers

    private static func closeSession(_ t: inout TaskRecord, at date: Date) {
        if let i = t.sessions.indices.last, t.sessions[i].end == nil {
            t.sessions[i].end = max(t.sessions[i].start, date)
        }
    }

    private func closeCurrentSession(at date: Date) {
        guard let task = store.currentTask else { return }
        store.update(task.id) { Self.closeSession(&$0, at: date) }
    }

    private func reopenSession() {
        guard let task = store.currentTask else { return }
        store.update(task.id) { $0.sessions.append(TaskSession(start: Date())) }
    }

    // MARK: - View conveniences

    var currentTaskName: String { store.currentTask?.name ?? "" }

    var elapsedString: String {
        Format.clock(store.currentTask?.focusedSeconds(asOf: now) ?? 0)
    }

    var breakElapsedString: String {
        Format.clock(breakStart.map { now.timeIntervalSince($0) } ?? 0)
    }
}
