import Foundation
import AVFoundation
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.clipforge.app", category: "session")

/// Continuously writes a live capture session to disk.
/// Lazy-initialises the AVAssetWriter on the first video sample so it can use
/// the real CMFormatDescription (needed for pass-through H.264/HEVC).
/// Audio inputs are created with explicit AAC settings so they don't need a
/// format hint at setup time.
actor SessionWriter {

    // MARK: - State

    private(set) var outputURL: URL?

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var sysAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?

    private var sessionStarted = false
    private let capturesSysAudio: Bool
    private let capturesMic: Bool

    /// Audio samples that arrive before the first video frame initialises the writer.
    private var pendingSysAudio: [CMSampleBuffer] = []
    private var pendingMic: [CMSampleBuffer] = []

    // MARK: - Init

    init(capturesSysAudio: Bool, capturesMic: Bool) {
        self.capturesSysAudio = capturesSysAudio
        self.capturesMic = capturesMic
    }

    // MARK: - Lifecycle

    /// Prepares a temp output URL. Call before starting capture.
    func prepare() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipforge_session_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)
        outputURL = url
        return url
    }

    /// Finalises the writer and returns the completed file URL (nil on failure).
    func stop() async -> URL? {
        guard sessionStarted, let w = writer else { return outputURL }
        videoInput?.markAsFinished()
        sysAudioInput?.markAsFinished()
        micInput?.markAsFinished()
        await withCheckedContinuation { cont in
            w.finishWriting { cont.resume() }
        }
        sessionStarted = false
        let url = outputURL
        if w.status == .completed {
            logger.notice("Session finished: \(url?.lastPathComponent ?? "", privacy: .public)")
            return url
        } else {
            logger.warning("Session writer failed: \(w.error?.localizedDescription ?? "unknown")")
            return nil
        }
    }

    // MARK: - Sample ingestion

    func appendVideo(_ sample: CMSampleBuffer) {
        if !sessionStarted { initWriter(firstVideoSample: sample) }
        guard sessionStarted, let input = videoInput, input.isReadyForMoreMediaData else { return }
        input.append(sample)
    }

    func appendSysAudio(_ sample: CMSampleBuffer) {
        if !sessionStarted {
            pendingSysAudio.append(sample)
            if pendingSysAudio.count > 500 { pendingSysAudio.removeFirst() }
            return
        }
        guard let input = sysAudioInput, input.isReadyForMoreMediaData else { return }
        input.append(sample)
    }

    func appendMicAudio(_ sample: CMSampleBuffer) {
        if !sessionStarted {
            pendingMic.append(sample)
            if pendingMic.count > 500 { pendingMic.removeFirst() }
            return
        }
        guard let input = micInput, input.isReadyForMoreMediaData else { return }
        input.append(sample)
    }

    // MARK: - Private

    private func initWriter(firstVideoSample: CMSampleBuffer) {
        guard let url = outputURL,
              let formatDesc = CMSampleBufferGetFormatDescription(firstVideoSample) else { return }

        do {
            let w = try AVAssetWriter(outputURL: url, fileType: .mp4)

            // Video — pass-through (already H.264/HEVC from VideoCompressor)
            let vi = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDesc)
            vi.expectsMediaDataInRealTime = true
            guard w.canAdd(vi) else { return }
            w.add(vi)

            // AAC settings for both audio tracks.
            let aacSettings: [String: Any] = [
                AVFormatIDKey:         kAudioFormatMPEG4AAC,
                AVSampleRateKey:       48_000.0,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey:   192_000
            ]

            var sai: AVAssetWriterInput?
            if capturesSysAudio {
                let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
                ai.expectsMediaDataInRealTime = true
                if w.canAdd(ai) { w.add(ai); sai = ai }
            }

            var mi: AVAssetWriterInput?
            if capturesMic {
                let aim = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
                aim.expectsMediaDataInRealTime = true
                if w.canAdd(aim) { w.add(aim); mi = aim }
            }

            let startPTS = CMSampleBufferGetPresentationTimeStamp(firstVideoSample)
            w.startWriting()
            w.startSession(atSourceTime: startPTS)

            guard w.status == .writing else {
                logger.error("Session writer failed to start: \(w.error?.localizedDescription ?? "")")
                return
            }

            writer = w
            videoInput = vi
            sysAudioInput = sai
            micInput = mi
            sessionStarted = true

            // Flush buffered audio that arrived before the first video frame.
            let videoStart = startPTS
            for s in pendingSysAudio
                where CMSampleBufferGetPresentationTimeStamp(s) >= videoStart
                   && sai?.isReadyForMoreMediaData == true {
                sai?.append(s)
            }
            for s in pendingMic
                where CMSampleBufferGetPresentationTimeStamp(s) >= videoStart
                   && mi?.isReadyForMoreMediaData == true {
                mi?.append(s)
            }
            pendingSysAudio.removeAll()
            pendingMic.removeAll()

            logger.notice("Session writer started → \(url.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("Session writer init failed: \(error.localizedDescription)")
        }
    }
}
