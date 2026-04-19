import Foundation
import ScreenCaptureKit

/// Represents a capture target: either a full display or a specific application window.
struct CaptureSource: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var kind: Kind
    var displayID: CGDirectDisplayID?

    // Stored as weak-ish opaque wrappers – recreated each enumeration
    var scDisplay: SCDisplay?
    var scWindow: SCWindow?

    enum Kind: Equatable, Hashable {
        case display
        case window(appName: String)
    }

    // SCDisplay / SCWindow are reference types; use id for Equatable / Hashable
    static func == (lhs: CaptureSource, rhs: CaptureSource) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Factory helpers

    static func from(display: SCDisplay) -> CaptureSource {
        CaptureSource(
            id: "display-\(display.displayID)",
            name: "Display \(display.displayID)",
            kind: .display,
            displayID: display.displayID,
            scDisplay: display,
            scWindow: nil
        )
    }

    static func from(window: SCWindow) -> CaptureSource {
        let appName = window.owningApplication?.applicationName ?? "Unknown App"
        let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? appName
        return CaptureSource(
            id: "window-\(window.windowID)",
            name: title,
            kind: .window(appName: appName),
            displayID: nil,
            scDisplay: nil,
            scWindow: window
        )
    }

    /// Human-readable type label.
    var typeLabel: String {
        switch kind {
        case .display: return "Display"
        case .window(let app): return app
        }
    }

    var systemImageName: String {
        switch kind {
        case .display: return "display"
        case .window: return "macwindow"
        }
    }

    /// Actual pixel aspect ratio of the source. Used by the preview to avoid black bars.
    var aspectRatio: CGFloat {
        if let d = scDisplay, d.height > 0 {
            return CGFloat(d.width) / CGFloat(d.height)
        }
        if let w = scWindow, w.frame.height > 0 {
            return w.frame.width / w.frame.height
        }
        return 16.0 / 9.0
    }
}
