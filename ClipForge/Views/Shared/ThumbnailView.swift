import SwiftUI
import AVFoundation

/// Loads and displays a video thumbnail.
/// Falls back to a generic placeholder if loading fails or thumbnailURL is nil.
struct ThumbnailView: View {

    let url: URL?
    let size: CGSize

    @State private var image: NSImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: min(size.width, size.height) * 0.35))
                        .foregroundStyle(.quaternary)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else { image = nil; return }

        // Try to load a pre-generated thumbnail JPEG
        if let img = NSImage(contentsOf: url) {
            image = img
            return
        }
        image = nil
    }
}

// MARK: - Preview

#Preview {
    HStack {
        ThumbnailView(url: nil, size: CGSize(width: 160, height: 90))
            .cornerRadius(6)
        ThumbnailView(url: nil, size: CGSize(width: 64, height: 36))
            .cornerRadius(4)
    }
    .padding()
}
