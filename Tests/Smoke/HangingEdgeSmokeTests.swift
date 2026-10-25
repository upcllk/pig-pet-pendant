import AppKit

extension PendantCoordinator {
    func smokeCheckHangingEdges() {
        guard let source = artwork.hangingLayers.body.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("Cannot inspect hanging body source")
        }
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let succeeded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        precondition(succeeded)
        let original = pixels
        HangingBodyEdgeCleanup.apply(to: &pixels, width: width, height: height)
        var changed = 0
        var whiteBefore = 0
        var whiteAfter = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                func white(_ data: [UInt8], eligible: Bool = false) -> Bool {
                    let alpha = Double(data[index + 3])
                    guard alpha > 0 else { return false }
                    let values = (0..<3).map { Double(data[index + $0]) / alpha }
                    return eligible
                        ? values.min()! > 0.65 && values.max()! > 0.82 && values.max()! - values.min()! < 0.28
                        : values.min()! > 0.86 && values.max()! - values.min()! < 0.14
                }
                if white(original) { whiteBefore += 1 }
                if white(pixels) { whiteAfter += 1 }
                if Array(original[index..<(index + 4)]) != Array(pixels[index..<(index + 4)]) {
                    changed += 1
                    precondition(white(original, eligible: true), "Cleanup must only change pale source edge pixels")
                    var transparentNearby = false
                    for dy in -3...3 {
                        for dx in -3...3 where (0..<width).contains(x + dx) && (0..<height).contains(y + dy) {
                            transparentNearby = transparentNearby || original[((y + dy) * width + x + dx) * 4 + 3] == 0
                        }
                    }
                    precondition(transparentNearby, "Cleanup must stay within three source pixels of transparency")
                }
            }
        }
        NSLog("Hanging edge cleanup: changed=%d nearWhite=%d -> %d", changed, whiteBefore, whiteAfter)
        precondition(changed > 300 && whiteAfter < whiteBefore / 2,
                     "Cleanup must measurably reduce the white matte, not just change a few pixels")
        let before = NSImage(cgImage: source, size: artwork.hanging.size)
        let after = artwork.hangingCharacter.image(for: .rest)
        let sheet = NSImage(size: NSSize(width: 1440, height: 900))
        sheet.lockFocus()
        for (column, background) in [NSColor.black, NSColor.white, NSColor(calibratedWhite: 0.23, alpha: 1)].enumerated() {
            background.setFill()
            NSRect(x: column * 480, y: 0, width: 480, height: 900).fill()
            for (row, image) in [before, after].enumerated() {
                let rect = NSRect(x: CGFloat(column) * 480 + 50, y: CGFloat(1 - row) * 450 + 40,
                                  width: 360, height: 384)
                image.draw(in: rect)
                artwork.hangingLayers.halo.draw(in: rect)
                (row == 0 ? "Before" : "Runtime cleanup").draw(at: NSPoint(x: rect.minX, y: rect.minY - 25),
                    withAttributes: [.foregroundColor: column == 1 ? NSColor.black : NSColor.white])
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode edge comparison")
        }
        do {
            try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("hanging-edge-comparison.png"))
        } catch { preconditionFailure("Cannot save edge comparison: \(error)") }
    }
}
