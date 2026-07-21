import CoreGraphics
import Foundation

enum IdleMonitor {
    /// Seconds since the user last touched any input device.
    static func systemIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .keyDown, .scrollWheel,
        ]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
