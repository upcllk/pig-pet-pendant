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
        WhiteColorKey.apply(to: &pixels, width: width, height: height)
        guard let displayCG = artwork.hangingCharacter.image(for: .rest)
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("Cannot inspect white-keyed body used by the app")
        }
        let displayed = NSBitmapImageRep(cgImage: displayCG)
        var changed = 0
        var whiteBefore = 0
        var whiteAfter = 0
        var selectedBoundaryWhite = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                func white(_ data: [UInt8]) -> Bool {
                    let alpha = Double(data[index + 3])
                    guard alpha > 0 else { return false }
                    let values = (0..<3).map { Double(data[index + $0]) / alpha }
                    return values.min()! >= 0.78 && values.max()! - values.min()! <= 0.22
                }
                if white(original) { whiteBefore += 1 }
                if white(pixels) { whiteAfter += 1 }
                if white(original) {
                    for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] where
                        (0..<width).contains(x + dx) && (0..<height).contains(y + dy) {
                        if original[((y + dy) * width + x + dx) * 4 + 3] == 0 {
                            selectedBoundaryWhite += 1
                            precondition(pixels[index + 3] == 0, "Every selected boundary white must become transparent")
                            break
                        }
                    }
                }
                if Array(original[index..<(index + 4)]) != Array(pixels[index..<(index + 4)]) {
                    changed += 1
                    let alpha = Double(original[index + 3])
                    precondition(alpha > 0)
                    let values = (0..<3).map { Double(original[index + $0]) / alpha }
                    precondition(values.min()! > 0.68 && values.max()! - values.min()! <= 0.22,
                                 "Only the white color range and its soft selection boundary may change")
                    var exteriorNearby = false
                    for dy in -3...3 {
                        for dx in -3...3 where abs(dx) + abs(dy) <= 3 &&
                            (0..<width).contains(x + dx) && (0..<height).contains(y + dy) {
                            exteriorNearby = exteriorNearby || original[((y + dy) * width + x + dx) * 4 + 3] == 0
                        }
                    }
                    precondition(exteriorNearby, "Interior facial and band pixels must be protected from the selection")
                }
                if white(original) && original[index..<(index + 4)] != pixels[index..<(index + 4)] {
                    precondition(pixels[index + 3] == 0, "Selected exterior white must be deleted, not recolored")
                }
                let renderedAlpha = displayed.colorAt(x: x, y: y)?.alphaComponent ?? -1
                precondition(abs(renderedAlpha - CGFloat(pixels[index + 3]) / 255) < 0.005,
                             "The running app must use the white-deleted body")
            }
        }
        NSLog("Hanging edge cleanup: changed=%d nearWhite=%d -> %d", changed, whiteBefore, whiteAfter)
        precondition(changed > 300 && selectedBoundaryWhite > 300 && whiteAfter < whiteBefore,
                     "Boundary white must be deleted while protected interior whites remain")
        var samples: [UInt8] = [
            0, 0, 0, 0, 255, 255, 255, 255, 255, 210, 170, 255, 255, 210, 170, 255,
            0, 0, 0, 0, 128, 128, 128, 128, 255, 210, 170, 255, 255, 210, 170, 255,
            0, 0, 0, 0, 210, 210, 210, 255, 255, 210, 170, 255, 240, 240, 240, 255,
            0, 0, 0, 0, 70, 90, 120, 255, 255, 210, 170, 255, 255, 210, 170, 255
        ]
        WhiteColorKey.apply(to: &samples, width: 4, height: 4)
        precondition(samples[7] == 0 && samples[23] == 0 && samples[39] == 0)
        precondition(Array(samples[44..<48]) == [240, 240, 240, 255], "Enclosed interior white must remain")
        precondition(Array(samples[52..<56]) == [70, 90, 120, 255])
        var connected = [UInt8](repeating: 255, count: 9 * 3 * 4)
        for row in [0, 2] {
            for column in 0..<9 {
                let index = (row * 9 + column) * 4
                connected[index + 1] = 210
                connected[index + 2] = 170
            }
        }
        for channel in 0..<4 { connected[9 * 4 + channel] = 0 }
        WhiteColorKey.apply(to: &connected, width: 9, height: 3)
        precondition(connected[(9 + 3) * 4 + 3] == 0)
        precondition(connected[(9 + 4) * 4 + 3] == 255,
                     "An exterior white path must not tunnel through an internal feature")
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
