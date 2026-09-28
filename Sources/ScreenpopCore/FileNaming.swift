import Foundation

public enum FileNaming {
    /// Turns model output into a safe kebab-case base name, or nil if nothing usable is left.
    public static func slug(_ raw: String, maxLength: Int = 60) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = text.lastIndex(of: "."), ["png", "jpg", "jpeg"].contains(text[text.index(after: dot)...].lowercased()) {
            text = String(text[..<dot])
        }
        let words = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .lowercased()
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }

        var result = ""
        for word in words {
            let next = result.isEmpty ? String(word) : "\(result)-\(word)"
            if next.count > maxLength { break }
            result = next
        }
        if result.isEmpty, let first = words.first { result = String(first.prefix(maxLength)) }
        return result.isEmpty ? nil : result
    }

    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenpop \(formatter.string(from: date))"
    }

    /// `base.png`, or `base-2.png`, `base-3.png`… if taken.
    public static func uniqueURL(in folder: URL, base: String, ext: String = "png",
                                 exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        var candidate = folder.appending(path: "\(base).\(ext)")
        var n = 2
        while exists(candidate) {
            candidate = folder.appending(path: "\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

public enum EnvFile {
    /// Reads `KEY=value` from dotenv-style text (handles `export`, quotes, comments).
    public static func value(for key: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            var entry = line.trimmingCharacters(in: .whitespaces)
            if entry.hasPrefix("#") { continue }
            if entry.hasPrefix("export ") { entry = String(entry.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = entry.firstIndex(of: "="), entry[..<eq].trimmingCharacters(in: .whitespaces) == key else { continue }
            let value = entry[entry.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
