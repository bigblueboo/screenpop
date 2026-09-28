import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

public enum ImageError: LocalizedError {
    case unreadable, encodingFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Couldn't read the captured image."
        case .encodingFailed: "Couldn't encode the image."
        }
    }
}

/// A captured image plus its DPI, so the saved PNG keeps Retina point sizing.
public struct Screenshot: Sendable {
    public let image: CGImage
    public let dpi: Double

    public init(image: CGImage, dpi: Double) {
        self.image = image
        self.dpi = dpi
    }

    public init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageError.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        self.init(image: image, dpi: properties?[kCGImagePropertyDPIWidth] as? Double ?? 72)
    }
}

public enum Cutout {
    // Color management off: Vision only masks pixels, so we pass them through untouched
    // and re-tag the result with the source color space.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    /// The foreground subject(s) on a transparent background, cropped to their bounds.
    /// Returns nil when Vision finds nothing it considers a subject.
    public static func liftSubject(from image: CGImage) throws -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
        let masked = CIImage(cvPixelBuffer: buffer)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(masked, from: masked.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    /// Loads the Vision model so the first real capture doesn't pay for it.
    public static func warmUp() {
        let size = 64
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let blank = ctx.makeImage()
        else { return }
        _ = try? liftSubject(from: blank)
    }
}

public enum ImageFile {
    public static func png(_ image: CGImage, dpi: Double = 72) throws -> Data {
        try encode(image, type: .png, properties: [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi])
    }

    /// A small JPEG flattened onto white, sized for a cheap vision-model call.
    public static func thumbnailJPEG(_ image: CGImage, maxSide: Int = 512) throws -> Data {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ImageError.encodingFailed }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let flattened = ctx.makeImage() else { throw ImageError.encodingFailed }
        return try encode(flattened, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: 0.8])
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
        else { throw ImageError.encodingFailed }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.encodingFailed }
        return data as Data
    }
}
