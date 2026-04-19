import Foundation
import SwiftUI
import AVFoundation
import ScreenCaptureKit
import CoreGraphics

@MainActor
final class PermissionsManager: ObservableObject {

    @Published var screenRecordingGranted: Bool = false
    @Published var microphoneGranted: Bool = false

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    init() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // Use synchronous preflight only — never call SCShareableContent at launch.
        // SCShareableContent triggers a TCC banner for every new binary (every rebuild),
        // which causes users to accidentally deny and permanently break the app.
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    // MARK: - Refresh (call only when returning from System Settings)

    func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Microphone

    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Computed

    var allRequiredGranted: Bool { screenRecordingGranted }
}
