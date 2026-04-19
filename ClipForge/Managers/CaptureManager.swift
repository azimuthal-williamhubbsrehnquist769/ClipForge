import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import Combine
import os.log

private let logger = Logger(subsystem: "com.clipforge.app", category: "capture")

/// Manages the ScreenCaptureKit stream. Compresses incoming pixel buffers via VideoEncoder
/// and feeds compressed samples into the shared ReplayBuffer.
@MainActor
final class CaptureManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var isCapturing: Bool = false
    @Published var availableSources: [CaptureSource] = []
    @Published var selectedSource: CaptureSource?
    @Published var lastError: String?

    // MARK: - Dependencies

    let replayBuffer: ReplayBuffer
    private let settings: SettingsStore

    // MARK: - Private

    private var stream: SCStream?
    private var encoder: VideoCompressor?

    /// Optional secondary handler for encoded video samples (used by SessionWriter in full-session mode).
    var additionalVideoSampleHandler: ((CMSampleBuffer) -> Void)?

    /// Serial queue for SCStream sample delivery
    private let sampleQueue = DispatchQueue(label: "com.clipforge.capture.samples", qos: .userInteractive)

    // MARK: - Preview
    let previewLayer = AVSampleBufferDisplayLayer()
    private var lastPreviewTime: CFTimeInterval = 0

    /// Still-image preview shown while a source is selected but not yet recording.
    @Published var selectionPreviewImage: CGImage?
    private var selectionPreviewTask: Task<Void, Never>?

    // MARK: - Init

    init(replayBuffer: ReplayBuffer, settings: SettingsStore) {
        self.replayBuffer = replayBuffer
        self.settings = settings
        super.init()
        setupPreviewLayer()
    }

    private func setupPreviewLayer() {
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let tb = timebase {
            CMTimebaseSetTime(tb, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(tb, rate: 1.0)
            previewLayer.controlTimebase = tb
        }
    }

    private func enqueuePreview(_ sample: CMSampleBuffer) {
        let now = CACurrentMediaTime()
        guard now - lastPreviewTime >= 1.0 / 15.0 else { return }
        lastPreviewTime = now
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: CMTime(seconds: now, preferredTimescale: 90_000),
            decodeTimeStamp: .invalid
        )
        var retimed: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: sample,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimed
        ) == noErr, let retimed else { return }
        previewLayer.enqueue(retimed)
    }

    // MARK: - Source enumeration

    /// Enumerates capture sources.
    /// - Parameter forced: When false (default), skips the call if TCC preflight says not granted —
    ///   safe to call automatically at launch. When true, calls SCShareableContent directly;
    ///   use only from explicit user actions (Retry button, return from System Settings).
    func refreshSources(forced: Bool = false) async {
        guard forced || CGPreflightScreenCaptureAccess() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            var sources: [CaptureSource] = []

            for display in content.displays {
                sources.append(.from(display: display))
            }
            for window in content.windows where window.owningApplication != nil && !window.isOnScreen == false {
                if let app = window.owningApplication, !app.applicationName.isEmpty {
                    sources.append(.from(window: window))
                }
            }

            availableSources = sources
            if selectedSource == nil {
                selectedSource = sources.first
            }
            if !isCapturing { startSelectionPreview() }
        } catch {
            lastError = "Cannot enumerate capture sources: \(error.localizedDescription)"
        }
    }

    // MARK: - Start capture

    func startCapture() async {
        guard !isCapturing else { return }

        // Auto-load sources if none are available yet.
        // Use forced=true because the user just clicked Start — fine to trigger TCC here.
        if availableSources.isEmpty {
            await refreshSources(forced: true)
        }

        guard let source = selectedSource else {
            lastError = "No capture source selected."
            return
        }

        do {
            let config = buildStreamConfiguration(for: source)
            let filter = try buildFilter(for: source)

            // Set up the video encoder
            let (width, height) = dimensions(for: source, config: config)
            encoder = try VideoCompressor(
                width: Int32(width),
                height: Int32(height),
                fps: Double(settings.fps.rawValue),
                bitrate: settings.bitrate.bitsPerSecond,
                codec: VideoCodecSetting.from(settings.encoder)
            )

            encoder?.onEncodedSample = { [weak self] sample in
                guard let self else { return }
                Task { await self.replayBuffer.appendVideo(sample) }
                self.additionalVideoSampleHandler?(sample)
                DispatchQueue.main.async { [weak self] in self?.enqueuePreview(sample) }
            }

            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

            try await newStream.startCapture()

            if settings.capturesSystemAudio {
                try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }

            stream = newStream
            isCapturing = true
            lastError = nil
            stopSelectionPreview()
        } catch {
            lastError = "Failed to start capture: \(error.localizedDescription)"
        }
    }

    // MARK: - Stop capture

    func stopCapture() async {
        guard isCapturing, let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            lastError = "Failed to stop capture: \(error.localizedDescription)"
        }
        encoder?.flush()
        encoder?.invalidate()
        encoder = nil
        self.stream = nil
        previewLayer.flush()
        isCapturing = false
        startSelectionPreview()
    }

    // MARK: - Toggle

    func toggleCapture() async {
        if isCapturing {
            await stopCapture()
        } else {
            await startCapture()
        }
    }

    // MARK: - Selection preview

    func startSelectionPreview() {
        stopSelectionPreview()
        selectionPreviewTask = Task { [weak self] in
            // Wait until sources are confirmed available before hitting SCScreenshotManager
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
            while !Task.isCancelled {
                await self?.captureSelectionSnapshot()
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 s
            }
        }
    }

    func stopSelectionPreview() {
        selectionPreviewTask?.cancel()
        selectionPreviewTask = nil
    }

    private func captureSelectionSnapshot() async {
        // Only attempt if sources were successfully enumerated (proxy for permission granted)
        guard !isCapturing, !availableSources.isEmpty, let source = selectedSource else { return }
        let filter: SCContentFilter
        if let display = source.scDisplay {
            filter = SCContentFilter(display: display, excludingWindows: [])
        } else if let window = source.scWindow {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else { return }

        let config = SCStreamConfiguration()
        config.width  = 640
        config.height = 360

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            selectionPreviewImage = image
        } catch {}
    }

    // MARK: - Config builders

    private func buildStreamConfiguration(for source: CaptureSource) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps.rawValue))
        config.queueDepth = 6
        config.showsCursor = false

        if settings.capturesSystemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = false
            config.sampleRate = 48_000
            config.channelCount = 2
        }

        switch source.kind {
        case .display:
            // For displays, respect the user's resolution preset (or native if unset).
            if let preset = settings.resolution.dimensions {
                config.width  = Int(preset.width)
                config.height = Int(preset.height)
            } else if let display = source.scDisplay {
                config.width  = display.width
                config.height = display.height
            }

        case .window:
            // For windows, match the window's actual frame so there are no black bars.
            // Cap the longest edge at 1920 px and ensure total pixel count stays
            // within hardware encoder limits (H.264 High AutoLevel).
            if let window = source.scWindow {
                let w = window.frame.width
                let h = window.frame.height
                guard w > 0, h > 0 else { break }
                let maxEdge: CGFloat = 1920
                let scale = min(1.0, maxEdge / max(w, h))
                // Dimensions must be even for H.264 encoding.
                let outW = max(2, Int((w * scale / 2).rounded()) * 2)
                let outH = max(2, Int((h * scale / 2).rounded()) * 2)
                config.width  = outW
                config.height = outH
            }
        }

        return config
    }

    private func buildFilter(for source: CaptureSource) throws -> SCContentFilter {
        if let display = source.scDisplay {
            return SCContentFilter(display: display, excludingWindows: [])
        } else if let window = source.scWindow {
            return SCContentFilter(desktopIndependentWindow: window)
        } else {
            throw CaptureError.invalidSource
        }
    }

    private func dimensions(for source: CaptureSource, config: SCStreamConfiguration) -> (Int, Int) {
        // Config was already sized correctly by buildStreamConfiguration(for:).
        if config.width > 0 && config.height > 0 { return (config.width, config.height) }
        if let display = source.scDisplay { return (display.width, display.height) }
        if let window = source.scWindow   { return (Int(window.frame.width), Int(window.frame.height)) }
        return (1920, 1080)
    }

    // MARK: - Errors

    enum CaptureError: Error, LocalizedError {
        case invalidSource
        var errorDescription: String? { "The selected capture source is no longer valid." }
    }
}

// MARK: - SCStreamOutput

extension CaptureManager: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        switch type {
        case .screen:
            handleVideoSample(sampleBuffer)
        case .audio:
            break  // System audio handled by SystemAudioCapture IOProc
        case .microphone:
            break
        @unknown default:
            break
        }
    }

    nonisolated private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let statusRawValue = attachments.first?[SCStreamFrameInfo.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue),
            status == .complete
        else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        Task { @MainActor [weak self] in
            self?.encoder?.encode(pixelBuffer: pixelBuffer, presentationTime: pts)
        }
    }
}

// MARK: - SCStreamDelegate

extension CaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.stream = nil
            self?.lastError = "Stream stopped unexpectedly: \(error.localizedDescription)"
        }
    }
}
