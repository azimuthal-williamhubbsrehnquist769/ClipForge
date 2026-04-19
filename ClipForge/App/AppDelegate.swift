import AppKit
import Foundation

/// Handles application lifecycle events that aren't expressible in SwiftUI App.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        // Ensure the library directory exists
        createLibraryDirectoryIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running as a menu-bar app even if the main window is closed.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the Dock icon re-opens the main window.
        if !flag {
            NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Private

    private func isAnotherInstanceRunning() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        return running.count > 1
    }

    private func createLibraryDirectoryIfNeeded() {
        let path = SettingsStore.shared.libraryPath
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }
}
