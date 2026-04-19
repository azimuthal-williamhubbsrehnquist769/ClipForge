import SwiftUI

// MARK: - Banner view

/// Non-modal slide-in banner shown after a clip is copied to the clipboard.
/// Gives the user the chance to also save it to the library, or discard the temp file.
struct ClipSaveBanner: View {

    let clip: PendingClip
    let onSaveToLibrary: () -> Void
    let onDiscard: () -> Void

    @State private var visible = false
    @State private var autoDismissTask: Task<Void, Never>?

    /// Seconds before the banner auto-dismisses and discards the temp file.
    private let autoDismissSeconds: Int = 10

    @State private var secondsRemaining: Int = 10

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text("Clip copied to clipboard")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(clip.title)
                        .lineLimit(1)
                    Text("·")
                    Text(clip.formattedDuration)
                    if let app = clip.appName {
                        Text("·")
                        Text(app)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Countdown ring
            countdownRing

            Divider().frame(height: 28)

            // Actions
            HStack(spacing: 8) {
                Button("Save to Library") {
                    cancelAutoDismiss()
                    onSaveToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Discard") {
                    cancelAutoDismiss()
                    onDiscard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .offset(y: visible ? 0 : 120)
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                visible = true
            }
            startAutoDismiss()
        }
    }

    // MARK: - Countdown ring

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(secondsRemaining) / CGFloat(autoDismissSeconds))
                .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: secondsRemaining)
            Text("\(secondsRemaining)")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Auto-dismiss

    private func startAutoDismiss() {
        secondsRemaining = autoDismissSeconds
        autoDismissTask = Task {
            for remaining in stride(from: autoDismissSeconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run { secondsRemaining = remaining }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.25)) { visible = false }
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run { onDiscard() }
        }
    }

    private func cancelAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        withAnimation(.easeIn(duration: 0.2)) { visible = false }
    }
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.1).ignoresSafeArea()
        ClipSaveBanner(
            clip: PendingClip(
                url: URL(fileURLWithPath: "/tmp/clip.mp4"),
                title: "CS2 Ace Round",
                duration: 47,
                appName: "CS2"
            ),
            onSaveToLibrary: {},
            onDiscard: {}
        )
    }
    .frame(width: 620, height: 200)
}
