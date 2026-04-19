import SwiftUI

@main
struct ClipForgeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Shared managers (all owned at app scope, injected via environment)
    private let settings      = SettingsStore.shared
    private let permissions   = PermissionsManager()
    private let libraryManager: LibraryManager
    private let captureVM: CaptureViewModel
    private let libraryVM: LibraryViewModel

    init() {
        let lib = LibraryManager(settings: SettingsStore.shared)
        libraryManager = lib
        captureVM = CaptureViewModel(
            settings: SettingsStore.shared,
            permissions: permissions,
            libraryManager: lib
        )
        libraryVM = LibraryViewModel(libraryManager: lib)

        // Kick off library load
        Task { await lib.load() }
    }

    // MARK: - Scenes

    var body: some Scene {
        // Main window
        Window("ClipForge", id: "main") {
            ContentView()
                .environmentObject(captureVM)
                .environmentObject(libraryVM)
                .environmentObject(permissions)
                .environmentObject(settings)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 620)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { }
                    .disabled(true)
            }
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar extra (macOS 13+)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(captureVM)
                .environmentObject(settings)
        } label: {
            // Animated recording indicator in menu bar
            MenuBarLabel(isRecording: captureVM.isCapturing)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

// MARK: - Menu bar icon

/// A compact label that pulses red while recording.
struct MenuBarLabel: View {
    let isRecording: Bool

    var body: some View {
        Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
            .symbolRenderingMode(isRecording ? .multicolor : .monochrome)
            .symbolEffect(.variableColor.iterative, isActive: isRecording)
    }
}
