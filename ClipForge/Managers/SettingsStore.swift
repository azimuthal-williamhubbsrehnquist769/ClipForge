import Foundation
import Combine
import SwiftUI

/// Persists all user preferences using UserDefaults + JSON encoding for complex types.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // MARK: - Simple @AppStorage-backed properties (surfaced via @Published for Combine use)

    @Published var replayDuration: ReplayDuration {
        didSet { defaults.set(replayDuration.rawValue, forKey: Keys.replayDuration) }
    }

    @Published var fps: FrameRate {
        didSet { defaults.set(fps.rawValue, forKey: Keys.fps) }
    }

    @Published var resolution: ResolutionPreset {
        didSet { defaults.set(resolution.rawValue, forKey: Keys.resolution) }
    }

    @Published var capturesMicrophone: Bool {
        didSet { defaults.set(capturesMicrophone, forKey: Keys.capturesMicrophone) }
    }

    @Published var capturesSystemAudio: Bool {
        didSet { defaults.set(capturesSystemAudio, forKey: Keys.capturesSystemAudio) }
    }

    @Published var audioScope: AudioScope {
        didSet { defaults.set(audioScope.rawValue, forKey: Keys.audioScope) }
    }

    @Published var recordingMode: RecordingMode {
        didSet { defaults.set(recordingMode.rawValue, forKey: Keys.recordingMode) }
    }

    @Published var encoder: VideoEncoder {
        didSet { defaults.set(encoder.rawValue, forKey: Keys.encoder) }
    }

    @Published var bitrate: BitrateSetting {
        didSet { defaults.set(bitrate.rawValue, forKey: Keys.bitrate) }
    }

    // MARK: - Library

    @Published var libraryPath: URL {
        didSet { defaults.set(libraryPath.path, forKey: Keys.libraryPath) }
    }

    // MARK: - Hotkeys (stored as [modifiers, keyCode] pairs)

    @Published var saveClipHotkey: HotkeyBinding {
        didSet { saveHotkey(saveClipHotkey, key: Keys.saveClipHotkey) }
    }

    @Published var startStopHotkey: HotkeyBinding {
        didSet { saveHotkey(startStopHotkey, key: Keys.startStopHotkey) }
    }

    @Published var muteMicHotkey: HotkeyBinding {
        didSet { saveHotkey(muteMicHotkey, key: Keys.muteMicHotkey) }
    }

    @Published var openAppHotkey: HotkeyBinding {
        didSet { saveHotkey(openAppHotkey, key: Keys.openAppHotkey) }
    }

    // MARK: - Onboarding

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Private

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let replayDuration = "replayDuration"
        static let fps = "fps"
        static let resolution = "resolution"
        static let capturesMicrophone = "capturesMicrophone"
        static let capturesSystemAudio = "capturesSystemAudio"
        static let audioScope = "audioScope"
        static let recordingMode = "recordingMode"
        static let encoder = "encoder"
        static let bitrate = "bitrate"
        static let libraryPath = "libraryPath"
        static let saveClipHotkey = "saveClipHotkey"
        static let startStopHotkey = "startStopHotkey"
        static let muteMicHotkey = "muteMicHotkey"
        static let openAppHotkey = "openAppHotkey"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private init() {
        let d = UserDefaults.standard

        replayDuration = ReplayDuration(rawValue: d.integer(forKey: Keys.replayDuration)) ?? .thirty
        fps = FrameRate(rawValue: d.integer(forKey: Keys.fps)) ?? .thirty
        resolution = ResolutionPreset(rawValue: d.string(forKey: Keys.resolution) ?? "") ?? .native
        capturesMicrophone = d.bool(forKey: Keys.capturesMicrophone)
        capturesSystemAudio = d.object(forKey: Keys.capturesSystemAudio) as? Bool ?? true
        audioScope = AudioScope(rawValue: d.string(forKey: Keys.audioScope) ?? "") ?? .desktop
        recordingMode = RecordingMode(rawValue: d.string(forKey: Keys.recordingMode) ?? "") ?? .clipBuffer
        encoder = VideoEncoder(rawValue: d.string(forKey: Keys.encoder) ?? "") ?? .h264
        bitrate = BitrateSetting(rawValue: d.string(forKey: Keys.bitrate) ?? "") ?? .medium
        hasCompletedOnboarding = d.bool(forKey: Keys.hasCompletedOnboarding)

        if let path = d.string(forKey: Keys.libraryPath) {
            libraryPath = URL(fileURLWithPath: path)
        } else {
            libraryPath = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ClipForge", isDirectory: true)
        }

        // Inline hotkey decode to avoid calling self.loadHotkey before init completes
        func loadKey(_ key: String, default binding: HotkeyBinding) -> HotkeyBinding {
            guard let data = d.data(forKey: key),
                  let h = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else { return binding }
            return h
        }
        saveClipHotkey  = loadKey(Keys.saveClipHotkey,  default: HotkeyBinding(modifiers: [.command, .shift], keyCode: 3))
        startStopHotkey = loadKey(Keys.startStopHotkey, default: HotkeyBinding(modifiers: [.command, .shift], keyCode: 15))
        muteMicHotkey   = loadKey(Keys.muteMicHotkey,   default: HotkeyBinding(modifiers: [.command, .shift], keyCode: 46))
        openAppHotkey   = loadKey(Keys.openAppHotkey,   default: HotkeyBinding(modifiers: [.command, .shift], keyCode: 38))
    }

    // MARK: - Hotkey serialisation helpers

    private func loadHotkey(key: String) -> HotkeyBinding? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    private func saveHotkey(_ binding: HotkeyBinding, key: String) {
        if let data = try? JSONEncoder().encode(binding) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - HotkeyBinding

struct HotkeyBinding: Codable, Equatable {
    var modifiers: NSEvent.ModifierFlags
    var keyCode: UInt16

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    // Encode as (modifiers rawValue, keyCode)
    enum CodingKeys: String, CodingKey { case modifiers, keyCode }

    init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawMods = try c.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawMods)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modifiers.rawValue, forKey: .modifiers)
        try c.encode(keyCode, forKey: .keyCode)
    }
}

private func keyCodeToString(_ keyCode: UInt16) -> String {
    // Carbon kVK_* virtual key codes
    let map: [UInt16: String] = [
        // Letters
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".",
        // Numbers & symbols
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 33: "[", 50: "`",
        // Whitespace / control
        48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        // Arrow keys
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // Function keys
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 115: "Home", 116: "PgUp", 117: "⌦", 118: "F4",
        119: "End", 120: "F2", 121: "PgDn", 122: "F1",
    ]
    return map[keyCode] ?? "(\(keyCode))"
}
