import Foundation
import Combine
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {

    // MARK: - Published

    @Published var searchQuery: String = ""
    @Published var showFavoritesOnly: Bool = false
    @Published var sortOrder: SortOrder = .dateDescending
    @Published var selectedClip: Clip?
    @Published var clipToRename: Clip?
    @Published var clipToDelete: Clip?
    @Published var clipToTrim: Clip?
    @Published var isExportingTrim: Bool = false
    @Published var trimProgress: Double = 0
    @Published var lastError: String?

    // MARK: - Dependencies

    private let libraryManager: LibraryManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(libraryManager: LibraryManager) {
        self.libraryManager = libraryManager
    }

    // MARK: - Derived list

    var filteredClips: [Clip] {
        let base = libraryManager.clips(matching: searchQuery, favoritesOnly: showFavoritesOnly)
        return base.sorted(by: sortOrder.comparator)
    }

    // MARK: - Actions

    func toggleFavorite(_ clip: Clip) {
        Task { await libraryManager.toggleFavorite(clip) }
    }

    func delete(_ clip: Clip) {
        Task {
            if selectedClip?.id == clip.id { selectedClip = nil }
            await libraryManager.delete(clip)
        }
    }

    func rename(_ clip: Clip, to title: String) {
        Task { await libraryManager.rename(clip, to: title) }
    }

    func revealInFinder(_ clip: Clip) {
        libraryManager.revealInFinder(clip)
    }

    func exportTrim(
        clip: Clip,
        startTime: TimeInterval,
        endTime: TimeInterval,
        outputURL: URL
    ) {
        guard !isExportingTrim else { return }
        isExportingTrim = true
        trimProgress = 0

        Task {
            do {
                try await ClipExportManager.exportTrimmed(
                    sourceURL: clip.url,
                    startTime: startTime,
                    endTime: endTime,
                    to: outputURL,
                    progressHandler: { [weak self] p in
                        Task { @MainActor [weak self] in self?.trimProgress = p }
                    }
                )
                // Add trimmed clip to library
                let duration = endTime - startTime
                _ = try await libraryManager.addClip(
                    from: outputURL,
                    title: clip.title + " (trimmed)",
                    duration: duration,
                    appName: clip.appName
                )
            } catch {
                lastError = "Trim export failed: \(error.localizedDescription)"
            }
            isExportingTrim = false
        }
    }

    func copyToClipboard(_ clip: Clip) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([clip.url as NSURL])
    }

    // MARK: - Sort order

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateDescending = "Newest First"
        case dateAscending  = "Oldest First"
        case titleAscending = "Title A–Z"
        case duration       = "Duration"

        var id: String { rawValue }

        var comparator: (Clip, Clip) -> Bool {
            switch self {
            case .dateDescending: return { $0.createdAt > $1.createdAt }
            case .dateAscending:  return { $0.createdAt < $1.createdAt }
            case .titleAscending: return { $0.title.localizedCompare($1.title) == .orderedAscending }
            case .duration:       return { $0.duration > $1.duration }
            }
        }
    }
}
