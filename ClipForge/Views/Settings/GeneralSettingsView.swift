import SwiftUI

struct GeneralSettingsView: View {

    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Replay Buffer") {
                Picker("Save last", selection: $settings.replayDuration) {
                    ForEach(ReplayDuration.allCases) { d in
                        Text(d.label).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                Text("Keeps a rolling window of your last N seconds of gameplay.\nPress the hotkey to save it as a clip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Audio") {
                Toggle("Capture system audio", isOn: $settings.capturesSystemAudio)
                Toggle("Capture microphone", isOn: $settings.capturesMicrophone)
            }

            Section("Launch") {
                Toggle("Show menu bar icon", isOn: .constant(true))
                    .disabled(true)
                    .help("Always enabled in this release.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(SettingsStore.shared)
}
