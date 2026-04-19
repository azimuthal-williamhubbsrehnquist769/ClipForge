import SwiftUI

struct PermissionsOnboardingView: View {

    @EnvironmentObject var permissions: PermissionsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Quit button top-right
            HStack {
                Spacer()
                Button(action: quitApp) {
                    Label("Quit", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
                .padding([.top, .trailing], 16)
            }

            // Header
            VStack(spacing: 12) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.red)

                Text("Welcome to ClipForge")
                    .font(.largeTitle.weight(.bold))

                Text("ClipForge needs two permissions to clip your gameplay.\nYour data stays local: no accounts, no cloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 40)

            Divider()
                .padding(.vertical, 24)

            // Permission rows
            VStack(spacing: 16) {
                PermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    iconColor: .red,
                    title: "Screen Recording",
                    description: "Required to capture your display or app window.",
                    state: rowState(granted: permissions.screenRecordingGranted),
                    onGrant: {
                        permissions.requestScreenRecording()
                        // Re-check when the user returns from System Settings
                    }
                )

                PermissionRow(
                    icon: "mic.fill",
                    iconColor: .blue,
                    title: "Microphone",
                    description: "Optional: record your voice alongside gameplay.",
                    state: rowState(granted: permissions.microphoneGranted),
                    onGrant: {
                        Task {
                            _ = await permissions.requestMicrophone()
                            permissions.refresh()
                        }
                    }
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            // Continue button
            VStack(spacing: 8) {
                Button(action: complete) {
                    Text("Continue to ClipForge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !permissions.screenRecordingGranted {
                    Text("Open System Settings → Privacy & Security → Screen Recording, then return here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 480, height: 500)
        .onChange(of: permissions.screenRecordingGranted) { _, granted in
            if granted { complete() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check using preflight (no TCC trigger) when returning from System Settings
            permissions.refresh()
        }
    }

    private func quitApp() {
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    private func rowState(granted: Bool) -> PermissionRow.State {
        return granted ? .granted : .notGranted
    }

    private func complete() {
        permissions.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Permission row

struct PermissionRow: View {

    enum State { case checking, granted, notGranted }

    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let state: State
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            switch state {
            case .checking:
                ProgressView().controlSize(.small)
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            case .notGranted:
                Button("Allow", action: onGrant)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .animation(.default, value: state == .granted)
    }
}

#Preview {
    PermissionsOnboardingView()
        .environmentObject(PermissionsManager())
}
