import Foundation
import Combine
import SwiftUI
import CoreMedia
import AVFoundation
import AppKit
import os.log

private let vmLogger = Logger(subsystem: "com.clipforge.app", category: "viewmodel")

/// Orchestrates CaptureManager, AudioManager, and ReplayBuffer.
/// This is the single source of truth for the capture UI.
@MainActor
final class CaptureViewModel: ObservableObject {

    // MARK: - Published state

    @Published var isSavingClip: Bool = false
    @Published var saveProgress: Double = 0
    @Published var statusMessage: String = ""
    @Published var showCountdown: Bool = false
    @Published var countdownValue: Int = 3

    /// Non-nil while a clip is waiting for the user's save/discard decision.
    @Published var pendingClip: PendingClip? = nil

    // Forwarded from sub-managers
    @Published var isCapturing: Bool = false
    @Published var isMicMuted: Bool = false
    @Published var isMicActive: Bool = false
    @Published var availableSources: [CaptureSource] = []
    @Published var selectedSource: CaptureSource?
    @Published var lastError: String?
    @Published var bufferDuration: TimeInterval = 0
    @Published var bufferSampleCount: Int = 0
    @Published var selectionPreviewImage: CGImage?
    @Published var sessionDuration: TimeInterval = 0

    // MARK: - Dependencies

    let captureManager: CaptureManager
    var previewLayer: AVSampleBufferDisplayLayer { captureManager.previewLayer }
    let audioManager: AudioManager
    let systemAudioCapture: SystemAudioCapture
    let replayBuffer: ReplayBuffer
    let libraryManager: LibraryManager
    let settings: SettingsStore
    let permissions: PermissionsManager

    private var cancellables = Set<AnyCancellable>()
    private var bufferUpdateTask: Task<Void, Never>?
    private var sessionWriter: SessionWriter?
    private var sessionStartDate: Date?

    // MARK: - Init

    init(
        settings: SettingsStore,
        permissions: PermissionsManager,
        libraryManager: LibraryManager
    ) {
        self.settings = settings
        self.permissions = permissions
        self.libraryManager = libraryManager

        let buffer = ReplayBuffer(maxDuration: settings.replayDuration.seconds)
        replayBuffer = buffer
        captureManager = CaptureManager(replayBuffer: buffer, settings: settings)
        audioManager = AudioManager()
        systemAudioCapture = SystemAudioCapture()

        setupBindings()
        wireHotkeys()
    }

    // MARK: - Actions

    func toggleCapture() {
        Task { await captureManager.toggleCapture() }
    }

    func saveReplayClip() {
        guard !isSavingClip else { return }
        Task { await performSaveClip() }
    }

    func toggleMic() {
        if isMicActive {
            audioManager.toggleMute()
        }
    }

    func refreshSources() {
        Task { await captureManager.refreshSources() }
    }

    /// Bypasses preflight — calls SCShareableContent directly. Safe to call from any user action.
    /// SCShareableContent only triggers a system prompt the first time per TCC state transition.
    func refreshSourcesExplicitly() {
        Task { await captureManager.refreshSources(forced: true) }
    }

    /// Opens the Screen Recording section of System Settings.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Called on NSApplication.didBecomeActiveNotification.
    /// Always does a forced refresh — SCShareableContent succeeds silently when already granted
    /// and only emits a one-time system prompt when transitioning from "not determined".
    func handleAppBecameActive() {
        refreshSourcesExplicitly()
    }

    func selectSource(_ source: CaptureSource) {
        captureManager.selectedSource = source
        selectedSource = source
        if !captureManager.isCapturing { captureManager.startSelectionPreview() }
    }

    // MARK: - Private: save clip

    private func performSaveClip() async {
        isSavingClip = true
        saveProgress = 0

        let snapshot = await replayBuffer.snapshot()
        guard !snapshot.video.isEmpty else {
            statusMessage = "Nothing in buffer yet - start capturing first."
            isSavingClip = false
            return
        }

        let title = defaultTitle()
        let duration = await replayBuffer.estimatedDuration
        let appName = captureManager.selectedSource?.typeLabel

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipforge_\(UUID().uuidString).mp4")

        do {
            try await ClipExportManager.exportReplay(
                videoSamples: snapshot.video,
                sysAudioSamples: snapshot.sysAudio,
                micAudioSamples: snapshot.micAudio,
                to: tempURL,
                progressHandler: { [weak self] p in
                    Task { @MainActor [weak self] in self?.saveProgress = p }
                }
            )

            // Copy to clipboard immediately - this is the primary action.
            copyToClipboard(url: tempURL)

            saveProgress = 1.0
            statusMessage = ""

            NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: false)?.play()

            // Show the save-or-discard banner.
            pendingClip = PendingClip(
                url: tempURL,
                title: title,
                duration: duration,
                appName: appName
            )
        } catch {
            lastError = "Export failed: \(error.localizedDescription)"
            statusMessage = ""
            try? FileManager.default.removeItem(at: tempURL)
        }

        isSavingClip = false
    }

    // MARK: - Pending clip resolution

    /// Moves the temp clip into the library and dismisses the banner.
    func savePendingClipToLibrary() {
        guard let pending = pendingClip else { return }
        pendingClip = nil
        Task {
            do {
                _ = try await libraryManager.addClip(
                    from: pending.url,
                    title: pending.title,
                    duration: pending.duration,
                    appName: pending.appName
                )
                statusMessage = "Saved to library: \(pending.title)"
            } catch {
                lastError = "Could not save to library: \(error.localizedDescription)"
                // Keep the file in temp so the user isn't left with nothing.
            }
        }
    }

    /// Deletes the temp clip and dismisses the banner.
    func discardPendingClip() {
        guard let pending = pendingClip else { return }
        pendingClip = nil
        try? FileManager.default.removeItem(at: pending.url)
        statusMessage = ""
    }

    // MARK: - Clipboard

    /// Writes the clip file URL to the system pasteboard so the user can paste
    /// directly into Discord, Slack, Messages, Finder, etc.
    private func copyToClipboard(url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        // Write as a file URL - most apps (Discord, Slack, Finder) understand this.
        pb.writeObjects([url as NSURL])
        // Also declare the UTType so apps that accept video data directly work too.
        if let data = try? Data(contentsOf: url) {
            pb.setData(data, forType: .init("public.mpeg-4"))
        }
    }

    // MARK: - Private: bindings

    private func setupBindings() {
        // Mirror sub-manager state upward
        captureManager.$isCapturing
            .receive(on: RunLoop.main)
            .assign(to: &$isCapturing)

        captureManager.$availableSources
            .receive(on: RunLoop.main)
            .assign(to: &$availableSources)

        captureManager.$selectedSource
            .receive(on: RunLoop.main)
            .assign(to: &$selectedSource)

        captureManager.$lastError
            .receive(on: RunLoop.main)
            .assign(to: &$lastError)

        // Mirror selection preview
        captureManager.$selectionPreviewImage
            .receive(on: RunLoop.main)
            .assign(to: &$selectionPreviewImage)

        // Sounds
        captureManager.$isCapturing
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { isCapturing in
                let file = isCapturing ? "Pop" : "Tink"
                NSSound(contentsOfFile: "/System/Library/Sounds/\(file).aiff", byReference: false)?.play()
            }
            .store(in: &cancellables)

        audioManager.$isMicMuted
            .receive(on: RunLoop.main)
            .assign(to: &$isMicMuted)

        audioManager.$isMicActive
            .receive(on: RunLoop.main)
            .assign(to: &$isMicActive)

        // Wire mic samples into the dedicated mic buffer (separate from system audio)
        audioManager.onAudioSample = { [weak self] sample in
            guard let self else { return }
            Task {
                await self.replayBuffer.appendMicAudio(sample)
                await self.sessionWriter?.appendMicAudio(sample)
            }
        }

        // Wire system audio capture into the sys audio buffer
        systemAudioCapture.onAudioSample = { [weak self] sample in
            guard let self else { return }
            Task {
                await self.replayBuffer.appendAudio(sample)
                await self.sessionWriter?.appendSysAudio(sample)
            }
        }

        // Start/stop capture when recording begins/ends
        captureManager.$isCapturing
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] isCapturing in
                guard let self else { return }
                if isCapturing {
                    if self.settings.capturesMicrophone {
                        Task { await self.audioManager.startMicCapture() }
                    }
                    if self.settings.capturesSystemAudio {
                        do {
                            var pids: [pid_t] = []
                            if self.settings.audioScope == .windowOnly,
                               case .window = self.captureManager.selectedSource?.kind,
                               let pid = self.captureManager.selectedSource?.scWindow?.owningApplication?.processID {
                                pids = [pid]
                            }
                            try self.systemAudioCapture.start(processPIDs: pids)
                        } catch {
                            vmLogger.warning("SystemAudioCapture start failed: \(error.localizedDescription)")
                        }
                    }
                    // Full session: start session writer and hook into encoded video.
                    if self.settings.recordingMode == .fullSession {
                        Task { await self.startSessionWriter() }
                    }
                } else {
                    self.audioManager.stopMicCapture()
                    self.systemAudioCapture.stop()
                    // Full session: finalise the recording.
                    if self.settings.recordingMode == .fullSession {
                        Task { await self.finaliseSession() }
                    }
                    self.sessionStartDate = nil
                    self.sessionDuration = 0
                }
            }
            .store(in: &cancellables)

        // Update buffer stats periodically
        bufferUpdateTask = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let dur = await replayBuffer.estimatedDuration
                let count = await replayBuffer.videoCount
                let sysAudio = await replayBuffer.sysAudioCount
                let micAudio = await replayBuffer.micAudioCount
                tick += 1
                if tick % 5 == 0 {
                    vmLogger.notice("Buffer — video:\(count) sysAudio:\(sysAudio) micAudio:\(micAudio) dur:\(dur, format: .fixed(precision: 1))s")
                }
                await MainActor.run {
                    bufferDuration = dur
                    bufferSampleCount = count
                }
            }
        }

        // Keep buffer duration in sync with settings
        settings.$replayDuration
            .sink { [weak self] dur in
                guard let self else { return }
                Task { await self.replayBuffer.setMaxDuration(dur.seconds) }
            }
            .store(in: &cancellables)
    }

    private func wireHotkeys() {
        let hm = HotkeyManager.shared
        hm.onSaveClip      = { [weak self] in self?.saveReplayClip() }
        hm.onToggleCapture = { [weak self] in self?.toggleCapture() }
        hm.onToggleMic     = { [weak self] in self?.toggleMic() }
        hm.onOpenApp       = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        applyHotkeyBindings()

        // Re-register whenever any binding changes.
        Publishers.MergeMany([
            settings.$saveClipHotkey.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$startStopHotkey.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$muteMicHotkey.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$openAppHotkey.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.applyHotkeyBindings() }
        .store(in: &cancellables)
    }

    // MARK: - Session recording

    private func startSessionWriter() async {
        let sw = SessionWriter(
            capturesSysAudio: settings.capturesSystemAudio,
            capturesMic: settings.capturesMicrophone
        )
        let url = await sw.prepare()
        sessionWriter = sw
        sessionStartDate = Date()

        // Route encoded video frames into the session writer.
        captureManager.additionalVideoSampleHandler = { [weak self] sample in
            guard let self else { return }
            Task { await self.sessionWriter?.appendVideo(sample) }
        }

        vmLogger.notice("Full session recording started → \(url.lastPathComponent, privacy: .public)")

        // Update session duration every second while recording.
        Task {
            while !Task.isCancelled, isCapturing {
                try? await Task.sleep(for: .seconds(1))
                sessionDuration = sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
            }
        }
    }

    private func finaliseSession() async {
        captureManager.additionalVideoSampleHandler = nil
        guard let sw = sessionWriter else { return }
        sessionWriter = nil

        statusMessage = "Saving session…"
        guard let url = await sw.stop() else {
            lastError = "Session recording failed to save."
            statusMessage = ""
            return
        }

        // Move the session into the library.
        let title = defaultTitle() + " (Full Session)"
        do {
            let asset = AVURLAsset(url: url)
            let cmDuration = try await asset.load(.duration)
            let duration = cmDuration.seconds
            _ = try await libraryManager.addClip(from: url, title: title, duration: duration, appName: captureManager.selectedSource?.typeLabel)
            statusMessage = "Session saved: \(title)"
        } catch {
            lastError = "Could not save session: \(error.localizedDescription)"
            statusMessage = ""
        }
    }

    private func applyHotkeyBindings() {
        HotkeyManager.shared.applyBindings(
            saveClip:      settings.saveClipHotkey,
            toggleCapture: settings.startStopHotkey,
            toggleMic:     settings.muteMicHotkey,
            openApp:       settings.openAppHotkey
        )
    }

    private func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let app = captureManager.selectedSource?.typeLabel ?? "Clip"
        return "\(app) \(formatter.string(from: Date()))"
    }
}
