import Foundation
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.clipforge.app", category: "buffer")

/// Thread-safe ring buffer holding compressed video and audio CMSampleBuffers
/// for the configured replay window duration.
///
/// Uses Swift's `actor` isolation to avoid lock-based concurrency. All mutations
/// happen on the actor's executor; callers use `await`.
actor ReplayBuffer {

    // MARK: - State

    private var videoSamples: [CMSampleBuffer] = []
    private var sysAudioSamples: [CMSampleBuffer] = []   // system audio from SCStream (LPCM)
    private var micAudioSamples: [CMSampleBuffer] = []   // microphone from AVCaptureSession (LPCM)
    private(set) var maxDuration: TimeInterval

    // MARK: - Init

    init(maxDuration: TimeInterval) {
        self.maxDuration = maxDuration
        videoSamples.reserveCapacity(3_600)
        sysAudioSamples.reserveCapacity(5_000)
        micAudioSamples.reserveCapacity(5_000)
    }

    // MARK: - Configuration

    func setMaxDuration(_ duration: TimeInterval) {
        maxDuration = duration
        trimAll()
    }

    // MARK: - Append

    func appendVideo(_ sample: CMSampleBuffer) {
        videoSamples.append(sample)
        trimVideo()
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        if sysAudioSamples.isEmpty {
            logger.notice("First sys audio sample received — SCStream audio is working")
        }
        sysAudioSamples.append(sample)
        trimSysAudio()
    }

    func appendMicAudio(_ sample: CMSampleBuffer) {
        micAudioSamples.append(sample)
        trimMicAudio()
    }

    // MARK: - Snapshot

    /// Returns a snapshot trimmed to start on a keyframe.
    /// System audio and mic audio are kept separate so their timestamps never collide.
    func snapshot() -> (video: [CMSampleBuffer], sysAudio: [CMSampleBuffer], micAudio: [CMSampleBuffer]) {
        let vid = videoSamplesFromFirstKeyframe()
        return (vid, audioAligned(sysAudioSamples, to: vid), audioAligned(micAudioSamples, to: vid))
    }

    func clear() {
        videoSamples.removeAll(keepingCapacity: true)
        sysAudioSamples.removeAll(keepingCapacity: true)
        micAudioSamples.removeAll(keepingCapacity: true)
    }

    // MARK: - Diagnostics

    var videoCount: Int { videoSamples.count }
    var sysAudioCount: Int { sysAudioSamples.count }
    var micAudioCount: Int { micAudioSamples.count }

    var estimatedDuration: TimeInterval {
        guard let first = videoSamples.first, let last = videoSamples.last else { return 0 }
        let start = CMSampleBufferGetPresentationTimeStamp(first)
        let end   = CMSampleBufferGetPresentationTimeStamp(last)
        return CMTimeSubtract(end, start).seconds
    }

    // MARK: - Private helpers

    private func trimVideo() {
        guard let last = videoSamples.last else { return }
        let cutoff = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(last),
                                    CMTime(seconds: maxDuration, preferredTimescale: 90_000))
        videoSamples.removeAll { CMSampleBufferGetPresentationTimeStamp($0) < cutoff }
    }

    private func trimSysAudio() {
        guard let last = sysAudioSamples.last else { return }
        let cutoff = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(last),
                                    CMTime(seconds: maxDuration, preferredTimescale: 90_000))
        sysAudioSamples.removeAll { CMSampleBufferGetPresentationTimeStamp($0) < cutoff }
    }

    private func trimMicAudio() {
        guard let last = micAudioSamples.last else { return }
        let cutoff = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(last),
                                    CMTime(seconds: maxDuration, preferredTimescale: 90_000))
        micAudioSamples.removeAll { CMSampleBufferGetPresentationTimeStamp($0) < cutoff }
    }

    private func trimAll() {
        trimVideo(); trimSysAudio(); trimMicAudio()
    }

    private func videoSamplesFromFirstKeyframe() -> [CMSampleBuffer] {
        guard !videoSamples.isEmpty else { return [] }
        let idx = videoSamples.firstIndex { isKeyframe($0) } ?? 0
        return Array(videoSamples[idx...])
    }

    private func audioAligned(_ samples: [CMSampleBuffer], to video: [CMSampleBuffer]) -> [CMSampleBuffer] {
        guard let firstVideoTime = video.first.map({ CMSampleBufferGetPresentationTimeStamp($0) }) else { return [] }
        return samples.filter { CMSampleBufferGetPresentationTimeStamp($0) >= firstVideoTime }
    }

    private func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[CFString: Any]],
              let first = attachments.first else { return true }
        return (first[kCMSampleAttachmentKey_NotSync] as? Bool) != true
    }
}
