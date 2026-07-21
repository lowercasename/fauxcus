import Foundation

struct TaskSession: Codable, Equatable {
    var start: Date
    var end: Date?

    func seconds(asOf now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

enum TaskStatus: String, Codable {
    case active, parked, completed, migrated
}

enum MigrationDestination: String, Codable, CaseIterable {
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

struct TaskRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var sessions: [TaskSession] = []
    var notes: String = ""
    var status: TaskStatus = .active
    var parkedAt: Date?
    var completedAt: Date?
    var exportedTo: MigrationDestination?

    func focusedSeconds(asOf now: Date = Date()) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.seconds(asOf: now) }
    }

    var lastActivity: Date {
        completedAt ?? parkedAt ?? sessions.last?.end ?? sessions.last?.start ?? createdAt
    }

    var noteTail: String? {
        notes.split(separator: "\n")
            .map(String.init)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Transitions
    // The compound "close open session + set status + stamp date" lives here so
    // every mutation site shares one definition of each transition.

    mutating func closeOpenSession(at date: Date) {
        if let i = sessions.indices.last, sessions[i].end == nil {
            sessions[i].end = max(sessions[i].start, date)
        }
    }

    mutating func park(at date: Date = Date()) {
        closeOpenSession(at: date)
        status = .parked
        parkedAt = date
    }

    mutating func complete(at date: Date = Date()) {
        closeOpenSession(at: date)
        status = .completed
        completedAt = date
    }

    mutating func beginSession(at date: Date = Date()) {
        status = .active
        parkedAt = nil
        sessions.append(TaskSession(start: date))
    }

    mutating func markMigrated(to destination: MigrationDestination) {
        status = .migrated
        exportedTo = destination
    }
}
