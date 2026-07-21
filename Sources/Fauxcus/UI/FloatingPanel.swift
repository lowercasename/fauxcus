import AppKit
import SwiftUI

/// Borderless, non-activating panel: floats above everything, never steals
/// focus from the frontmost app except when the user deliberately types.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject {
    let panel: FloatingPanel
    private static let originKey = "panelOrigin"
    private static let defaultWidth: CGFloat = 300
    private var selfAdjusting = false
    private var desiredOrigin: NSPoint?

    init(engine: FocusEngine, store: Store) {
        let root = PanelRootView()
            .environmentObject(engine)
            .environmentObject(store)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        super.init()
        positionInitially()
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification, object: panel
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidResize),
            name: NSWindow.didResizeNotification, object: panel
        )
    }

    private func positionInitially() {
        // The hosting view may not have laid out yet, so the panel's own frame
        // width can be 0 here — never derive the position from it.
        let width = max(panel.frame.width, Self.defaultWidth)
        var origin: NSPoint
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            origin = NSPointFromString(saved)
        } else if let visible = NSScreen.main?.visibleFrame {
            origin = NSPoint(x: visible.maxX - width - 24, y: visible.minY + 24)
        } else {
            origin = .zero
        }
        origin = clampedToVisible(NSRect(
            origin: origin,
            size: NSSize(width: width, height: max(panel.frame.height, 150))
        ))
        moveTo(origin)
    }

    /// Keep the whole panel inside some screen's visible area.
    private func clampedToVisible(_ rect: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(rect) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return rect.origin }
        return NSPoint(
            x: min(max(rect.origin.x, visible.minX), visible.maxX - rect.width),
            y: min(max(rect.origin.y, visible.minY), visible.maxY - rect.height)
        )
    }

    private func moveTo(_ origin: NSPoint) {
        selfAdjusting = true
        panel.setFrameOrigin(origin)
        selfAdjusting = false
        desiredOrigin = origin
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
    }

    @objc private func panelDidMove() {
        guard !selfAdjusting else { return }
        desiredOrigin = panel.frame.origin
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
    }

    /// AppKit anchors the top-left when the content resizes; re-pin the saved
    /// bottom-left so the panel grows upward from its corner instead.
    @objc private func panelDidResize() {
        guard !selfAdjusting, let desired = desiredOrigin else { return }
        selfAdjusting = true
        panel.setFrameOrigin(clampedToVisible(NSRect(origin: desired, size: panel.frame.size)))
        selfAdjusting = false
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func summon() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }
}
