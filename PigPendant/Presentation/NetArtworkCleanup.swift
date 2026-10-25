import AppKit

enum NetArtworkCleanup {
    static func image(_ source: CGImage) -> CGImage? {
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        apply(to: &pixels, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func apply(to pixels: inout [UInt8], width: Int, height: Int) {
        let source = pixels
        func color(_ index: Int) -> (r: Double, g: Double, b: Double) {
            let alpha = max(1, Double(source[index + 3]))
            return (Double(source[index]) / alpha, Double(source[index + 1]) / alpha,
                    Double(source[index + 2]) / alpha)
        }
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let original = color(index)
                let minimum = min(original.r, original.g, original.b)
                let maximum = max(original.r, original.g, original.b)
                guard source[index + 3] > 0, minimum > 0.60, maximum - minimum < 0.18,
                      original.b >= original.r - 0.015, original.g >= original.r - 0.015 else { continue }
                var red = 0.0
                var green = 0.0
                var blue = 0.0
                var total = 0.0
                var transparentNeighbor = false
                for dy in -2...2 {
                    for dx in -2...2 where (0..<width).contains(x + dx) && (0..<height).contains(y + dy) {
                        let next = ((y + dy) * width + x + dx) * 4
                        if abs(dx) <= 1 && abs(dy) <= 1 && source[next + 3] == 0 { transparentNeighbor = true }
                        let value = color(next)
                        let distance = dx * dx + dy * dy
                        if source[next + 3] >= 128 && value.r < 0.65 &&
                            value.b > value.r + 0.06 && value.b > value.g + 0.015 && value.g >= value.r {
                            let weight = 1 / (Double(distance) + 0.5)
                            red += value.r * weight
                            green += value.g * weight
                            blue += value.b * weight
                            total += weight
                        }
                    }
                }
                guard total > 0 else { continue }
                let alpha = Double(source[index + 3]) * (transparentNeighbor ? 0.9 : 1)
                let replacement = [red / total * 0.85 + original.r * 0.15,
                                   green / total * 0.85 + original.g * 0.15,
                                   blue / total * 0.85 + original.b * 0.15]
                for (channel, value) in replacement.enumerated() {
                    pixels[index + channel] = UInt8(min(255, max(0, value * alpha)).rounded())
                }
                pixels[index + 3] = UInt8(alpha.rounded())
            }
        }
    }
}
