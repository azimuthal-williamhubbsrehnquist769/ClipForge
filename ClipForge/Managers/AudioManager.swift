import Foundation
import AVFoundation
import CoreMedia
import Combine

/// Manages microphone capture using AVCaptureSession.
/// Produces PCM audio CMSampleBuffers routed into the ReplayBuffer.
@MainActor
final class AudioManager: NSObject, ObservableObject {

    @Published var isMicMuted: Bool = false
    @Published var isMicActive: Bool = false
    @Published var lastError: String?

    // Called on the sample delivery queue; route to ReplayBuffer.appendAudio
    var onAudioSample: ((CMSampleBuffer) -> Void)?

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let sampleQueue = DispatchQueue(label: "com.clipforge.audio.mic", qos: .userInteractive)

    // MARK: - Start / stop

    func startMicCapture() async {
        guard !isMicActive else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { lastError = "Microphone permission denied."; return }
        default:
            lastError = "Microphone permission denied. Enable in System Settings > Privacy > Microphone."
            return
        }

        do {
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .audio) else {
                throw AudioError.noMicrophoneFound
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw AudioError.cannotAddInput }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            guard session.canAddOutput(output) else { throw AudioError.cannotAddOutput }
            output.setSampleBufferDelegate(self, queue: sampleQueue)
            session.addOutput(output)

            session.startRunning()
            captureSession = session
            audioOutput = output
            isMicActive = true
            lastError = nil
        } catch {
            lastError = "Mic error: \(error.localizedDescription)"
        }
    }

    func stopMicCapture() {
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        isMicActive = false
    }

    func toggleMute() {
        isMicMuted.toggle()
    }

    // MARK: - Errors

    enum AudioError: Error, LocalizedError {
        case noMicrophoneFound
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noMicrophoneFound: return "No microphone found."
            case .cannotAddInput:   return "Cannot add microphone input."
            case .cannotAddOutput:  return "Cannot add audio output."
            }
        }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension AudioManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Drop samples when muted
        Task { @MainActor [weak self] in
            guard let self, !self.isMicMuted else { return }
            self.onAudioSample?(sampleBuffer)
        }
    }
}
