import SwiftUI

struct CaptureSettingsView: View {

    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Replay Buffer") {
                Picker("Clip Length", selection: $settings.replayDuration) {
                    ForEach(ReplayDuration.allCases) { dur in
                        Text(dur.label).tag(dur)
                    }
                }
                .pickerStyle(.segmented)

                Text("How far back \"Save Clip\" reaches when you press the hotkey.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Frame Rate") {
                Picker("FPS", selection: $settings.fps) {
                    ForEach(FrameRate.allCases) { fps in
                        Text(fps.label).tag(fps)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Resolution") {
                Picker("Resolution", selection: $settings.resolution) {
                    ForEach(ResolutionPreset.allCases) { res in
                        Text(res.label).tag(res)
                    }
                }
                .pickerStyle(.segmented)

                if settings.resolution == .native {
                    Text("Captures at the source's native resolution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Encoding") {
                Picker("Codec", selection: $settings.encoder) {
                    ForEach(VideoEncoder.allCases) { enc in
                        Text(enc.label).tag(enc)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality").font(.subheadline)
                    ForEach(BitrateSetting.allCases) { b in
                        qualityRow(b)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func qualityRow(_ b: BitrateSetting) -> some View {
        Button {
            settings.bitrate = b
        } label: {
            HStack {
                Image(systemName: settings.bitrate == b ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(settings.bitrate == b ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(b.qualityLabel)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(b.ramEstimate(for: settings.replayDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

#Preview {
    CaptureSettingsView()
        .environmentObject(SettingsStore.shared)
}
