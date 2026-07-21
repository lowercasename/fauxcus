import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if store.history.isEmpty {
                Text("Nothing here yet — finished and migrated tasks land in this list.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.history) { task in
                    HistoryRow(task: task)
                        .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 440, minHeight: 320)
    }
}

private struct HistoryRow: View {
    @EnvironmentObject var store: Store
    let task: TaskRecord
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.name)
                    .fontWeight(.medium)
                Spacer()
                Text(Format.dateTime(task.lastActivity))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Label(Format.duration(task.focusedSeconds()), systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if task.status == .migrated {
                    let destination = task.exportedTo.flatMap(FocusEngine.MigrationDestination.init(rawValue:))
                    Label(
                        destination == .markdown ? "Copied to clipboard"
                            : "Migrated to \(destination?.label ?? "elsewhere")",
                        systemImage: "arrow.up.right.square"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(copied ? "Copied" : "Copy to clipboard") {
                    Markdown.copyToPasteboard(task)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button("Delete", role: .destructive) {
                    if DeleteConfirmation.confirm(task) {
                        store.delete(task.id)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
            }
            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
    }
}
