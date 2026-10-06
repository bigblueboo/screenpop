import AppKit
import ScreenpopCore

/// Hotkey → rect selection → cutout → clipboard + file → AI rename.
@MainActor
final class Pipeline {
    private let settings: Settings
    private let hud: HUD
    private let onNeedsAccess: () -> Void
    private var selecting = false

    init(settings: Settings, hud: HUD, onNeedsAccess: @escaping () -> Void) {
        self.settings = settings
        self.hud = hud
        self.onNeedsAccess = onNeedsAccess
    }

    func capture() {
        guard !selecting else { return }
        guard CGPreflightScreenCaptureAccess() else { return onNeedsAccess() }
        selecting = true
        Task {
            do {
                let file = try await Self.selectRect()
                selecting = false
                if let file { try await process(file) }
            } catch {
                selecting = false
                Alerts.show(error)
            }
        }
    }

    /// The system's own crosshair selector (Space toggles window mode, Esc cancels).
    /// Returns nil when the user cancels.
    private static func selectRect() async throws -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "screenpop-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", "-t", "png", url.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func process(_ file: URL) async throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let shot = try Screenshot(contentsOf: file)

        // Name from the full capture (more context) while the cutout runs.
        let naming = Task.detached(priority: .userInitiated) {
            guard let key = APIKeyStore.resolve()?.key else { throw NamerError.missingKey }
            return try await Namer(apiKey: key).name(for: shot.image)
        }

        var cutout: CGImage?
        var note: String?
        if settings.removeBackground {
            do {
                cutout = try await Task.detached(priority: .userInitiated) { try Cutout.liftSubject(from: shot.image) }.value
                if cutout == nil { note = "No subject found, so the full capture was kept." }
            } catch {
                note = "Background removal failed, so the full capture was kept."
            }
        }
        let image = cutout ?? shot.image
        let png = try ImageFile.png(image, dpi: shot.dpi)
        if settings.copyToClipboard { Clipboard.put(png: png, image: image) }

        let folder = settings.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = FileNaming.uniqueURL(in: folder, base: FileNaming.timestamp(.now))
        try png.write(to: url)

        let card = CaptureCard(image: image, url: url, isCutout: cutout != nil, copied: settings.copyToClipboard)
        card.note = note
        hud.present(card)

        // The file exists under a timestamp name first so drag and clipboard work instantly.
        do {
            let named = FileNaming.uniqueURL(in: folder, base: try await naming.value)
            try FileManager.default.moveItem(at: url, to: named)
            card.url = named
        } catch {
            card.note = [card.note, error.localizedDescription].compactMap { $0 }.joined(separator: " ")
        }
        card.isNaming = false
        hud.settle(card)
    }
}

enum Clipboard {
    /// PNG for modern apps, TIFF for older ones; both keep transparency.
    static func put(png: Data, image: CGImage) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            board.setData(tiff, forType: .tiff)
        }
    }
}

@MainActor
enum Alerts {
    static func show(_ error: Error) {
        let alert = NSAlert(error: error)
        NSApp.activate()
        alert.runModal()
    }
}
