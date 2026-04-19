import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

// MARK: - C callback (must be a top-level function, not a closure)

private func vtCompressionOutputCallback(
    _ outputCallbackRefCon: UnsafeMutableRawPointer?,
    _ sourceFrameRefCon: UnsafeMutableRawPointer?,
    _ status: OSStatus,
    _ infoFlags: VTEncodeInfoFlags,
    _ sampleBuffer: CMSampleBuffer?
) {
    guard
        status == noErr,
        let sampleBuffer,
        let refCon = outputCallbackRefCon
    else { return }

    let compressor = Unmanaged<VideoCompressor>.fromOpaque(refCon).takeUnretainedValue()
    compressor.handleEncodedSample(sampleBuffer)
}

// MARK: - VideoCompressor

/// Wraps a VTCompressionSession to compress raw CVPixelBuffers (from ScreenCaptureKit)
/// into H.264 or HEVC CMSampleBuffers suitable for the ReplayBuffer.
///
/// Not an actor - the VT callbacks arrive on an internal VT queue. Thread-safety is handled
/// by directing all output through `onEncodedSample`, which callers should route
/// to the actor-isolated ReplayBuffer.
final class VideoCompressor {

    /// Called on an arbitrary queue; callers must not assume the main actor.
    var onEncodedSample: ((CMSampleBuffer) -> Void)?

    private var session: VTCompressionSession?

    // MARK: - Init

    init(
        width: Int32,
        height: Int32,
        fps: Double,
        bitrate: Int,
        codec: VideoCodecSetting = .h264
    ) throws {
        var session: VTCompressionSession?

        let err = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codec.cmCodecType,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: vtCompressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard err == noErr, let session else {
            throw VideoCompressorError.sessionCreationFailed(err)
        }
        self.session = session

        try configure(session: session, bitrate: bitrate, codec: codec)
        let prepErr = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepErr == noErr else {
            throw VideoCompressorError.prepareFailed(prepErr)
        }
    }

    // MARK: - Encode

    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let session else { return }
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    // MARK: - Lifecycle

    /// Flush any pending frames synchronously.
    func flush() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .positiveInfinity)
    }

    func invalidate() {
        guard let session else { return }
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    deinit { invalidate() }

    // MARK: - Internal

    fileprivate func handleEncodedSample(_ sample: CMSampleBuffer) {
        onEncodedSample?(sample)
    }

    // MARK: - Private configuration

    private func configure(session: VTCompressionSession, bitrate: Int, codec: VideoCodecSetting) throws {
        // Use a high keyframe interval (4 s at 30 fps) to minimise the number of IDR frames.
        // Fewer IDR frames = fewer potential SPS/PPS changes = more reliable pass-through export.
        let keyframeInterval = NSNumber(value: 120)
        // Lock the codec profile so SPS/PPS bytes stay identical across all IDR frames.
        let profileLevel: CFString = codec == .hevc
            ? kVTProfileLevel_HEVC_Main_AutoLevel
            : kVTProfileLevel_H264_High_AutoLevel

        let props: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime,              kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering,  kCFBooleanFalse),
            (kVTCompressionPropertyKey_AverageBitRate,        NSNumber(value: bitrate)),
            (kVTCompressionPropertyKey_ProfileLevel,          profileLevel),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval,   keyframeInterval),
        ]
        for (key, value) in props {
            let status = VTSessionSetProperty(session, key: key, value: value)
            if status != noErr && status != kVTPropertyNotSupportedErr {
                throw VideoCompressorError.propertyFailed(key as String, status)
            }
        }
    }

    // MARK: - Errors

    enum VideoCompressorError: Error, LocalizedError {
        case sessionCreationFailed(OSStatus)
        case prepareFailed(OSStatus)
        case propertyFailed(String, OSStatus)

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed(let s): return "VTCompressionSession creation failed: \(s)"
            case .prepareFailed(let s):         return "VTCompressionSession prepare failed: \(s)"
            case .propertyFailed(let k, let s): return "VT property '\(k)' failed: \(s)"
            }
        }
    }
}

// MARK: - Codec translation

/// Translates the user-facing `VideoEncoder` settings enum to a CMVideoCodecType.
enum VideoCodecSetting {
    case h264
    case hevc

    var cmCodecType: CMVideoCodecType {
        switch self {
        case .h264: return kCMVideoCodecType_H264
        case .hevc: return kCMVideoCodecType_HEVC
        }
    }

    static func from(_ setting: VideoEncoder) -> VideoCodecSetting {
        switch setting {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}
