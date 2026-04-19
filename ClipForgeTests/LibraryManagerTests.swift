import XCTest
@testable import ClipForge

final class LibraryManagerTests: XCTestCase {

    private var manager: LibraryManager!
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        await MainActor.run { SettingsStore.shared.libraryPath = tempDir }
        manager = await MainActor.run { LibraryManager(settings: SettingsStore.shared) }
        await manager.load()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Tests

    @MainActor func testInitiallyEmpty() {
        XCTAssertTrue(manager.clips.isEmpty)
    }

    @MainActor func testRenameClip() async {
        insertClip(title: "Original")
        let clip = manager.clips.first!
        await manager.rename(clip, to: "Renamed")
        XCTAssertEqual(manager.clips.first?.title, "Renamed")
    }

    @MainActor func testToggleFavorite() async {
        insertClip(title: "Fav test")
        let clip = manager.clips.first!
        XCTAssertFalse(clip.isFavorite)
        await manager.toggleFavorite(clip)
        XCTAssertTrue(manager.clips.first!.isFavorite)
        await manager.toggleFavorite(manager.clips.first!)
        XCTAssertFalse(manager.clips.first!.isFavorite)
    }

    @MainActor func testDeleteClip() async {
        insertClip(title: "Delete me")
        let clip = manager.clips.first!
        await manager.delete(clip)
        XCTAssertTrue(manager.clips.isEmpty)
    }

    @MainActor func testSearchFiltering() {
        insertClip(title: "CS2 Ace")
        insertClip(title: "Minecraft Clip")
        let results = manager.clips(matching: "CS2", favoritesOnly: false)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "CS2 Ace")
    }

    @MainActor func testFavoritesFilter() async {
        insertClip(title: "Fav")
        insertClip(title: "Not fav")
        await manager.toggleFavorite(manager.clips[0])
        let favOnly = manager.clips(matching: "", favoritesOnly: true)
        XCTAssertEqual(favOnly.count, 1)
    }

    @MainActor func testEmptySearchReturnsAll() {
        insertClip(title: "A")
        insertClip(title: "B")
        let all = manager.clips(matching: "", favoritesOnly: false)
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Helpers

    @MainActor
    private func insertClip(title: String) {
        let url = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let clip = Clip(title: title, url: url, duration: 30)
        manager.clips_testInsert(clip)
    }
}

// MARK: - Test-only extension

extension LibraryManager {
    @MainActor
    func clips_testInsert(_ clip: Clip) {
        clips.append(clip)
    }
}
