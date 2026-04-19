import SwiftUI

/// Root settings window with sidebar navigation.
struct SettingsView: View {

    private enum Tab: String, CaseIterable, Identifiable {
        case general  = "General"
        case capture  = "Capture"
        case hotkeys  = "Hotkeys"
        case library  = "Library"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .capture:  return "record.circle"
            case .hotkeys:  return "keyboard"
            case .library:  return "folder"
            }
        }
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "record.circle") }
                .tag(Tab.capture)

            HotkeySettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .tag(Tab.hotkeys)

            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "folder") }
                .tag(Tab.library)
        }
        .frame(width: 460, height: 360)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore.shared)
}
