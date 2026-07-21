import Foundation

@MainActor
final class Store: ObservableObject {
    private struct Payload: Codable {
        var tasks: [TaskRecord]
        var heartbeat: Date?
    }

    @Published private(set) var tasks: [TaskRecord] = []
    /// Set when store.json existed but couldn't be read (a backup was made).
    @Published var loadWarning: String?
    /// Set while disk writes are failing; cleared by the next successful save.
    @Published private(set) var saveError: String?
    private var heartbeatDate: Date?
    private var saveWorkItem: DispatchWorkItem?

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fauxcus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    static func load() -> Store {
        let store = Store()
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return store }
        do {
            let data = try Data(contentsOf: url)
            let payload = try decoder.decode(Payload.self, from: data)
            store.tasks = payload.tasks
            store.heartbeatDate = payload.heartbeat
            store.healOpenSessions(asOf: payload.heartbeat)
        } catch {
            // Never overwrite a store we couldn't read: move it aside first, so
            // the heartbeat/save cycle can't destroy recoverable data.
            appLog.error("store.json unreadable: \(String(describing: error), privacy: .public)")
            let backup = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
                .appendingPathExtension("json")
            do {
                try FileManager.default.moveItem(at: url, to: backup)
                store.loadWarning = "Task history couldn't be read — the old file was kept as \(backup.lastPathComponent)."
            } catch {
                appLog.error("couldn't back up unreadable store: \(String(describing: error), privacy: .public)")
                store.loadWarning = "Task history couldn't be read."
            }
        }
        return store
    }

    /// If the app died mid-task, close the dangling session at the last known
    /// heartbeat and park the task — the work is never lost, never inflated.
    /// Note: this (and appWillTerminate) parks past the 5-task cap on purpose;
    /// the cap is a UI-flow policy enforced only at explicit park time.
    private func healOpenSessions(asOf heartbeat: Date?) {
        var changed = false
        for i in tasks.indices where tasks[i].status == .active {
            let cutoff = heartbeat ?? tasks[i].sessions.last?.start ?? Date()
            tasks[i].park(at: cutoff)
            changed = true
        }
        if changed { save() }
    }

    var currentTask: TaskRecord? { tasks.first { $0.status == .active } }

    var parked: [TaskRecord] {
        tasks.filter { $0.status == .parked }
            .sorted { ($0.parkedAt ?? .distantPast) > ($1.parkedAt ?? .distantPast) }
    }

    var parkedOldestFirst: [TaskRecord] { parked.reversed() }

    var history: [TaskRecord] {
        tasks.filter { $0.status == .completed || $0.status == .migrated }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    func suggestion(for input: String) -> String? {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return nil }
        var seen = Set<String>()
        for task in tasks.sorted(by: { $0.lastActivity > $1.lastActivity }) {
            let key = task.name.lowercased()
            guard seen.insert(key).inserted else { continue }
            if key.hasPrefix(query) && key != query { return task.name }
        }
        return nil
    }

    func add(_ task: TaskRecord) {
        assert(task.status != .active || currentTask == nil, "second active task")
        tasks.append(task)
        save()
    }

    @discardableResult
    func update(_ id: UUID, _ mutate: (inout TaskRecord) -> Void) -> Bool {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else {
            appLog.error("update for unknown task id \(id, privacy: .public)")
            return false
        }
        mutate(&tasks[i])
        save()
        return true
    }

    /// For high-frequency edits (typing notes): mutate immediately, write to
    /// disk debounced so we don't hit the filesystem on every keystroke.
    @discardableResult
    func updateDebounced(_ id: UUID, _ mutate: (inout TaskRecord) -> Void) -> Bool {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return false }
        mutate(&tasks[i])
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        return true
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func heartbeat() {
        heartbeatDate = Date()
        save()
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    func save() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let data = try Store.encoder.encode(Payload(tasks: tasks, heartbeat: heartbeatDate))
            try data.write(to: Store.fileURL, options: .atomic)
            if saveError != nil { saveError = nil }
        } catch {
            appLog.error("failed to save store: \(String(describing: error), privacy: .public)")
            saveError = "Couldn't save your tasks — check disk space. Recent changes may be lost."
        }
    }
}
