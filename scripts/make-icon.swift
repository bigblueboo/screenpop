// Masks Resources/AppIcon-source.png into the macOS icon shape and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appending(path: "Resources")
guard let art = NSImage(contentsOf: resources.appending(path: "AppIcon-source.png"))?
    .cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("missing Resources/AppIcon-source.png") }

/// Superellipse approximating Apple's continuous-corner icon shape.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let (a, b) = (rect.width / 2, rect.height / 2)
    for step in 0...720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let (c, s) = (cos(t), sin(t))
        let point = CGPoint(x: rect.midX + a * copysign(pow(abs(c), 2 / n), c),
                            y: rect.midY + b * copysign(pow(abs(s), 2 / n), s))
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func render(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high
    // Apple's grid: an 824pt body centered on a 1024pt canvas, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(art, in: body)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try render(size: 1024).write(to: FileManager.default.temporaryDirectory.appending(path: "AppIcon-preview.png"))
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
exit(iconutil.terminationStatus)
