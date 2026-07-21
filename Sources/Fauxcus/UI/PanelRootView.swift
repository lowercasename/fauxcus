import SwiftUI

struct PanelRootView: View {
    @EnvironmentObject var engine: FocusEngine

    var body: some View {
        content
            .frame(width: 300)
            .background(PanelBackground())
            .modifier(SheenWave())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.phase)
    }

    @ViewBuilder private var content: some View {
        switch engine.phase {
        case .firstRun: FirstRunView()
        case .picker: PickerView()
        case .running: RunningView()
        case .checkIn: CheckInView()
        case .pauseMenu: PauseMenuView()
        case .switchNote: SwitchNoteView()
        case .onBreak: BreakView()
        case .away: WelcomeBackView()
        case .completion: CompletionView()
        case .parkingFull: ParkingFullView()
        }
    }
}

struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The obvious-but-silent alert: a diagonal band of accent-tinted light that
/// sweeps across the whole panel surface, twice. Peripheral vision catches
/// travelling motion, but nothing changes position — a glint, not a shake.
struct SheenWave: ViewModifier {
    @EnvironmentObject var engine: FocusEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let bandWidth = geo.size.width * 0.55
                    // Accent-only band with a soft crest: on a vibrancy
                    // material, a glint reads as the tint intensifying — a
                    // bright white stripe reads as plastic glare.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.accentColor.opacity(0.14), location: 0.3),
                            .init(color: Color.accentColor.opacity(0.28), location: 0.5),
                            .init(color: Color.accentColor.opacity(0.14), location: 0.7),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth, height: geo.size.height * 2)
                    .rotationEffect(.degrees(16))
                    .offset(
                        x: progress * (geo.size.width + bandWidth) - bandWidth,
                        y: -geo.size.height / 2
                    )
                }
                .allowsHitTesting(false)
            )
            .onReceive(engine.wave) { run() }
    }

    private func run() {
        guard !reduceMotion else { return }
        sweep()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { sweep() }
    }

    private func sweep() {
        progress = -0.2
        withAnimation(.easeInOut(duration: 2.2)) { progress = 1.2 }
    }
}

/// The 2-second silent "breath": a gentle brighten-and-settle that draws the
/// eye back to whatever it wraps (usually the task name).
struct Breathing: ViewModifier {
    @EnvironmentObject var engine: FocusEngine
    @State private var breathing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(breathing ? 1.04 : 1)
            .brightness(breathing ? 0.07 : 0)
            .onReceive(engine.breath) {
                withAnimation(.easeInOut(duration: 1.0)) { breathing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 1.0)) { breathing = false }
                }
            }
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    init(_ systemName: String, help: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}
