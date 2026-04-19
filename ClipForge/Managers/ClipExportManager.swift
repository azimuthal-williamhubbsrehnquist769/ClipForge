import Foundation
import AVFoundation
import CoreMedia
import CoreImage
import AppKit
import os.log

private let logger = Logger(subsystem: "com.clipforge.app", category: "export")

/// Assembles buffered CMSampleBuffers into an MP4 file on disk.
/// Also handles thumbnail generation and basic trim export.
enum ClipExportManager {

    // MARK: - Export from replay buffer snapshot

    /// Writes buffered samples to `outputURL` (must end in .mp4).
    /// - Parameters:
    ///   - videoSamples: H.264/HEVC compressed samples from VTCompressionSession.
    ///   - sysAudioSamples: LPCM system audio from SCStream (encoded to AAC on write).
    ///   - micAudioSamples: LPCM mic audio from AVCaptureSession (encoded to AAC on write, separate track).
    static func exportReplay(
        videoSamples: [CMSampleBuffer],
        sysAudioSamples: [CMSampleBuffer],
        micAudioSamples: [CMSampleBuffer] = [],
        to outputURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        guard !videoSamples.isEmpty else { throw ExportError.noVideoSamples }

        // Trim to last contiguous run of identical SPS/PPS so pass-through never
        // sees a format description change mid-stream.
        let videoSamples = trimToConsistentFormat(videoSamples)

        // Re-align audio to the trimmed video window.
        let videoStart = CMSampleBufferGetPresentationTimeStamp(videoSamples[0])
        let sysAudioSamples = sysAudioSamples.filter {
            CMSampleBufferGetPresentationTimeStamp($0) >= videoStart
        }
        let micAudioSamples = micAudioSamples.filter {
            CMSampleBufferGetPresentationTimeStamp($0) >= videoStart
        }

        logger.notice("Export: \(videoSamples.count) video, \(sysAudioSamples.count) sys audio, \(micAudioSamples.count) mic audio samples")

        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video — pass-through (already H.264/HEVC)
        guard let formatDesc = CMSampleBufferGetFormatDescription(videoSamples[0]) else {
            throw ExportError.missingFormatDescription
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDesc)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ExportError.cannotAddTrack }
        writer.add(videoInput)

        // AAC settings used for both audio tracks.
        // SCStream and AVCaptureSession both deliver LPCM; AVAssetWriterInput encodes to AAC.
        // Type matters: AVFormatIDKey must be AudioFormatID (UInt32); AVSampleRateKey must be Double.
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,  // UInt32 — NOT Int()
            AVSampleRateKey: 48_000.0,             // Double
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]

        var sysAudioInput: AVAssetWriterInput?
        if let first = sysAudioSamples.first,
           let fmt = CMSampleBufferGetFormatDescription(first) {
            logger.notice("Sys audio format: \(String(describing: fmt))")
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings, sourceFormatHint: fmt)
            ai.expectsMediaDataInRealTime = false
            let canAdd = writer.canAdd(ai)
            logger.notice("Can add sys audio input: \(canAdd), writer error: \(writer.error?.localizedDescription ?? "none")")
            if canAdd { writer.add(ai); sysAudioInput = ai }
        } else {
            logger.warning("No sys audio samples or missing format description — sysAudio count: \(sysAudioSamples.count)")
        }

        var micInput: AVAssetWriterInput?
        if let first = micAudioSamples.first,
           let fmt = CMSampleBufferGetFormatDescription(first) {
            let mi = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings, sourceFormatHint: fmt)
            mi.expectsMediaDataInRealTime = false
            if writer.canAdd(mi) { writer.add(mi); micInput = mi }
        }

        // Start session anchored to first video frame
        let startTime = CMSampleBufferGetPresentationTimeStamp(videoSamples[0])
        writer.startWriting()
        writer.startSession(atSourceTime: startTime)
        guard writer.status == .writing else {
            throw writer.error ?? ExportError.writerFailed
        }

        // Write all tracks concurrently — AVAssetWriter requires concurrent feeding
        // of multiple inputs. Writing video fully before audio causes the writer to
        // discard the audio track silently.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    try await writeSamples(videoSamples, to: videoInput, writer: writer, progress: nil)
                } catch {
                    logger.warning("Video write failed: \(error.localizedDescription)")
                }
            }
            if let ai = sysAudioInput {
                group.addTask {
                    await writeAudioSamples(sysAudioSamples, to: ai, writer: writer, progress: nil)
                }
            }
            if let mi = micInput {
                group.addTask {
                    await writeAudioSamples(micAudioSamples, to: mi, writer: writer, progress: nil)
                }
            }
        }
        progressHandler?(0.85)

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }

        progressHandler?(1.0)

        guard writer.status == .completed else {
            throw writer.error ?? ExportError.writerFailed
        }
    }

    // MARK: - Trim export

    static func exportTrimmed(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval,
        to outputURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let clampedEnd = min(endTime, duration.seconds)

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end:   CMTime(seconds: clampedEnd, preferredTimescale: 600)
        )

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.cannotCreateExportSession
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange

        try? FileManager.default.removeItem(at: outputURL)
        await exportSession.export()

        if let err = exportSession.error { throw err }
        guard exportSession.status == .completed else { throw ExportError.writerFailed }
    }

    // MARK: - Thumbnail generation

    static func generateThumbnail(for url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: time)
        let nsImage = NSImage(cgImage: cgImage, size: .zero)

        let thumbURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_thumb.jpg")

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw ExportError.thumbnailFailed
        }

        try jpegData.write(to: thumbURL)
        return thumbURL
    }

    // MARK: - Private helpers

    /// Returns the longest suffix of compressed video samples that all share the same
    /// CMFormatDescription as the last sample — guaranteed to start on a keyframe.
    private static func trimToConsistentFormat(_ samples: [CMSampleBuffer]) -> [CMSampleBuffer] {
        guard samples.count > 1,
              let targetFmt = CMSampleBufferGetFormatDescription(samples[samples.count - 1])
        else { return samples }

        var startIdx = samples.count - 1
        for i in stride(from: samples.count - 2, through: 0, by: -1) {
            guard let fmt = CMSampleBufferGetFormatDescription(samples[i]),
                  CMFormatDescriptionEqual(fmt, otherFormatDescription: targetFmt) else { break }
            startIdx = i
        }
        return startIdx == 0 ? samples : Array(samples[startIdx...])
    }

    /// Audio-safe writer: skips individual samples that are rejected rather than aborting the whole track.
    /// A single out-of-window or mis-timed sample should not silence the entire clip.
    private static func writeAudioSamples(
        _ samples: [CMSampleBuffer],
        to input: AVAssetWriterInput,
        writer: AVAssetWriter,
        progress: ((Int) -> Void)? = nil
    ) async {
        defer { input.markAsFinished() }
        guard !samples.isEmpty else { return }
        for sample in samples {
            guard writer.status == .writing else { return }
            var retries = 0
            while !input.isReadyForMoreMediaData {
                guard retries < 200, writer.status == .writing else { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
                retries += 1
            }
            let appended = input.append(sample)
            if !appended { logger.warning("Audio sample rejected — writer status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")") }
            progress?(1)
        }
    }

    private static func writeSamples(
        _ samples: [CMSampleBuffer],
        to input: AVAssetWriterInput,
        writer: AVAssetWriter,
        progress: ((Int) -> Void)? = nil
    ) async throws {
        defer { input.markAsFinished() }
        guard !samples.isEmpty else { return }
        for (i, sample) in samples.enumerated() {
            guard writer.status == .writing else {
                throw writer.error ?? ExportError.writerFailed
            }
            var retries = 0
            while !input.isReadyForMoreMediaData {
                guard retries < 300 else { throw ExportError.appendSampleFailed(i) }
                try await Task.sleep(nanoseconds: 10_000_000)
                retries += 1
            }
            guard input.append(sample) else {
                throw writer.error ?? ExportError.appendSampleFailed(i)
            }
            progress?(1)
        }
    }

    // MARK: - Errors

    enum ExportError: Error, LocalizedError {
        case noVideoSamples
        case missingFormatDescription
        case cannotAddTrack
        case appendSampleFailed(Int)
        case cannotCreateExportSession
        case writerFailed
        case thumbnailFailed

        var errorDescription: String? {
            switch self {
            case .noVideoSamples:             return "No video samples to export."
            case .missingFormatDescription:   return "Cannot read video format."
            case .cannotAddTrack:             return "Cannot add track to export file."
            case .appendSampleFailed(let i):  return "Failed to append sample \(i)."
            case .cannotCreateExportSession:  return "Cannot create export session."
            case .writerFailed:               return "Export writer failed."
            case .thumbnailFailed:            return "Could not generate thumbnail."
            }
        }
    }
}
