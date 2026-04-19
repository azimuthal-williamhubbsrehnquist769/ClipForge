import SwiftUI

/// Content view for the MenuBarExtra popover.
struct MenuBarView: View {

    @EnvironmentObject var captureVM: CaptureViewModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(captureVM.isCapturing ? Color.red.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 28, height: 28)
                    Image(systemName: captureVM.isCapturing ? "record.circle.fill" : "record.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(captureVM.isCapturing ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: captureVM.isCapturing)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(captureVM.isCapturing ? "Recording" : "Ready")
                        .font(.subheadline.weight(.semibold))
                    if captureVM.isCapturing {
                        Text("\(Int(captureVM.bufferDuration))s buffered")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else if let src = captureVM.selectedSource {
                        Text(src.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Quick actions
            menuItem(
                icon: captureVM.isCapturing ? "stop.circle" : "record.circle",
                label: captureVM.isCapturing ? "Stop Recording" : "Start Recording",
                tint: captureVM.isCapturing ? .red : .primary
            ) {
                captureVM.toggleCapture()
            }

            menuItem(
                icon: "scissors",
                label: captureVM.isSavingClip ? "Exporting…" : "Save Replay Clip",
                shortcut: captureVM.settings.saveClipHotkey.displayString
            ) {
                captureVM.saveReplayClip()
            }
            .disabled(!captureVM.isCapturing || captureVM.isSavingClip || captureVM.pendingClip != nil)

            // Pending clip actions (shown while banner is active)
            if captureVM.pendingClip != nil {
                Divider()
                menuItem(icon: "square.and.arrow.down", label: "Save to Library") {
                    captureVM.savePendingClipToLibrary()
                }
                menuItem(icon: "trash", label: "Discard Clip", tint: .red) {
                    captureVM.discardPendingClip()
                }
            }

            if captureVM.settings.capturesMicrophone {
                menuItem(
                    icon: captureVM.isMicMuted ? "mic.slash" : "mic",
                    label: captureVM.isMicMuted ? "Unmute Mic" : "Mute Mic"
                ) {
                    captureVM.toggleMic()
                }
            }

            Divider()

            menuItem(icon: "photo.stack", label: "Open Library") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            menuItem(icon: "gearshape", label: "Settings…") {
                openSettings()
            }

            Divider()

            menuItem(icon: "xmark.circle", label: "Quit ClipForge") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 240)
    }

    private func menuItem(
        icon: String,
        label: String,
        shortcut: String? = nil,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(
            Color.accentColor.opacity(0.0001) // allows hover highlighting
        )
    }
}

#Preview {
    MenuBarView()
        .environmentObject(
            CaptureViewModel(
                settings: .shared,
                permissions: PermissionsManager(),
                libraryManager: LibraryManager(settings: .shared)
            )
        )
}
