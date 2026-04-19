import SwiftUI
import Carbon.HIToolbox
import AppKit

struct HotkeySettingsView: View {

    @EnvironmentObject var settings: SettingsStore
    @State private var recordingFor: HotkeyAction? = nil
    @State private var eventMonitor: Any?

    enum HotkeyAction: String, CaseIterable, Identifiable {
        case saveClip      = "Save Replay Clip"
        case startStop     = "Start / Stop Recording"
        case muteMic       = "Mute / Unmute Mic"
        case openApp       = "Open ClipForge"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Global Hotkeys") {
                Text("Click a binding to record a new shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                hotkeyRow(.saveClip,  binding: $settings.saveClipHotkey)
                hotkeyRow(.startStop, binding: $settings.startStopHotkey)
                hotkeyRow(.muteMic,   binding: $settings.muteMicHotkey)
                hotkeyRow(.openApp,   binding: $settings.openAppHotkey)
            }

            Section {
                Button("Reset to Defaults") {
                    stopRecording()
                    settings.saveClipHotkey    = HotkeyBinding(modifiers: [.command, .shift], keyCode: 3)
                    settings.startStopHotkey   = HotkeyBinding(modifiers: [.command, .shift], keyCode: 15)
                    settings.muteMicHotkey     = HotkeyBinding(modifiers: [.command, .shift], keyCode: 46)
                    settings.openAppHotkey     = HotkeyBinding(modifiers: [.command, .shift], keyCode: 38)
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: recordingFor) { _, newValue in
            if newValue != nil { startMonitor() } else { stopMonitor() }
        }
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private func hotkeyRow(_ action: HotkeyAction, binding: Binding<HotkeyBinding>) -> some View {
        LabeledContent(action.rawValue) {
            HotkeyRecorderButton(
                binding: binding,
                isRecording: recordingFor == action,
                onStartRecording: {
                    // Cancel any in-progress recording first.
                    recordingFor = nil
                    DispatchQueue.main.async { recordingFor = action }
                },
                onStopRecording: { stopRecording() }
            )
        }
    }

    // MARK: - NSEvent monitoring

    private func startMonitor() {
        stopMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            self.handleNSEvent(event)
            return nil // consume – don't forward to focused control
        }
    }

    private func stopMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func stopRecording() {
        recordingFor = nil
        stopMonitor()
    }

    private func handleNSEvent(_ event: NSEvent) {
        guard let action = recordingFor else { return }

        // Escape cancels recording without saving.
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Require at least one modifier so lone letters don't get eaten.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty else { return }

        var nsFlags: NSEvent.ModifierFlags = []
        if flags.contains(.command)  { nsFlags.insert(.command) }
        if flags.contains(.shift)    { nsFlags.insert(.shift) }
        if flags.contains(.option)   { nsFlags.insert(.option) }
        if flags.contains(.control)  { nsFlags.insert(.control) }

        let binding = HotkeyBinding(modifiers: nsFlags, keyCode: event.keyCode)
        switch action {
        case .saveClip:  settings.saveClipHotkey  = binding
        case .startStop: settings.startStopHotkey = binding
        case .muteMic:   settings.muteMicHotkey   = binding
        case .openApp:   settings.openAppHotkey   = binding
        }
        stopRecording()
    }
}

// MARK: - Hotkey recorder button

struct HotkeyRecorderButton: View {
    @Binding var binding: HotkeyBinding
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void

    var body: some View {
        Button(action: {
            if isRecording { onStopRecording() }
            else { onStartRecording() }
        }) {
            Text(isRecording ? "Press keys…" : binding.displayString)
                .font(.caption.monospaced())
                .frame(minWidth: 80)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isRecording
                        ? Color.accentColor.opacity(0.15)
                        : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HotkeySettingsView()
        .environmentObject(SettingsStore.shared)
}
