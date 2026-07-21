import SwiftUI

struct SettingsView: View {
    @AppStorage("todoistToken") private var todoistToken = ""
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            LabeledContent("Summon hotkey") {
                HotkeyRecorderView()
            }
            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    LoginItem.setEnabled(launchAtLogin)
                }
            SecureField("Todoist API token", text: $todoistToken)
            Text("Find it in Todoist → Settings → Integrations → Developer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct HotkeyRecorderView: View {
    @State private var recording = false
    @State private var display = Hotkey.description
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : display) {
            recording ? stopRecording() : startRecording()
        }
        .buttonStyle(.bordered)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = Hotkey.carbonModifiers(from: event.modifierFlags)
            if event.keyCode == 53 && mods == 0 { // Escape cancels
                stopRecording()
                return nil
            }
            guard mods != 0 else { return nil } // require at least one modifier
            Hotkey.save(keyCode: UInt32(event.keyCode), modifiers: mods)
            display = Hotkey.description
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
