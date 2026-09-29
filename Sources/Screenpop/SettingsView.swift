import AppKit
import Carbon.HIToolbox
import ScreenpopCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    /// Called with true while recording a new shortcut, so the old one doesn't fire.
    let onRecording: (Bool) -> Void

    @State private var keyDraft = ""
    @State private var keySource = APIKeyStore.resolve()?.source
    @State private var keySaveFailed = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: $settings.shortcut, onRecording: onRecording)
                }
                Toggle("Remove background", isOn: $settings.removeBackground)
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
                LabeledContent("Save to") {
                    HStack {
                        Text(settings.saveFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do { try LaunchAtLogin.set(enabled) } catch { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
            }
            Section {
                SecureField("API key", text: $keyDraft, prompt: Text("sk-…"))
                    .onSubmit(saveKey)
                HStack {
                    Text(keyStatus).font(.caption).foregroundStyle(keySaveFailed ? .red : .secondary)
                    Spacer()
                    Button("Save", action: saveKey).disabled(keyDraft.isEmpty)
                }
            } header: {
                Text("OpenAI naming")
            } footer: {
                Text("Captures are named by \(Namer.defaultModel). Without a key they keep a timestamp name.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private var keyStatus: String {
        if keySaveFailed { return "Couldn't save to the Keychain." }
        return keySource.map { "Using key from \($0)" } ?? "No key found"
    }

    private func saveKey() {
        keySaveFailed = !APIKeyStore.save(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        if !keySaveFailed { keyDraft = "" }
        keySource = APIKeyStore.resolve()?.source
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveFolder
        if panel.runModal() == .OK, let url = panel.url { settings.saveFolder = url }
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    let onRecording: (Bool) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button { monitor == nil ? start() : stop() } label: {
            Text(monitor == nil ? shortcut.display : "Type shortcut…")
                .monospacedDigit()
                .frame(minWidth: 110)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == UInt16(kVK_Escape) {
                    stop()
                } else if let recorded = Shortcut(event: event) {
                    shortcut = recorded
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        onRecording(false)
    }
}
