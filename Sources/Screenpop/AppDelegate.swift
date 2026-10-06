import AppKit
import ScreenpopCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let hud = HUD()
    private let screenAccess = ScreenAccess()
    private lazy var pipeline = Pipeline(settings: settings, hud: hud) { [weak self] in self?.openSetup() }
    private lazy var hotKey = HotKey { [weak self] in self?.pipeline.capture() }
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Screenpop")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        NSApp.mainMenu = Self.makeMainMenu()

        hotKey.register(settings.shortcut)
        Task.detached(priority: .utility) { Cutout.warmUp() }
        if !screenAccess.isGranted || !settings.onboarded { openSetup() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !CGPreflightScreenCaptureAccess() {
            menu.addItem(withTitle: "Allow Screen Recording…", action: #selector(openSetup), keyEquivalent: "")
            menu.addItem(.separator())
        }
        let capture = menu.addItem(withTitle: settings.removeBackground ? "Capture Cutout" : "Capture Screenshot",
                                   action: #selector(capture), keyEquivalent: settings.shortcut.key)
        capture.keyEquivalentModifierMask = settings.shortcut.flags
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove Background", action: #selector(toggleBackground), keyEquivalent: "")
            .state = settings.removeBackground ? .on : .off
        menu.addItem(withTitle: "Copy to Clipboard", action: #selector(toggleClipboard), keyEquivalent: "")
            .state = settings.copyToClipboard ? .on : .off
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screenpop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    /// Never shown (we're a menu bar app), but text fields only get ⌘V/⌘C/⌘A/⌘Z
    /// and windows only get ⌘W through main-menu key equivalents.
    private static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for submenu in [NSMenu(title: "Screenpop"), edit, window] {
            main.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
        }
        return main
    }

    @objc private func capture() { pipeline.capture() }

    @objc private func toggleBackground() { settings.removeBackground.toggle() }

    @objc private func toggleClipboard() { settings.copyToClipboard.toggle() }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: settings.saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(settings.saveFolder)
    }

    @objc private func openSettings() {
        present(\.settingsWindow, title: "Screenpop Settings") {
            SettingsView(settings: settings) { [weak self] recording in
                guard let self else { return }
                if recording { hotKey.unregister() } else { hotKey.register(settings.shortcut) }
            }
        }
    }

    @objc private func openSetup() {
        screenAccess.refresh()
        present(\.setupWindow, title: "Welcome to Screenpop") {
            OnboardingView(settings: settings, access: screenAccess) { [weak self] in
                guard let self else { return }
                if screenAccess.isGranted { settings.onboarded = true }
                setupWindow?.close()
            }
        }
    }

    /// Shows the window in `slot`, creating it on first use.
    private func present(_ slot: ReferenceWritableKeyPath<AppDelegate, NSWindow?>, title: String,
                         content: () -> some View) {
        let window = self[keyPath: slot] ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self[keyPath: slot] = window
            return window
        }()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
