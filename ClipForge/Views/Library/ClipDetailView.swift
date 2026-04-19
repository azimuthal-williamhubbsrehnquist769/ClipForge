import SwiftUI
import AVKit

struct ClipDetailView: View {

    let clip: Clip

    @EnvironmentObject var libraryVM: LibraryViewModel
    @State private var player: AVPlayer?
    @State private var showTrimSheet = false
    @State private var showRenameDialog = false
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Video player
            videoPlayer
                .background(.black)

            Divider()

            // Metadata + actions
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    actionsSection
                }
                .padding(20)
            }
        }
        .navigationTitle(clip.title)
        .navigationSubtitle(clip.formattedDuration)
        .onAppear { setupPlayer() }
        .onDisappear { player?.pause() }
        .onChange(of: clip.id) { setupPlayer() }
        .sheet(isPresented: $showTrimSheet) {
            TrimView(clip: clip)
                .environmentObject(libraryVM)
        }
        .alert("Rename Clip", isPresented: $showRenameDialog) {
            TextField("Title", text: $renameText)
            Button("Rename") { libraryVM.rename(clip, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Video player

    private var videoPlayer: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else {
                Color.black
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            grid {
                detailRow("File", clip.url.lastPathComponent)
                if let app = clip.appName { detailRow("App", app) }
                detailRow("Duration", clip.formattedDuration)
                detailRow("Created", clip.formattedDate)
                if let size = clip.formattedFileSize as String? { detailRow("Size", size) }
            }
        }
    }

    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            content()
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                actionButton("Trim", icon: "scissors") { showTrimSheet = true }
                actionButton("Rename", icon: "pencil") {
                    renameText = clip.title
                    showRenameDialog = true
                }
                actionButton(clip.isFavorite ? "Unfavorite" : "Favorite",
                             icon: clip.isFavorite ? "star.slash" : "star") {
                    libraryVM.toggleFavorite(clip)
                }
                actionButton("Reveal", icon: "folder") {
                    libraryVM.revealInFinder(clip)
                }
                actionButton("Copy", icon: "doc.on.clipboard") {
                    libraryVM.copyToClipboard(clip)
                }
                actionButton("Delete", icon: "trash", role: .destructive) {
                    libraryVM.clipToDelete = clip
                    libraryVM.selectedClip = nil
                }
            }
        }
    }

    private func actionButton(
        _ label: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Private

    private func setupPlayer() {
        player = AVPlayer(url: clip.url)
    }
}

#Preview {
    ClipDetailView(clip: .preview)
        .environmentObject(LibraryViewModel(libraryManager: LibraryManager(settings: .shared)))
        .frame(width: 600, height: 500)
}
