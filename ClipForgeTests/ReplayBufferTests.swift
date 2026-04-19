import XCTest
import CoreMedia
@testable import ClipForge

final class ReplayBufferTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal CMSampleBuffer with a known presentation timestamp.
    /// Uses a 1-sample linear PCM format that is simple to construct without real data.
    private func makeSample(pts seconds: Double) throws -> CMSampleBuffer {
        var formatDesc: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 44100),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 44100),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sb = sampleBuffer else {
            throw NSError(domain: "ReplayBufferTests", code: Int(status))
        }
        return sb
    }

    // MARK: - Tests

    func testEmptyBufferReturnsEmptySnapshot() async {
        let buffer = ReplayBuffer(maxDuration: 30)
        let snap = await buffer.snapshot()
        XCTAssertTrue(snap.video.isEmpty)
        XCTAssertTrue(snap.audio.isEmpty)
    }

    func testMaxDurationTrimming() async throws {
        let buffer = ReplayBuffer(maxDuration: 5)

        // Add 10 seconds of audio samples (one per second)
        for i in 0..<10 {
            let sample = try makeSample(pts: Double(i))
            await buffer.appendAudio(sample)
        }

        // Should only retain samples within the last 5 seconds
        let count = await buffer.audioCount
        XCTAssertLessThanOrEqual(count, 6, "Buffer should have trimmed old samples")
    }

    func testClear() async throws {
        let buffer = ReplayBuffer(maxDuration: 30)
        let sample = try makeSample(pts: 0)
        await buffer.appendAudio(sample)
        await buffer.clear()
        let count = await buffer.audioCount
        XCTAssertEqual(count, 0)
    }

    func testSetMaxDurationTrimsExisting() async throws {
        let buffer = ReplayBuffer(maxDuration: 60)

        // Add samples at t=0, 2, 4 … 58s
        for i in stride(from: 0, through: 58, by: 2) {
            await buffer.appendAudio(try makeSample(pts: Double(i)))
        }

        // Shrink the window to 10 seconds
        await buffer.setMaxDuration(10)
        let count = await buffer.audioCount
        // Should only have samples in [48, 58] → ≤ 7 samples
        XCTAssertLessThanOrEqual(count, 7)
    }

    func testAudioSamplesAlignedToVideoWindow() async throws {
        let buffer = ReplayBuffer(maxDuration: 30)

        // Add audio with no corresponding video
        for i in 0..<5 {
            await buffer.appendAudio(try makeSample(pts: Double(i)))
        }

        // snapshot() aligns audio to first video PTS. With no video, audio is empty.
        let snap = await buffer.snapshot()
        XCTAssertTrue(snap.audio.isEmpty, "Audio should be dropped when there are no video samples")
    }

    func testEstimatedDuration() async throws {
        let buffer = ReplayBuffer(maxDuration: 30)
        // Initially zero
        let zeroD = await buffer.estimatedDuration
        XCTAssertEqual(zeroD, 0, accuracy: 0.01)
    }
}
