import Foundation

/// A clip that has been exported to a temp file and copied to the clipboard,
/// but not yet committed to the library. The user must choose to save or discard.
struct PendingClip {
    let url: URL
    let title: String
    let duration: TimeInterval
    let appName: String?

    var formattedDuration: String {
        let t = Int(duration)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
