import AppKit

enum NetPigArtwork {
    static func removeOpenEye(_ source: NSImage) throws -> NSImage {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ArtworkError.invalidNetRetouch
        }
        let original = NSBitmapImageRep(cgImage: cg)
        let result = NSBitmapImageRep(cgImage: cg)
        let eyeRegion = NSRect(x: 294, y: 398, width: 55, height: 50)
        var mask = Set<Int>()
        for y in Int(eyeRegion.minY)..<Int(eyeRegion.maxY) {
            for x in Int(eyeRegion.minX)..<Int(eyeRegion.maxX) {
                guard let color = original.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.1,
                      color.redComponent < 0.68,
                      color.greenComponent < 0.58,
                      color.blueComponent < 0.50 else { continue }
                mask.insert(y * cg.width + x)
            }
        }
        guard mask.count > 250 else { throw ArtworkError.invalidNetRetouch }

        for pixel in mask {
            let x = pixel % cg.width
            let y = pixel / cg.width
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var totalWeight: CGFloat = 0
            for radius in 1...16 where totalWeight < 2 {
                for offsetY in -radius...radius {
                    for offsetX in -radius...radius where max(abs(offsetX), abs(offsetY)) == radius {
                        let sampleX = x + offsetX
                        let sampleY = y + offsetY
                        guard sampleX >= 0, sampleX < cg.width, sampleY >= 0, sampleY < cg.height,
                              !mask.contains(sampleY * cg.width + sampleX),
                              let sample = original.colorAt(x: sampleX, y: sampleY)?.usingColorSpace(.deviceRGB),
                              sample.alphaComponent > 0.8,
                              (sample.blueComponent <= sample.redComponent + 0.08 ||
                                sample.blueComponent <= sample.greenComponent + 0.08) else { continue }
                        let weight = 1 / CGFloat(offsetX * offsetX + offsetY * offsetY)
                        red += sample.redComponent * weight
                        green += sample.greenComponent * weight
                        blue += sample.blueComponent * weight
                        totalWeight += weight
                    }
                }
            }
            guard totalWeight > 0,
                  let originalPixel = original.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                throw ArtworkError.invalidNetRetouch
            }
            result.setColor(NSColor(deviceRed: red / totalWeight, green: green / totalWeight,
                                    blue: blue / totalWeight, alpha: originalPixel.alphaComponent),
                            atX: x, y: y)
        }
        guard let resultCG = result.cgImage else { throw ArtworkError.invalidNetRetouch }
        return NSImage(cgImage: resultCG, size: source.size)
    }
}
