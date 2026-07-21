import Foundation

@MainActor
final class Store: ObservableObject {
    private struct Payload: Codable {
        var tasks: [TaskRecord]
        var heartbeat: Date?
    }

    @Published private(set) var tasks: [TaskRecord] = []
    private var heartbeatDate: Date?

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fauxcus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    static func load() -> Store {
        let store = Store()
        if let data = try? Data(contentsOf: fileURL),
           let payload = try? decoder.decode(Payload.self, from: data) {
            store.tasks = payload.tasks
            store.healOpenSessions(asOf: payload.heartbeat)
        }
        return store
    }

    /// If the app died mid-task, close the dangling session at the last known
    /// heartbeat and park the task — the work is never lost, never inflated.
    private func healOpenSessions(asOf heartbeat: Date?) {
        var changed = false
        for i in tasks.indices where tasks[i].status == .active {
            if let last = tasks[i].sessions.indices.last, tasks[i].sessions[last].end == nil {
                tasks[i].sessions[last].end = max(tasks[i].sessions[last].start, heartbeat ?? tasks[i].sessions[last].start)
            }
            tasks[i].status = .parked
            tasks[i].parkedAt = heartbeat ?? Date()
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
        tasks.append(task)
        save()
    }

    func update(_ id: UUID, _ mutate: (inout TaskRecord) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[i])
        save()
    }

    /// For high-frequency edits (typing notes): mutate immediately, write to
    /// disk debounced so we don't hit the filesystem on every keystroke.
    func updateDebounced(_ id: UUID, _ mutate: (inout TaskRecord) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[i])
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private var saveWorkItem: DispatchWorkItem?

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
        } catch {
            NSLog("Fauxcus: failed to save store: \(error)")
        }
    }
}
