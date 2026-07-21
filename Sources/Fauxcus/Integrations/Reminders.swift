import EventKit

enum Reminders {
    enum RemindersError: Error {
        case accessDenied
        case noDefaultList
    }

    private static let store = EKEventStore()

    static func createReminder(name: String, notes: String) async throws {
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw RemindersError.accessDenied }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw RemindersError.noDefaultList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = name
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
    }
}
