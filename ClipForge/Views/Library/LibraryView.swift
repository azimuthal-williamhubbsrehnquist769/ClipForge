import SwiftUI

struct LibraryView: View {

    @EnvironmentObject var libraryVM: LibraryViewModel

    @State private var showRenameDialog = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .navigationTitle("Library")
        .alert("Rename Clip", isPresented: $showRenameDialog, presenting: libraryVM.clipToRename) { clip in
            TextField("Title", text: $renameText)
            Button("Rename") { libraryVM.rename(clip, to: renameText) }
            Button("Cancel", role: .cancel) {}
        } message: { clip in
            Text("Rename \"\(clip.title)\"")
        }
        .confirmationDialog(
            "Delete Clip?",
            isPresented: $showDeleteConfirm,
            presenting: libraryVM.clipToDelete
        ) { clip in
            Button("Delete", role: .destructive) { libraryVM.delete(clip) }
            Button("Cancel", role: .cancel) {}
        } message: { clip in
            Text("\"\(clip.title)\" will be permanently deleted.")
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clips…", text: $libraryVM.searchQuery)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
            if !libraryVM.searchQuery.isEmpty {
                Button(action: { libraryVM.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)

        HStack {
            Toggle(isOn: $libraryVM.showFavoritesOnly) {
                Label("Favorites", systemImage: "star.fill")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)

            Spacer()

            Picker("Sort", selection: $libraryVM.sortOrder) {
                ForEach(LibraryViewModel.SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let clips = libraryVM.filteredClips
        if clips.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(clips) { clip in
                        ClipRowView(clip: clip)
                            .contentShape(Rectangle())
                            .onTapGesture { libraryVM.selectedClip = clip }
                            .background(
                                libraryVM.selectedClip?.id == clip.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contextMenu { contextMenu(for: clip) }
                    }
                }
                .padding(6)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "film.stack",
            title: libraryVM.searchQuery.isEmpty ? "No Clips Yet" : "No Results",
            subtitle: libraryVM.searchQuery.isEmpty
                ? "Start recording and save a clip\nto see it here."
                : "Try a different search term."
        )
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for clip: Clip) -> some View {
        Button(action: { libraryVM.selectedClip = clip }) {
            Label("Open", systemImage: "eye")
        }
        Button(action: { libraryVM.toggleFavorite(clip) }) {
            Label(clip.isFavorite ? "Unfavorite" : "Favorite", systemImage: clip.isFavorite ? "star.slash" : "star")
        }
        Divider()
        Button(action: {
            renameText = clip.title
            libraryVM.clipToRename = clip
            showRenameDialog = true
        }) {
            Label("Rename…", systemImage: "pencil")
        }
        Button(action: { libraryVM.revealInFinder(clip) }) {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Button(action: { libraryVM.copyToClipboard(clip) }) {
            Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
        }
        Divider()
        Button(role: .destructive, action: {
            libraryVM.clipToDelete = clip
            showDeleteConfirm = true
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Clip row

struct ClipRowView: View {
    let clip: Clip

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(url: clip.thumbnailURL, size: CGSize(width: 64, height: 36))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(clip.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if clip.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 8) {
                    if let app = clip.appName {
                        Text(app)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(clip.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(clip.relativeDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

#Preview {
    LibraryView()
        .environmentObject({
            let vm = LibraryViewModel(libraryManager: LibraryManager(settings: .shared))
            return vm
        }())
        .frame(width: 300, height: 500)
}
