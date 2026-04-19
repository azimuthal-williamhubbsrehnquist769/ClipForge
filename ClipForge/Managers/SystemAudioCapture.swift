import Foundation
import CoreAudio
import AVFoundation
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.clipforge.app", category: "sysaudio")

/// Captures all system audio using CoreAudio process taps + aggregate device (macOS 14.2+).
/// Uses a direct AudioDeviceIOProc instead of AVAudioEngine to avoid macOS 26 compatibility issues.
final class SystemAudioCapture {

    var onAudioSample: ((CMSampleBuffer) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var cachedPluginID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var capturedASBD = AudioStreamBasicDescription()
    private var capturedFmt: CMAudioFormatDescription?

    // MARK: - Start / Stop

    /// - Parameter processPIDs: If non-empty, captures audio only from those processes (window-only mode).
    ///   If empty, captures all system audio (desktop mode).
    func start(processPIDs: [pid_t] = []) throws {
        guard #available(macOS 14.2, *) else { return }
        guard tapID == AudioObjectID(kAudioObjectUnknown) else { return }

        // 1. Create a stereo tap — scoped to specific processes or global.
        // CATapDescription.stereoMixdownOfProcesses takes CoreAudio AudioObjectIDs, not PIDs.
        let tapDesc: CATapDescription
        if processPIDs.isEmpty {
            tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            logger.notice("Audio scope: desktop (global tap)")
        } else {
            let audioObjIDs = processPIDs.compactMap { audioObjectID(forPID: $0) }
            tapDesc = CATapDescription(stereoMixdownOfProcesses: audioObjIDs)
            logger.notice("Audio scope: window-only pids=\(processPIDs, privacy: .public) objIDs=\(audioObjIDs, privacy: .public)")
        }
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = CATapMuteBehavior(rawValue: 0)! // CATapUnmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapStatus == noErr else {
            throw Err.tapCreationFailed(tapStatus)
        }
        tapID = newTapID
        logger.notice("Tap created id=\(newTapID)")

        // 2. Get the tap's UID string.
        var tapUID: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(tapID, &uidAddr, 0, nil, &uidSize, &tapUID)
        guard let tapUIDString = tapUID?.takeRetainedValue() as String? else {
            throw Err.noTapUID
        }
        logger.notice("Tap UID: \(tapUIDString, privacy: .public)")

        // 3. Get the CoreAudio HAL plugin for creating aggregate devices.
        let pluginID = try findAggregateDevicePlugin()
        cachedPluginID = pluginID

        // 4. Create an aggregate device that wraps the tap.
        let aggUID = "com.clipforge.sysaudio.\(UUID().uuidString)"
        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey: tapUIDString,
            kAudioSubTapDriftCompensationKey: false
        ]
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey:        "ClipForge System Audio",
            kAudioAggregateDeviceUIDKey:         aggUID,
            kAudioAggregateDeviceIsPrivateKey:   true,
            kAudioAggregateDeviceSubDeviceListKey: [],
            kAudioAggregateDeviceTapListKey:     [tapEntry],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]

        let cfDesc: CFDictionary = aggDesc as CFDictionary
        var aggID = AudioObjectID(kAudioObjectUnknown)
        var aggSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var createAddr = AudioObjectPropertyAddress(
            mSelector: kAudioPlugInCreateAggregateDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var createStatus = OSStatus(0)
        withUnsafePointer(to: cfDesc) { dPtr in
            createStatus = AudioObjectGetPropertyData(
                pluginID, &createAddr,
                UInt32(MemoryLayout<CFDictionary>.size), UnsafeRawPointer(dPtr),
                &aggSize, &aggID
            )
        }
        guard createStatus == noErr, aggID != kAudioObjectUnknown else {
            throw Err.aggregateDeviceCreationFailed(createStatus)
        }
        aggregateDeviceID = aggID
        logger.notice("Aggregate device created id=\(aggID)")

        // 5. Read the aggregate device's input format.
        var asbd = AudioStreamBasicDescription()
        var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(aggID, &fmtAddr, 0, nil, &fmtSize, &asbd)
        logger.notice("Aggregate format: \(asbd.mSampleRate) Hz \(asbd.mChannelsPerFrame) ch flags=\(asbd.mFormatFlags)")

        // Fallback to 48kHz stereo float32 non-interleaved if format is empty.
        if asbd.mSampleRate == 0 {
            asbd.mSampleRate       = 48_000
            asbd.mFormatID         = kAudioFormatLinearPCM
            asbd.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
            asbd.mBitsPerChannel   = 32
            asbd.mChannelsPerFrame = 2
            asbd.mFramesPerPacket  = 1
            asbd.mBytesPerFrame    = 4
            asbd.mBytesPerPacket   = 4
        }
        capturedASBD = asbd

        // Build an interleaved format description for CMSampleBuffers — IOProc data
        // will always be converted to interleaved before wrapping.
        var interleavedASBD = asbd
        interleavedASBD.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved
        interleavedASBD.mBytesPerFrame  = (asbd.mBitsPerChannel / 8) * asbd.mChannelsPerFrame
        interleavedASBD.mBytesPerPacket = interleavedASBD.mBytesPerFrame

        var fmtDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &interleavedASBD,
                                       layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil,
                                       extensions: nil, formatDescriptionOut: &fmtDesc)
        capturedFmt = fmtDesc

        // 6. Register a direct IOProc on the aggregate device (bypasses AVAudioEngine).
        var procID: AudioDeviceIOProcID?
        let selfRef = Unmanaged.passRetained(self)

        let ioBlock: AudioDeviceIOBlock = { inNow, inInputData, inInputTime, _, _ in
            let capture = Unmanaged<SystemAudioCapture>.fromOpaque(selfRef.toOpaque()).takeUnretainedValue()
            capture.handleIOData(inInputData: inInputData, inInputTime: inInputTime)
        }

        let createProcStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil, ioBlock)
        guard createProcStatus == noErr, let procID else {
            selfRef.release()
            throw Err.cannotSetDevice(createProcStatus)
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggID, procID)
            ioProcID = nil
            selfRef.release()
            throw Err.cannotSetDevice(startStatus)
        }

        // Store selfRef so it can be released on stop.
        objc_setAssociatedObject(self, &associatedSelfRefKey, selfRef, .OBJC_ASSOCIATION_RETAIN)

        logger.notice("SystemAudioCapture running via IOProc")
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown, let proc = ioProcID {
            AudioDeviceStop(aggregateDeviceID, proc)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
            ioProcID = nil

            // Release the retained self ref used by the IOProc block.
            if let selfRef = objc_getAssociatedObject(self, &associatedSelfRefKey) as? Unmanaged<SystemAudioCapture> {
                selfRef.release()
                objc_setAssociatedObject(self, &associatedSelfRefKey, nil, .OBJC_ASSOCIATION_RETAIN)
            }
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            var destroyAddr = AudioObjectPropertyAddress(
                mSelector: kAudioPlugInDestroyAggregateDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let pluginID = cachedPluginID != kAudioObjectUnknown
                ? cachedPluginID
                : (try? findAggregateDevicePlugin()) ?? kAudioObjectUnknown
            if pluginID != kAudioObjectUnknown {
                var devID = aggregateDeviceID
                AudioObjectSetPropertyData(pluginID, &destroyAddr, 0, nil,
                                           UInt32(MemoryLayout<AudioObjectID>.size), &devID)
            }
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            cachedPluginID = AudioObjectID(kAudioObjectUnknown)
        }

        if #available(macOS 14.2, *), tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        capturedFmt = nil
        logger.notice("SystemAudioCapture stopped")
    }

    // MARK: - IOProc handler

    private func handleIOData(inInputData: UnsafePointer<AudioBufferList>,
                               inInputTime: UnsafePointer<AudioTimeStamp>) {
        let asbd = capturedASBD
        guard asbd.mSampleRate > 0, let fmt = capturedFmt else { return }

        let bufList = inInputData.pointee
        guard bufList.mNumberBuffers > 0 else { return }

        let isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(asbd.mChannelsPerFrame)
        let bytesPerSample = Int(asbd.mBitsPerChannel) / 8

        // Determine frame count from the first buffer.
        let buf0 = bufList.mBuffers
        let frameCount: Int
        if isNonInterleaved {
            frameCount = Int(buf0.mDataByteSize) / bytesPerSample
        } else {
            frameCount = Int(buf0.mDataByteSize) / (bytesPerSample * channels)
        }
        guard frameCount > 0 else { return }

        let totalBytes = frameCount * channels * bytesPerSample

        var blockBuf: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: totalBytes,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: totalBytes, flags: 0, blockBufferOut: &blockBuf
        ) == noErr, let blockBuf,
        CMBlockBufferAssureBlockMemory(blockBuf) == noErr else { return }

        var rawPtr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuf, atOffset: 0, lengthAtOffsetOut: nil,
                                         totalLengthOut: nil, dataPointerOut: &rawPtr) == noErr,
              let rawPtr else { return }

        // Convert to interleaved if needed.
        if isNonInterleaved {
            // Non-interleaved: each buffer in the list is one channel.
            let dest = rawPtr.withMemoryRebound(to: Float.self, capacity: frameCount * channels) { $0 }
            withUnsafePointer(to: bufList) { blPtr in
                let buffers = UnsafeBufferPointer<AudioBuffer>(
                    start: UnsafeRawPointer(blPtr).advanced(by: MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers)!).assumingMemoryBound(to: AudioBuffer.self),
                    count: min(channels, Int(bufList.mNumberBuffers))
                )
                for (c, ab) in buffers.enumerated() {
                    guard let src = ab.mData else { continue }
                    let srcFloats = src.assumingMemoryBound(to: Float.self)
                    for f in 0..<frameCount {
                        dest[f * channels + c] = srcFloats[f]
                    }
                }
            }
        } else {
            // Interleaved: copy the single buffer directly.
            if let src = buf0.mData {
                rawPtr.initialize(from: src.assumingMemoryBound(to: Int8.self), count: totalBytes)
            }
        }

        let hostTime = inInputTime.pointee.mHostTime
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let nanos = Double(hostTime) * Double(tb.numer) / Double(tb.denom)
        let pts = CMTime(seconds: nanos / 1_000_000_000, preferredTimescale: 48_000)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
            presentationTimeStamp: pts, decodeTimeStamp: .invalid
        )
        var sampleBuf: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuf, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: fmt,
            sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuf
        ) == noErr, let sampleBuf else { return }

        onAudioSample?(sampleBuf)
    }

    // MARK: - PID → AudioObjectID

    /// Looks up the CoreAudio process object ID for a given POSIX PID.
    private func audioObjectID(forPID pid: pid_t) -> AudioObjectID? {
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var listSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &listSize)
        let count = Int(listSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return nil }

        var processObjIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &listSize, &processObjIDs)

        var pidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for objID in processObjIDs where objID != kAudioObjectUnknown {
            var procPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &procPID)
            if procPID == pid { return objID }
        }
        return nil
    }

    // MARK: - Plugin lookup

    /// Finds the CoreAudio HAL plugin that supports aggregate device creation.
    /// First tries the bundle ID approach (macOS 14.2-15), then falls back to
    /// enumerating all plugins (works on macOS 26+).
    private func findAggregateDevicePlugin() throws -> AudioObjectID {
        // Try bundle ID approach first.
        var pluginID = AudioObjectID(kAudioObjectUnknown)
        var pluginSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var pluginAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyPlugInForBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let bundleID: CFString = "com.apple.audio.CoreAudio" as CFString
        withUnsafePointer(to: bundleID) { bPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &pluginAddr,
                UInt32(MemoryLayout<CFString>.size), UnsafeRawPointer(bPtr),
                &pluginSize, &pluginID
            )
        }
        if pluginID != kAudioObjectUnknown {
            logger.notice("Plugin found via bundle ID: \(pluginID)")
            return pluginID
        }

        // Fallback: enumerate all plugins, find one supporting aggregate device creation.
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyPlugInList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var listSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &listSize)
        let count = Int(listSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { throw Err.noPlugin }

        var plugins = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &listSize, &plugins)
        logger.notice("Enumerating \(count) plugins for aggregate device support")

        var aggCheckAddr = AudioObjectPropertyAddress(
            mSelector: kAudioPlugInCreateAggregateDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for pID in plugins where pID != kAudioObjectUnknown {
            if AudioObjectHasProperty(pID, &aggCheckAddr) {
                logger.notice("Plugin found via enumeration: \(pID)")
                return pID
            }
        }
        throw Err.noPlugin
    }

    // MARK: - Errors

    enum Err: Error, LocalizedError {
        case tapCreationFailed(OSStatus)
        case noTapUID
        case noPlugin
        case aggregateDeviceCreationFailed(OSStatus)
        case noAudioUnit
        case cannotSetDevice(OSStatus)
        case badFormat

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let s):            return "Tap creation failed: \(s)"
            case .noTapUID:                            return "Could not read tap UID"
            case .noPlugin:                            return "CoreAudio plugin not found"
            case .aggregateDeviceCreationFailed(let s): return "Aggregate device failed: \(s)"
            case .noAudioUnit:                         return "No audio unit"
            case .cannotSetDevice(let s):              return "Cannot set device: \(s)"
            case .badFormat:                           return "Bad audio format"
            }
        }
    }
}

private var associatedSelfRefKey: UInt8 = 0
