import SwiftUI

// MARK: - Picker

struct PickerView: View {
    @EnvironmentObject var engine: FocusEngine
    @EnvironmentObject var store: Store
    @State private var text = ""
    @State private var focusTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PrismIcon()
                PlainTextField(
                    text: $text,
                    placeholder: "What are you working on?",
                    focusTrigger: focusTrigger
                ) { start() }
            }
            if let suggested = store.suggestion(for: text) {
                Button {
                    text = suggested
                } label: {
                    Label(suggested, systemImage: "arrow.turn.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Use this task name")
            }
            MigrationErrorBanner()
            if !store.parked.isEmpty {
                Divider()
                Text("PARKED")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
                ForEach(store.parked) { task in
                    ParkedRow(task: task)
                }
            }
        }
        .padding(14)
        .onAppear { focusTrigger += 1 }
        .onChange(of: engine.focusTaskRequest) { focusTrigger += 1 }
    }

    private func start() {
        engine.startTask(named: text)
        text = ""
    }
}

struct ParkedRow: View {
    @EnvironmentObject var engine: FocusEngine
    let task: TaskRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                engine.resume(task.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let tail = task.noteTail {
                        Text(tail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Resume this task")
            Menu {
                MigrationDestinationItems(taskID: task.id)
            } label: {
                if engine.migratingIDs.contains(task.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// The app's prism mark, Things-style, prefixing the task field.
struct PrismIcon: View {
    static let image: NSImage? = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for name in ["PrismIcon", "PrismIcon@2x"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let rep = NSImageRep(contentsOf: url) {
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
            }
        }
        guard !image.representations.isEmpty else {
            appLog.warning("PrismIcon PNGs missing from bundle")
            return nil
        }
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .frame(width: 18, height: 18)
        }
    }
}

/// Inline, non-modal migration error: styled like a system warning (triangle,
/// dismissible) but never an NSAlert — alerts steal focus, and the panel's
/// whole contract is that it doesn't.
struct MigrationErrorBanner: View {
    @EnvironmentObject var engine: FocusEngine

    var body: some View {
        if let error = engine.migrationError {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    engine.migrationError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Dismiss")
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.yellow.opacity(0.12))
            )
        }
    }
}

/// One menu-item per migration destination — migrating removes the park.
struct MigrationDestinationItems: View {
    @EnvironmentObject var engine: FocusEngine
    let taskID: UUID

    var body: some View {
        ForEach(MigrationDestination.allCases.filter(\.isAvailable), id: \.self) { destination in
            Button(destination == .markdown ? "Copy to clipboard & clear" : "Migrate to \(destination.label)") {
                engine.migrate(taskID, to: destination)
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            confirmDelete()
        }
    }

    private func confirmDelete() {
        guard let task = engine.store.tasks.first(where: { $0.id == taskID }) else { return }
        if DeleteConfirmation.confirm(task) {
            engine.deleteParked(task.id)
        }
    }
}

/// HIG-style destructive confirmation: names the task, states the
/// consequence, red Delete, and Cancel keeps the Return key.
@MainActor
enum DeleteConfirmation {
    static func confirm(_ task: TaskRecord) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete “\(task.name)”?"
        alert.informativeText = task.notes.isEmpty
            ? "This can't be undone."
            : "Its notes will be deleted too. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}

// MARK: - Running

struct RunningView: View {
    @EnvironmentObject var engine: FocusEngine
    @State private var showNotes = false
    @State private var notesText = ""
    @FocusState private var notesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(engine.currentTaskName)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .modifier(Breathing())
            HStack(spacing: 10) {
                Text(engine.elapsedString)
                    .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .onTapGesture { engine.wave.send() }
                    .help("Click to preview the alert wave")
                Spacer()
                IconButton("checkmark.circle.fill", help: "Done") { engine.completeCurrent() }
                IconButton("pause.circle.fill", help: "Pause") { engine.requestPause() }
                IconButton("square.and.pencil", help: "Notes") { toggleNotes() }
            }
            if showNotes {
                TaskNotesEditor(text: $notesText, focused: $notesFocused)
                    .onChange(of: notesText) { engine.setNotesForCurrent(notesText) }
            }
        }
        .padding(14)
        .onChange(of: engine.focusNoteRequest) { openNotes() }
    }

    private func toggleNotes() {
        showNotes ? (showNotes = false) : openNotes()
    }

    private func openNotes() {
        notesText = engine.currentNotes
        showNotes = true
        notesFocused = true
    }
}

/// The shared notes editor: the task's full notes blob, older notes always
/// visible. Both call sites live-save on change — edits survive Back, quit,
/// and crashes alike.
struct TaskNotesEditor: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var placeholder = "Notes for this task…"

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 88)
                .focused(focused)
            if text.isEmpty {
                // Match NSTextView's 5pt line-fragment padding so the ghost
                // text sits exactly where the caret and typed text land.
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .onAppear {
            if focused.wrappedValue { Self.moveCursorToEnd() }
        }
        .onChange(of: focused.wrappedValue) {
            if focused.wrappedValue { Self.moveCursorToEnd() }
        }
    }

    /// TextEditor doesn't expose the insertion point, but it's backed by an
    /// NSTextView — once focus lands, jump it past the existing notes.
    private static func moveCursorToEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let textView = NSApp.windows
                .filter({ $0 is FloatingPanel })
                .compactMap({ $0.firstResponder as? NSTextView })
                .first(where: { $0.isEditable })
            else { return }
            let end = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.setSelectedRange(end)
            textView.scrollRangeToVisible(end)
        }
    }
}

// MARK: - Check-in

struct CheckInView: View {
    @EnvironmentObject var engine: FocusEngine

    var body: some View {
        VStack(spacing: 12) {
            (Text("Still on ").foregroundStyle(.secondary)
                + Text(engine.currentTaskName).fontWeight(.semibold)
                + Text("?").foregroundStyle(.secondary))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .modifier(Breathing())
            HStack(spacing: 8) {
                Button {
                    engine.confirmStillOnIt()
                } label: {
                    Text("Yes").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    engine.requestPause()
                } label: {
                    Text("Pause").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(14)
        .onAppear { engine.breath.send() }
    }
}

// MARK: - Pause menu

struct PauseMenuView: View {
    @EnvironmentObject var engine: FocusEngine

    var body: some View {
        VStack(spacing: 8) {
            Text(engine.currentTaskName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Button {
                engine.takeBreak()
            } label: {
                Label("Take a break", systemImage: "cup.and.saucer").frame(maxWidth: .infinity)
            }
            Button {
                engine.beginSwitchTask()
            } label: {
                Label("Park this task", systemImage: "parkingsign").frame(maxWidth: .infinity)
            }
            Button {
                engine.backToWork()
            } label: {
                Label("Back to task", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(14)
    }
}

// MARK: - Switch task (breadcrumb note)

struct SwitchNoteView: View {
    @EnvironmentObject var engine: FocusEngine
    @State private var notes = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(engine.currentTaskName)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text("Leave a breadcrumb")
                .font(.system(size: 14, weight: .semibold))
            Text("Next steps, resources, or reminders for future you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TaskNotesEditor(text: $notes, focused: $focused, placeholder: "Where did you leave off?")
                .onChange(of: notes) { engine.setNotesForCurrent(notes) }
            HStack {
                Button("Back") { engine.cancelSwitchTask() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Park it") { engine.parkCurrent(notes: notes) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .onAppear {
            notes = engine.currentNotes
            focused = true
        }
    }
}

// MARK: - Break

struct BreakView: View {
    @EnvironmentObject var engine: FocusEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(engine.currentTaskName)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text("On a break")
                    .font(.system(size: 14, weight: .semibold))
                    .modifier(Breathing())
                Spacer()
                Text(engine.breakElapsedString)
                    .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Button {
                engine.endBreak()
            } label: {
                Text("Back to it").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(14)
    }
}

// MARK: - Welcome back (auto-paused while away)

struct WelcomeBackView: View {
    @EnvironmentObject var engine: FocusEngine

    var body: some View {
        VStack(spacing: 8) {
            Text(engine.currentTaskName)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("Paused while you were away")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                engine.resumeFromAway()
            } label: {
                Text("Resume").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            HStack(spacing: 16) {
                Button("Done") { engine.completeCurrent() }
                Button("Park this task") { engine.beginSwitchTask() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

// MARK: - Completion flourish

struct CompletionView: View {
    @EnvironmentObject var engine: FocusEngine
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
                .scaleEffect(appeared ? 1 : 0.2)
                .animation(.spring(response: 0.4, dampingFraction: 0.55), value: appeared)
            Text(engine.completedSnapshot?.name ?? "")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(Format.duration(engine.completedSnapshot?.focusedSeconds() ?? 0))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }
}

// MARK: - Parking full (migration)

struct ParkingFullView: View {
    @EnvironmentObject var engine: FocusEngine
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parking's full")
                .font(.system(size: 14, weight: .semibold))
            Text("Migrate one to make room.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            MigrationErrorBanner()
            ForEach(store.parkedOldestFirst) { task in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if let tail = task.noteTail {
                            Text(tail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if engine.migratingIDs.contains(task.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Menu("Migrate") {
                            MigrationDestinationItems(taskID: task.id)
                        }
                        .fixedSize()
                        .controlSize(.small)
                    }
                }
            }
            Button("Never mind") { engine.cancelParkingFull() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}
