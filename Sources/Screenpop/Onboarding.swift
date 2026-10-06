import AppKit
import Observation
import ScreenpopCore
import SwiftUI

/// Screen Recording permission. Captures run `screencapture` as our child process,
/// so macOS checks Screenpop's grant.
@MainActor @Observable
final class ScreenAccess {
    private(set) var isGranted = CGPreflightScreenCaptureAccess()
    private(set) var hasAsked = UserDefaults.standard.bool(forKey: "askedForScreenAccess")
    private var polling: Task<Void, Never>?

    private static let settingsPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// The first time, macOS shows its own prompt and adds Screenpop to the list.
    /// It never prompts twice, so after that we open the Settings pane directly.
    func request() {
        if hasAsked {
            NSWorkspace.shared.open(Self.settingsPane)
        } else {
            CGRequestScreenCaptureAccess()
            hasAsked = true
            UserDefaults.standard.set(true, forKey: "askedForScreenAccess")
        }
        refresh()
    }

    /// Re-reads the grant (it can be revoked while we run), then watches for it to appear
    /// so the window updates without a relaunch.
    func refresh() {
        isGranted = CGPreflightScreenCaptureAccess()
        guard !isGranted, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if CGPreflightScreenCaptureAccess() {
                    isGranted = true
                    polling = nil
                    return
                }
            }
        }
    }

    /// For when the grant only applies to a fresh process. The shell waits for us to exit,
    /// otherwise `open` would just reactivate this instance.
    static func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 $1 2>/dev/null; do sleep 0.1; done; open \"$0\"",
                           Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        try? shell.run()
        NSApp.terminate(nil)
    }
}

struct OnboardingView: View {
    let settings: Settings
    let access: ScreenAccess
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up Screenpop").font(.title2.weight(.semibold))
                    Text("Only the first step is required.").foregroundStyle(.secondary)
                }
            }

            Step(number: 1, title: "Allow screen recording", done: access.isGranted) {
                if access.isGranted {
                    Text("Allowed. You're ready to capture.")
                } else {
                    Text(access.hasAsked
                         ? "In System Settings, turn on Screenpop. If macOS offers Quit & Reopen, click it."
                         : "Screenpop captures with the macOS screenshot tool, which needs this permission.")
                    HStack {
                        Button(access.hasAsked ? "Open System Settings" : "Allow…", action: access.request)
                            .buttonStyle(.borderedProminent)
                        if access.hasAsked {
                            Button("Restart Screenpop", action: ScreenAccess.relaunch)
                        }
                    }
                }
            }

            Step(number: 2, title: "Add your OpenAI key") {
                APIKeyField()
                Text("Optional. \(Namer.defaultModel) names each file from a small copy of the capture. Nothing else is sent.")
            }

            Step(number: 3, title: "Try it") {
                Text("Press \(settings.shortcut.display) and drag over anything.")
                LaunchAtLoginToggle()
            }

            HStack {
                Spacer()
                Button(access.isGranted ? "Done" : "Later", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 480)
        .animation(.easeOut(duration: 0.2), value: access.isGranted)
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let title: String
    var done = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.2))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 22, height: 22)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
