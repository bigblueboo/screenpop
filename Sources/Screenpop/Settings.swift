import AppKit
import Observation
import ScreenpopCore
import Security
import ServiceManagement

@MainActor @Observable
final class Settings {
    private let defaults = UserDefaults.standard

    var removeBackground: Bool {
        didSet { defaults.set(removeBackground, forKey: "removeBackground") }
    }

    var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: "saveFolder") }
    }

    var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }

    init() {
        removeBackground = defaults.object(forKey: "removeBackground") as? Bool ?? true
        saveFolder = defaults.string(forKey: "saveFolder").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/Screenpop")
        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            ?? .standard
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// The OpenAI key comes from, in order: the Keychain (set in Settings), the
/// OPENAI_API_KEY environment variable, or ~/.secrets/screenpop/openai.env.
enum APIKeyStore {
    private static var query: [CFString: Any] { [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.bigblueboo.screenpop",
        kSecAttrAccount: "openai",
    ] }

    static let secretsFile = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".secrets/screenpop/openai.env")

    static func resolve() -> (key: String, source: String)? {
        if let key = keychainValue() { return (key, "Keychain") }
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return (key, "OPENAI_API_KEY")
        }
        if let text = try? String(contentsOf: secretsFile, encoding: .utf8),
           let key = EnvFile.value(for: "OPENAI_API_KEY", in: text) {
            return (key, "~/.secrets/screenpop/openai.env")
        }
        return nil
    }

    /// Stores the key in the Keychain; an empty string removes it.
    static func save(_ key: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return true }
        var item = query
        item[kSecValueData] = Data(key.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func keychainValue() -> String? {
        var lookup = query
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
