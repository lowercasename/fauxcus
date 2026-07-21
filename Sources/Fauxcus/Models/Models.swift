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

struct TaskRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var sessions: [TaskSession] = []
    var notes: String = ""
    var status: TaskStatus = .active
    var parkedAt: Date?
    var completedAt: Date?
    var exportedTo: String?

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
}
