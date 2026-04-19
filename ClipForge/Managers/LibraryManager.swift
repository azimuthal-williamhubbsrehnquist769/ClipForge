import Foundation
import Combine
import AppKit

/// Manages the on-disk clip library: persisting metadata, enumerating files,
/// and keeping the in-memory model in sync with disk.
@MainActor
final class LibraryManager: ObservableObject {

    @Published var clips: [Clip] = []
    @Published var lastError: String?

    private let settings: SettingsStore
    private var metadataURL: URL { settings.libraryPath.appendingPathComponent(".metadata.json") }

    // MARK: - Init

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Load

    func load() async {
        await createLibraryDirectoryIfNeeded()
        do {
            let data = try Data(contentsOf: metadataURL)
            var stored = try JSONDecoder().decode([Clip].self, from: data)
            // Remove entries whose files no longer exist
            stored = stored.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            clips = stored
        } catch {
            // First launch or corrupt metadata - scan directory
            await scanLibraryDirectory()
        }
    }

    // MARK: - Save clip from export

    /// Moves an exported temp clip into the library and records metadata.
    func addClip(
        from tempURL: URL,
        title: String,
        duration: TimeInterval,
        appName: String?
    ) async throws -> Clip {
        let destination = settings.libraryPath
            .appendingPathComponent(sanitizeFilename(title) + "_\(Int(Date().timeIntervalSince1970)).mp4")

        try FileManager.default.moveItem(at: tempURL, to: destination)

        // File size
        let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let fileSize = attrs?[.size] as? Int64

        // Thumbnail
        let thumbURL = try? await ClipExportManager.generateThumbnail(for: destination)

        let clip = Clip(
            title: title,
            url: destination,
            duration: duration,
            appName: appName,
            thumbnailURL: thumbURL,
            fileSize: fileSize
        )

        clips.insert(clip, at: 0)
        await persistMetadata()
        return clip
    }

    // MARK: - Mutations

    func rename(_ clip: Clip, to newTitle: String) async {
        guard let idx = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[idx].title = newTitle
        await persistMetadata()
    }

    func toggleFavorite(_ clip: Clip) async {
        guard let idx = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[idx].isFavorite.toggle()
        await persistMetadata()
    }

    func delete(_ clip: Clip) async {
        try? FileManager.default.removeItem(at: clip.url)
        if let thumbURL = clip.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        clips.removeAll { $0.id == clip.id }
        await persistMetadata()
    }

    func revealInFinder(_ clip: Clip) {
        NSWorkspace.shared.activateFileViewerSelecting([clip.url])
    }

    // MARK: - Search / filter

    func clips(matching query: String, favoritesOnly: Bool) -> [Clip] {
        clips.filter { clip in
            let matchesQuery = query.isEmpty
                || clip.title.localizedCaseInsensitiveContains(query)
                || (clip.appName?.localizedCaseInsensitiveContains(query) ?? false)
            let matchesFav = !favoritesOnly || clip.isFavorite
            return matchesQuery && matchesFav
        }
    }

    // MARK: - Private helpers

    private func createLibraryDirectoryIfNeeded() async {
        do {
            try FileManager.default.createDirectory(at: settings.libraryPath, withIntermediateDirectories: true)
        } catch {
            lastError = "Cannot create library directory: \(error.localizedDescription)"
        }
    }

    private func scanLibraryDirectory() async {
        let dir = settings.libraryPath
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [
            .fileSizeKey, .creationDateKey
        ], options: [.skipsHiddenFiles]) else { return }

        var scanned: [Clip] = []
        for url in contents where url.pathExtension.lowercased() == "mp4" {
            let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = attrs?.fileSize.map { Int64($0) }
            let date = attrs?.creationDate ?? Date()
            // Attempt thumbnail lookup
            let thumbURL = url.deletingLastPathComponent()
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_thumb.jpg")
            scanned.append(Clip(
                title: url.deletingPathExtension().lastPathComponent,
                url: url,
                duration: 0,
                createdAt: date,
                thumbnailURL: FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : nil,
                fileSize: size
            ))
        }

        clips = scanned.sorted { $0.createdAt > $1.createdAt }
        await persistMetadata()
    }

    private func persistMetadata() async {
        do {
            let data = try JSONEncoder().encode(clips)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            lastError = "Could not save library metadata: \(error.localizedDescription)"
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}
