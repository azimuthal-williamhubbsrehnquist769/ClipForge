import Foundation

/// User-configurable recording preferences.
struct RecordingSettings: Codable, Equatable {
    var replayDuration: ReplayDuration = .sixty
    var fps: FrameRate = .thirty
    var resolution: ResolutionPreset = .native
    var capturesMicrophone: Bool = false
    var capturesSystemAudio: Bool = true
    var encoder: VideoEncoder = .h264
    var bitrate: BitrateSetting = .medium
}

// MARK: - Enumerations

enum ReplayDuration: Int, Codable, CaseIterable, Identifiable {
    case ten = 10
    case fifteen = 15
    case thirty = 30
    case fortyfive = 45
    case sixty = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .ten:      return "10s"
        case .fifteen:  return "15s"
        case .thirty:   return "30s"
        case .fortyfive: return "45s"
        case .sixty:    return "1m"
        }
    }

    var seconds: TimeInterval { TimeInterval(rawValue) }
}

enum FrameRate: Int, Codable, CaseIterable, Identifiable {
    case twenty = 20
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue) FPS" }
}

enum ResolutionPreset: String, Codable, CaseIterable, Identifiable {
    case native
    case p1080 = "1080p"
    case p720 = "720p"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: return "Native"
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }

    var dimensions: CGSize? {
        switch self {
        case .native: return nil
        case .p1080: return CGSize(width: 1920, height: 1080)
        case .p720: return CGSize(width: 1280, height: 720)
        }
    }
}

enum VideoEncoder: String, Codable, CaseIterable, Identifiable {
    case h264 = "H.264"
    case hevc = "HEVC (H.265)"

    var id: String { rawValue }
    var label: String { rawValue }
}

enum RecordingMode: String, Codable, CaseIterable, Identifiable {
    case clipBuffer  = "clipBuffer"
    case fullSession = "fullSession"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clipBuffer:  return "Clip Buffer"
        case .fullSession: return "Full Session"
        }
    }

    var icon: String {
        switch self {
        case .clipBuffer:  return "timer"
        case .fullSession: return "record.circle.fill"
        }
    }
}

enum AudioScope: String, Codable, CaseIterable, Identifiable {
    case desktop    = "desktop"
    case windowOnly = "windowOnly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .desktop:    return "Desktop"
        case .windowOnly: return "Window Only"
        }
    }

    var icon: String {
        switch self {
        case .desktop:    return "speaker.wave.2"
        case .windowOnly: return "app.badge"
        }
    }
}

enum BitrateSetting: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Bits per second
    var bitsPerSecond: Int {
        switch self {
        case .low:    return 4_000_000
        case .medium: return 8_000_000
        case .high:   return 16_000_000
        }
    }

    var qualityLabel: String {
        switch self {
        case .low:    return "Low · 4 Mbps"
        case .medium: return "Medium · 8 Mbps"
        case .high:   return "High · 16 Mbps"
        }
    }

    /// Approximate RAM used by the compressed ring buffer for the given duration.
    func ramEstimate(for duration: ReplayDuration) -> String {
        // Compressed video + ~320 kbps audio overhead
        let audioBitsPerSec = 320_000
        let totalBits = Double(bitsPerSecond + audioBitsPerSec) * duration.seconds
        let mb = totalBits / 8 / 1_048_576
        return mb >= 1000
            ? String(format: "~%.1f GB RAM", mb / 1024)
            : String(format: "~%.0f MB RAM", mb)
    }
}
