import Foundation

/// A recorded video clip stored in the local library.
struct Clip: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var url: URL
    var duration: TimeInterval
    var createdAt: Date = Date()
    /// Name of the app/game that was captured, if detectable.
    var appName: String?
    var isFavorite: Bool = false
    var thumbnailURL: URL?
    var fileSize: Int64?
    var tags: [String] = []

    // MARK: - Computed helpers

    var formattedDuration: String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        guard let size = fileSize else { return "–" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: createdAt)
    }

    var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: createdAt, relativeTo: Date())
    }
}

// MARK: - Preview / mock data

extension Clip {
    static let preview = Clip(
        id: UUID(),
        title: "Epic Play",
        url: URL(fileURLWithPath: "/tmp/clip.mp4"),
        duration: 47,
        createdAt: Date().addingTimeInterval(-300),
        appName: "Minecraft",
        isFavorite: true,
        thumbnailURL: nil,
        fileSize: 12_400_000
    )

    static let previews: [Clip] = [
        Clip(id: UUID(), title: "Ace Round", url: URL(fileURLWithPath: "/tmp/1.mp4"),
             duration: 30, createdAt: Date().addingTimeInterval(-3600),
             appName: "CS2", isFavorite: false, fileSize: 8_000_000),
        Clip(id: UUID(), title: "Epic Play", url: URL(fileURLWithPath: "/tmp/2.mp4"),
             duration: 60, createdAt: Date().addingTimeInterval(-7200),
             appName: "Minecraft", isFavorite: true, fileSize: 15_000_000),
        Clip(id: UUID(), title: "Clutch Win", url: URL(fileURLWithPath: "/tmp/3.mp4"),
             duration: 15, createdAt: Date().addingTimeInterval(-86400),
             appName: "Valorant", isFavorite: false, fileSize: 4_200_000),
    ]
}
