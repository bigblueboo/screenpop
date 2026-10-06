import AppKit
import SwiftUI

/// `Screenpop --snapshot <dir>` renders the app's windows to PNGs, for checking layout
/// on a Mac you can't see (e.g. over SSH).
@MainActor
enum Snapshots {
    static func write(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = Settings()
        try render(OnboardingView(settings: settings, access: ScreenAccess(), onDone: {}), to: folder, name: "setup")
        try render(SettingsView(settings: settings, onRecording: { _ in }), to: folder, name: "settings")

        guard let icon = NSApp.applicationIconImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let card = CaptureCard(image: icon, url: URL(fileURLWithPath: "/tmp/red-macaw-portrait.png"), isCutout: true, copied: true)
        try render(CardView(card: card, onHover: { _ in }), to: folder, name: "card-naming")
        card.isNaming = false
        card.note = "No OpenAI key. Add one in Settings to get names."
        try render(CardView(card: card, onHover: { _ in }), to: folder, name: "card-done")
    }

    private static func render(_ view: some View, to folder: URL, name: String) throws {
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name).png"))
    }
}
