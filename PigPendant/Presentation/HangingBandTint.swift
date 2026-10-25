import AppKit

enum HangingBandTint {
    static func image(_ source: NSImage, ropeReference: NSImage) throws -> NSImage {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let reference = ropeReference.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let sample = reference.cropping(to: CGRect(x: 180, y: 70, width: 1, height: 1)) else {
            throw ArtworkError.invalidBandTint
        }
        var referencePixel = [UInt8](repeating: 0, count: 4)
        let sampled = referencePixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard sampled, referencePixel[3] > 240,
              Int(referencePixel[0]) > Int(referencePixel[1]) + 25,
              Int(referencePixel[0]) > Int(referencePixel[2]) + 25 else { throw ArtworkError.invalidBandTint }
        let brown = referencePixel.prefix(3).map { Double($0) / Double(referencePixel[3]) }
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw ArtworkError.invalidBandTint }
        var changed = 0
        for y in Int(Double(height) * 0.30)..<Int(Double(height) * 0.69) {
            for x in Int(Double(width) * 0.19)..<Int(Double(width) * 0.78) {
                let index = (y * width + x) * 4
                let alpha = Double(pixels[index + 3])
                guard alpha > 0 else { continue }
                let r = Double(pixels[index]) / alpha
                let g = Double(pixels[index + 1]) / alpha
                let b = Double(pixels[index + 2]) / alpha
                guard b > r + 0.02 && b > g + 0.04 else { continue }
                let shade = min(1.3, max(0.7, (r + g + b) / 1.44))
                for (channel, value) in brown.enumerated() {
                    pixels[index + channel] = UInt8(min(alpha, Double(value) * shade * alpha).rounded())
                }
                changed += 1
            }
        }
        guard changed > 1000, let provider = CGDataProvider(data: Data(pixels) as CFData),
              let result = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true,
                                   intent: .defaultIntent) else { throw ArtworkError.invalidBandTint }
        return NSImage(cgImage: result, size: source.size)
    }
}
