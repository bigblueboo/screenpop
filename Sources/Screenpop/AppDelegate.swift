import AppKit
import ScreenpopCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let hud = HUD()
    private lazy var pipeline = Pipeline(settings: settings, hud: hud)
    private lazy var hotKey = HotKey { [weak self] in self?.pipeline.capture() }
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Screenpop")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        hotKey.register(settings.shortcut)
        Task.detached(priority: .utility) { Cutout.warmUp() }
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let capture = menu.addItem(withTitle: settings.removeBackground ? "Capture Cutout" : "Capture Screenshot",
                                   action: #selector(capture), keyEquivalent: settings.shortcut.key)
        capture.keyEquivalentModifierMask = settings.shortcut.flags
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove Background", action: #selector(toggleBackground), keyEquivalent: "")
            .state = settings.removeBackground ? .on : .off
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screenpop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func capture() { pipeline.capture() }

    @objc private func toggleBackground() { settings.removeBackground.toggle() }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: settings.saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(settings.saveFolder)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] recording in
                guard let self else { return }
                if recording { hotKey.unregister() } else { hotKey.register(settings.shortcut) }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Screenpop Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
