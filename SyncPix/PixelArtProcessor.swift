import UIKit
import CoreGraphics

/// Native RGB sampling only. No network, palette substitution, or image-generation model.
enum PixelArtProcessor {
    static let resolution = 24

    /// UIImage.draw applies all eight UIImage orientations, including mirrored camera images.
    /// Bound the normalized intermediate to avoid a second full-size camera-photo allocation.
    static func normalizeOrientation(_ image: UIImage) throws -> UIImage {
        guard image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else { throw AppFailure.image }
        if image.imageOrientation == .up, image.scale == 1, image.cgImage != nil,
           max(image.size.width, image.size.height) <= 2048 { return image }
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let scale = min(1, 2048 / max(pixelSize.width, pixelSize.height))
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size))
            renderer.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// New artwork uses the default 24. Other sizes remain supported for saved legacy artwork/tests.
    static func process(_ image: UIImage, resolution: Int = 24, zoom: CGFloat = 1, offset: CGSize = .zero) throws -> [Int] {
        guard (1...256).contains(resolution), zoom.isFinite, (1...3).contains(zoom),
              offset.width.isFinite, offset.height.isFinite else { throw AppFailure.image }
        let normalized = try normalizeOrientation(image)
        let side = CGFloat(resolution)
        let scale = max(side / normalized.size.width, side / normalized.size.height) * zoom
        let size = CGSize(width: normalized.size.width * scale, height: normalized.size.height * scale)
        // Clamp the square crop so no uncovered border is sampled.
        let maxX = max(0, (size.width - side) / 2)
        let maxY = max(0, (size.height - side) / 2)
        let x = (side - size.width) / 2 + min(maxX, max(-maxX, offset.width * side))
        let y = (side - size.height) / 2 + min(maxY, max(-maxY, offset.height * side))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let sampled = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            UIColor.white.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: side, height: side))
            renderer.cgContext.interpolationQuality = .high
            normalized.draw(in: CGRect(x: x, y: y, width: size.width, height: size.height))
        }
        guard let cgImage = sampled.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw AppFailure.image }
        var bytes = [UInt8](repeating: 0, count: resolution * resolution * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(data: buffer.baseAddress, width: resolution, height: resolution,
                                          bitsPerComponent: 8, bytesPerRow: resolution * 4,
                                          space: colorSpace, bitmapInfo: info) else { throw AppFailure.image }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: resolution, height: resolution))
        }
        return stride(from: 0, to: bytes.count, by: 4).map {
            Int(bytes[$0]) << 16 | Int(bytes[$0 + 1]) << 8 | Int(bytes[$0 + 2])
        }
    }

    /// Make an exact-size, opaque sRGB raster. Enlargement is handled with interpolation(.none).
    static func image(from pixels: [Int], resolution: Int = 24) throws -> UIImage {
        guard (1...256).contains(resolution), pixels.count == resolution * resolution,
              pixels.allSatisfy({ (0...0xFFFFFF).contains($0) }),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw AppFailure.image }
        let bytes = pixels.flatMap { value -> [UInt8] in
            [UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255), 255]
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(width: resolution, height: resolution, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: resolution * 4, space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw AppFailure.image }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

/// The single mapping used for pixel colors and unlock geometry; 24×24 yields 16 pixels per block.
enum PixelBlockLayout {
    static let side = 6
    static let count = 36
    static func blockID(x: Int, y: Int, resolution: Int = 24) -> Int? {
        guard (1...256).contains(resolution), (0..<resolution).contains(x), (0..<resolution).contains(y) else { return nil }
        return (y * side / resolution) * side + x * side / resolution
    }
    static func pixelIndices(in block: Int, resolution: Int = 24) -> [Int] {
        guard (0..<count).contains(block), (1...256).contains(resolution) else { return [] }
        return (0..<(resolution * resolution)).filter { blockID(x: $0 % resolution, y: $0 / resolution, resolution: resolution) == block }
    }
    static func lockedColors(_ pixels: [Int], mode: String) -> [Int] {
        pixels.map { value in
            if mode == "Mystery Reveal" { return 0xE0D4D1 }
            let r = Double((value >> 16) & 255), g = Double((value >> 8) & 255), b = Double(value & 255)
            let gray = Int((0.299 * r + 0.587 * g + 0.114 * b).rounded())
            return gray << 16 | gray << 8 | gray
        }
    }
    static func displayColors(_ pixels: [Int], resolution: Int = 24, mode: String, unlocked: [Int]) -> [Int] {
        guard (1...256).contains(resolution), pixels.count == resolution * resolution else { return [] }
        let locked = lockedColors(pixels, mode: mode), open = Set(unlocked)
        return pixels.indices.map { index in
            guard let block = blockID(x: index % resolution, y: index / resolution, resolution: resolution) else { return locked[index] }
            return open.contains(block) ? pixels[index] : locked[index]
        }
    }
}
