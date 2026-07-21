import AppKit

enum Markdown {
    static func render(_ task: TaskRecord) -> String {
        var lines = ["## \(task.name)", ""]
        lines.append("- Started: \(Format.dateTime(task.createdAt))")
        lines.append("- Focused: \(Format.duration(task.focusedSeconds()))")
        lines.append("- Status: \(task.status.rawValue)")
        if !task.notes.isEmpty {
            lines.append("")
            lines.append("### Notes")
            lines.append("")
            lines.append(task.notes)
        }
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(_ task: TaskRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(render(task), forType: .string) {
            appLog.warning("pasteboard write failed for task \(task.name, privacy: .public)")
        }
    }
}
