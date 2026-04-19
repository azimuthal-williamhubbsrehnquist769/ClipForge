import SwiftUI
import AVKit

/// Lightweight in/out trim UI. Lets the user drag start/end points,
/// then exports the trimmed section as a new clip.
struct TrimView: View {

    let clip: Clip

    @EnvironmentObject var libraryVM: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var duration: TimeInterval = 0
    @State private var startTime: TimeInterval = 0
    @State private var endTime: TimeInterval = 0
    @State private var player: AVPlayer?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Trim Clip")
                .font(.headline)

            // Preview
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .cornerRadius(8)
                    .frame(maxHeight: 270)
            }

            // Timeline scrubber
            if duration > 0 {
                trimTimeline
                timeLabels
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                if libraryVM.isExportingTrim {
                    ProgressView(value: libraryVM.trimProgress)
                        .frame(width: 120)
                } else {
                    Button("Export Trimmed Clip") {
                        exportTrimmedClip()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(endTime <= startTime)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 380)
        .onAppear { setup() }
        .onChange(of: libraryVM.isExportingTrim) { _, exporting in
            if !exporting { dismiss() }
        }
    }

    // MARK: - Timeline

    private var trimTimeline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 6)

                // Selected range
                let startFrac = startTime / duration
                let endFrac   = endTime / duration
                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: (endFrac - startFrac) * w, height: 6)
                    .offset(x: startFrac * w)

                // Start handle
                handle(at: startTime / duration * w)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        startTime = max(0, min(endTime - 0.5, v.location.x / w * duration))
                        seekPlayer(to: startTime)
                    })

                // End handle
                handle(at: endTime / duration * w)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        endTime = min(duration, max(startTime + 0.5, v.location.x / w * duration))
                        seekPlayer(to: endTime)
                    })
            }
        }
        .frame(height: 32)
    }

    private func handle(at x: CGFloat) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 20, height: 20)
            .shadow(radius: 2)
            .offset(x: x - 10, y: -7)
    }

    private var timeLabels: some View {
        HStack {
            Text(formatTime(startTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text("Duration: \(formatTime(endTime - startTime))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatTime(endTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Private helpers

    private func setup() {
        let asset = AVURLAsset(url: clip.url)
        player = AVPlayer(url: clip.url)
        Task {
            if let d = try? await asset.load(.duration) {
                duration = d.seconds
                endTime = duration
            }
        }
    }

    private func seekPlayer(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    private func exportTrimmedClip() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = clip.title + "_trimmed.mp4"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            libraryVM.exportTrim(clip: clip, startTime: startTime, endTime: endTime, outputURL: url)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%01d", m, s, ms)
    }
}

#Preview {
    TrimView(clip: .preview)
        .environmentObject(LibraryViewModel(libraryManager: LibraryManager(settings: .shared)))
}
