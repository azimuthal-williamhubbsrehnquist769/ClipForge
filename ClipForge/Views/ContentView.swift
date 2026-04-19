import SwiftUI

/// Root view: two-column sidebar layout - Library on left, detail/capture on right.
struct ContentView: View {

    @EnvironmentObject var captureVM: CaptureViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var permissions: PermissionsManager
    @EnvironmentObject var settings: SettingsStore

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if !permissions.hasCompletedOnboarding {
                PermissionsOnboardingView()
            } else {
                mainContent
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibraryView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            if let clip = libraryVM.selectedClip {
                ClipDetailView(clip: clip)
            } else {
                capturePanel
            }
        }
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { saveBanner }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            captureVM.handleAppBecameActive()
        }
    }

    // MARK: - Save banner overlay

    @ViewBuilder
    private var saveBanner: some View {
        if let pending = captureVM.pendingClip {
            ClipSaveBanner(
                clip: pending,
                onSaveToLibrary: { captureVM.savePendingClipToLibrary() },
                onDiscard: { captureVM.discardPendingClip() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(10)
        }
    }

    // MARK: - Capture panel (shown when no clip is selected)

    private var capturePanel: some View {
        VStack(spacing: 24) {
            Spacer()

            // Live preview (shown while capturing)
            if captureVM.isCapturing {
                ZStack(alignment: .topLeading) {
                    CapturePreviewView(displayLayer: captureVM.previewLayer)
                        .aspectRatio(captureVM.selectedSource?.aspectRatio ?? (16.0/9.0), contentMode: .fit)
                        .frame(maxWidth: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.red.opacity(0.6), lineWidth: 1.5))

                    HStack(spacing: 5) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .symbolEffect(.pulse, isActive: true)
                        Text("REC")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    .padding(10)
                }
            } else if let preview = captureVM.selectionPreviewImage {
                ZStack(alignment: .topLeading) {
                    Image(preview, scale: 1, label: Text("Preview"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))

                    Text(captureVM.selectedSource?.name ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .padding(10)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 80, height: 80)
                    Image(systemName: "record.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
                Text("Ready")
                    .font(.title2.weight(.semibold))
            }

            if captureVM.isCapturing {
                HStack(spacing: 12) {
                    if settings.recordingMode == .fullSession {
                        Label(formatDuration(captureVM.sessionDuration), systemImage: "record.circle.fill")
                            .foregroundStyle(.red)
                    }
                    Text("Buffer: \(Int(captureVM.bufferDuration))s · \(captureVM.bufferSampleCount) frames")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
            }

            // Recording mode picker
            recordingModePicker

            // Clip length presets
            clipLengthPicker

            // Source picker
            sourcePicker

            // Audio scope (only for window capture)
            if case .window = captureVM.selectedSource?.kind, settings.capturesSystemAudio {
                audioScopePicker
            }

            // Controls
            HStack(spacing: 12) {
                Button(action: { captureVM.toggleCapture() }) {
                    Label(
                        captureVM.isCapturing ? "Stop" : "Start Recording",
                        systemImage: captureVM.isCapturing ? "stop.fill" : "record.circle"
                    )
                    .frame(minWidth: 140)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(captureVM.isCapturing ? .red : .accentColor)

                Button(action: { captureVM.saveReplayClip() }) {
                    Label("Save Clip", systemImage: "scissors")
                        .frame(minWidth: 100)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(!captureVM.isCapturing || captureVM.isSavingClip || captureVM.pendingClip != nil)
                .keyboardShortcut("s", modifiers: [.command, .shift])

                if settings.capturesMicrophone {
                    Button(action: { captureVM.toggleMic() }) {
                        Image(systemName: captureVM.isMicMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(captureVM.isMicMuted ? .red : .primary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!captureVM.isCapturing)
                    .help(captureVM.isMicMuted ? "Unmute Mic" : "Mute Mic")
                }
            }

            // Export progress
            if captureVM.isSavingClip {
                VStack(spacing: 6) {
                    ProgressView(value: captureVM.saveProgress)
                        .frame(maxWidth: 260)
                    Text("Exporting clip…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !captureVM.statusMessage.isEmpty {
                Text(captureVM.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            if let err = captureVM.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Spacer()

            hotkeySummary
        }
        .padding(32)
        .animation(.default, value: captureVM.isCapturing)
        .animation(.default, value: captureVM.isSavingClip)
    }

    private var recordingModePicker: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Recording Mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: 340)

            Picker("Mode", selection: $settings.recordingMode) {
                ForEach(RecordingMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)
            .disabled(captureVM.isCapturing)

            if settings.recordingMode == .fullSession {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Full Session records everything to disk — uses more CPU and storage.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: 340, alignment: .leading)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private var clipLengthPicker: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Clip Length")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(settings.bitrate.ramEstimate(for: settings.replayDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 340)
            Picker("Clip Length", selection: $settings.replayDuration) {
                ForEach(ReplayDuration.allCases) { dur in
                    Text(dur.label).tag(dur)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)
            .disabled(captureVM.isCapturing)
        }
    }

    private var sourcePicker: some View {
        Group {
            if captureVM.availableSources.isEmpty {
                VStack(spacing: 8) {
                    Text("Screen Recording permission required")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Open System Settings") {
                            captureVM.openSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Retry") { captureVM.refreshSourcesExplicitly() }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                Menu {
                    ForEach(captureVM.availableSources) { source in
                        Button(action: { captureVM.selectSource(source) }) {
                            Label(source.name, systemImage: source.systemImageName)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: captureVM.selectedSource?.systemImageName ?? "display")
                        Text(captureVM.selectedSource?.name ?? "Select Source")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .onAppear { captureVM.refreshSourcesExplicitly() }
    }

    private var audioScopePicker: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Audio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: 340)

            Picker("Audio", selection: $settings.audioScope) {
                ForEach(AudioScope.allCases) { scope in
                    Label(scope.label, systemImage: scope.icon).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)
            .disabled(captureVM.isCapturing)
        }
    }

    private var hotkeySummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hotkeys")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 10)
            VStack(spacing: 6) {
                hotkeyRow("Save Clip",    binding: captureVM.settings.saveClipHotkey)
                Divider()
                hotkeyRow("Start / Stop", binding: captureVM.settings.startStopHotkey)
                Divider()
                hotkeyRow("Mute Mic",     binding: captureVM.settings.muteMicHotkey)
            }
        }
        .padding(18)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 360)
    }

    private func hotkeyRow(_ label: String, binding: HotkeyBinding) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(binding.displayString)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { captureVM.toggleCapture() }) {
                Image(systemName: captureVM.isCapturing ? "stop.circle" : "record.circle")
                    .foregroundStyle(captureVM.isCapturing ? .red : .primary)
            }
            .help(captureVM.isCapturing ? "Stop Recording" : "Start Recording")
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { captureVM.saveReplayClip() }) {
                Image(systemName: "scissors")
            }
            .help("Save Replay Clip")
            .disabled(!captureVM.isCapturing || captureVM.isSavingClip)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(
            CaptureViewModel(
                settings: .shared,
                permissions: PermissionsManager(),
                libraryManager: LibraryManager(settings: .shared)
            )
        )
        .environmentObject(LibraryViewModel(libraryManager: LibraryManager(settings: .shared)))
        .environmentObject(PermissionsManager())
        .frame(width: 900, height: 600)
}
