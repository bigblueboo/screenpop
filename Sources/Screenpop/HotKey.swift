import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// What the key types with no modifiers; doubles as the menu item's key equivalent.
    var key: String
    var modifierFlags: UInt

    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_4), key: "4",
                                   modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue)

    init(keyCode: UInt32, key: String, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.key = key
        self.modifierFlags = modifierFlags
    }

    /// Nil unless the event includes ⌘, ⌃, or ⌥; a bare or shift-only key would eat normal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.isDisjoint(with: [.command, .control, .option]),
              let key = event.characters(byApplyingModifiers: []), !key.isEmpty
        else { return nil }
        self.init(keyCode: UInt32(event.keyCode), key: key, modifierFlags: flags.rawValue)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    var carbonModifiers: UInt32 {
        var mods = 0
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        return UInt32(mods)
    }

    var display: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = symbols.filter { flags.contains($0.0) }.map(\.1).joined()
        return prefix + (Self.keyNames[Int(keyCode)] ?? key.uppercased())
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// A system-wide hotkey via Carbon, which needs no Accessibility permission.
@MainActor
final class HotKey {
    private let action: () -> Void
    private var ref: EventHotKeyRef?

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x5350_4F50), id: 1) // 'SPOP'
        return RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                   GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
