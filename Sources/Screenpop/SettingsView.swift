import AppKit
import Carbon.HIToolbox
import ScreenpopCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    /// Called with true while recording a new shortcut, so the old one doesn't fire.
    let onRecording: (Bool) -> Void

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
                LaunchAtLoginToggle()
            }
            Section {
                APIKeyField()
            } header: {
                Text("OpenAI naming")
            } footer: {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Captures are named by \(Namer.defaultModel). Without a key they keep a timestamp name.")
                        .foregroundStyle(.secondary)
                    Text("Screenpop \(AppInfo.version)")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
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

/// Saves the OpenAI key to the Keychain and says where the active key comes from.
struct APIKeyField: View {
    @State private var draft = ""
    @State private var source = APIKeyStore.resolve()?.source
    @State private var saveFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField("API key", text: $draft, prompt: Text("sk-…"))
                    .labelsHidden()
                    .onSubmit(save)
                Button("Save", action: save).disabled(draft.isEmpty)
            }
            Text(status).font(.caption).foregroundStyle(saveFailed ? .red : .secondary)
        }
    }

    private var status: String {
        if saveFailed { return "Couldn't save to the Keychain." }
        return source.map { "Using key from \($0)" } ?? "No key yet"
    }

    private func save() {
        saveFailed = !APIKeyStore.save(draft.trimmingCharacters(in: .whitespacesAndNewlines))
        if !saveFailed { draft = "" }
        source = APIKeyStore.resolve()?.source
    }
}

struct LaunchAtLoginToggle: View {
    @State private var isOn = LaunchAtLogin.isEnabled

    var body: some View {
        Toggle("Open at login", isOn: $isOn)
            .onChange(of: isOn) { _, enabled in
                do { try LaunchAtLogin.set(enabled) } catch { isOn = LaunchAtLogin.isEnabled }
            }
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
