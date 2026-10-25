import AppKit

enum NetPigArtwork {
    static func removeExtraFoot(_ source: NSImage) throws -> NSImage {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ArtworkError.invalidNetRetouch
        }
        let original = NSBitmapImageRep(cgImage: cg)
        guard cg.bitsPerComponent == 8, cg.bitsPerPixel == 32,
              cg.bytesPerRow >= cg.width * 4,
              let colorSpace = cg.colorSpace,
              let sourceData = cg.dataProvider?.data else {
            throw ArtworkError.invalidNetRetouch
        }
        var pixels = [UInt8](sourceData as Data)
        guard pixels.count >= cg.bytesPerRow * cg.height else {
            throw ArtworkError.invalidNetRetouch
        }
        let footRegion = NSRect(x: 248, y: 398, width: 96, height: 48)
        var footPixels = Set<Int>()
        for y in Int(footRegion.minY)..<Int(footRegion.maxY) {
            for x in Int(footRegion.minX)..<Int(footRegion.maxX) {
                guard let color = original.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.1 else { continue }
                let isBlueMesh = color.blueComponent > color.redComponent + 0.04
                let isPink = !isBlueMesh && color.redComponent > color.greenComponent + 0.10 &&
                    color.blueComponent > color.greenComponent + 0.02
                let isDark = !isBlueMesh && color.redComponent < 0.68 &&
                    color.greenComponent < 0.58 && color.blueComponent < 0.50
                if isPink || isDark { footPixels.insert(y * cg.width + x) }
            }
        }
        guard footPixels.count > 800 else { throw ArtworkError.invalidNetRetouch }
        for pixel in footPixels {
            let offset = (pixel / cg.width) * cg.bytesPerRow + (pixel % cg.width) * 4
            pixels[offset...offset + 3] = [0, 0, 0, 0]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let resultCG = CGImage(width: cg.width, height: cg.height,
                                     bitsPerComponent: cg.bitsPerComponent, bitsPerPixel: cg.bitsPerPixel,
                                     bytesPerRow: cg.bytesPerRow, space: colorSpace,
                                     bitmapInfo: cg.bitmapInfo, provider: provider, decode: cg.decode,
                                     shouldInterpolate: cg.shouldInterpolate, intent: cg.renderingIntent) else {
            throw ArtworkError.invalidNetRetouch
        }
        return NSImage(cgImage: resultCG, size: source.size)
    }
}
