import AppKit
import ScreenpopCore

let arguments = CommandLine.arguments

// `Screenpop --process in.png [out.png]` runs the cutout + naming steps without the UI.
if let flag = arguments.firstIndex(of: "--process") {
    Task { exit(await processFile(Array(arguments[(flag + 1)...]))) }
    dispatchMain()
}

if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
    _ = NSApplication.shared
    do { try Snapshots.write(to: URL(fileURLWithPath: arguments[flag + 1])) } catch { print(error); exit(1) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

func processFile(_ args: [String]) async -> Int32 {
    guard let inputPath = args.first else {
        print("usage: Screenpop --process <input.png> [output.png]")
        return 64
    }
    let input = URL(fileURLWithPath: inputPath)
    let output = args.dropFirst().first.map { URL(fileURLWithPath: $0) }
        ?? input.deletingPathExtension().appendingPathExtension("cutout.png")
    do {
        let shot = try Screenshot(contentsOf: input)
        let clock = ContinuousClock()
        let start = clock.now
        let cutout = try Cutout.liftSubject(from: shot.image)
        print("cutout: \(cutout.map { "\($0.width)x\($0.height)" } ?? "no subject") in \(clock.now - start)")
        try ImageFile.png(cutout ?? shot.image, dpi: shot.dpi).write(to: output)
        print("wrote: \(output.path)")

        guard let key = APIKeyStore.resolve() else {
            print("name: skipped (no OpenAI key)")
            return 0
        }
        let nameStart = clock.now
        do {
            let name = try await Namer(apiKey: key.key).name(for: shot.image)
            print("name: \(name) in \(clock.now - nameStart) (key from \(key.source))")
        } catch {
            print("name: failed, \(error.localizedDescription)")
        }
        return 0
    } catch {
        print("error: \(error.localizedDescription)")
        return 1
    }
}
