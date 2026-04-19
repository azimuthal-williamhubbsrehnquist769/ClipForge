import SwiftUI

struct LibrarySettingsView: View {

    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Library Location") {
                HStack {
                    Text(settings.libraryPath.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Choose…") { chooseLibraryFolder() }
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.open(settings.libraryPath)
                }
                .buttonStyle(.link)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersionString ?? "1.0.0")
                LabeledContent("License", value: "MIT")
                Link("View on GitHub", destination: URL(string: "https://github.com/yourusername/ClipForge")!)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Library Folder"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    settings.libraryPath = url
                }
            }
        }
    }
}

private extension Bundle {
    var shortVersionString: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

#Preview {
    LibrarySettingsView()
        .environmentObject(SettingsStore.shared)
}
