import AppKit

extension PendantCoordinator {
    func smokeCheckNetEdges() {
        let url = Bundle.main.resourceURL!.appendingPathComponent("net-pig.png")
        guard let original = AnimatedArtwork(url: url) else { preconditionFailure("Cannot inspect original net frames") }
        precondition(original.frameDurations == artwork.net.frameDurations)
        func raster(_ image: NSImage) -> [UInt8] {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot decode net frame")
            }
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                                              bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                return true
            }
            precondition(success)
            return bytes
        }
        var totalChanged = 0
        var changedFrames = 0
        var paleBefore = 0
        var paleAfter = 0
        for index in original.frames.indices {
            let before = raster(original.frames[index])
            var after = before
            NetArtworkCleanup.apply(to: &after, width: 207, height: 200)
            let displayed = raster(artwork.net.frames[index])
            var changed = 0
            for pixel in 0..<(207 * 200) {
                let offset = pixel * 4
                func pale(_ bytes: [UInt8]) -> Bool {
                    let alpha = Double(bytes[offset + 3])
                    guard alpha > 0 else { return false }
                    let red = Double(bytes[offset]) / alpha
                    let green = Double(bytes[offset + 1]) / alpha
                    let blue = Double(bytes[offset + 2]) / alpha
                    return min(red, green, blue) > 0.75 && max(red, green, blue) - min(red, green, blue) < 0.18 &&
                        blue >= red - 0.015 && green >= red - 0.015
                }
                if pale(before) { paleBefore += 1 }
                if pale(after) { paleAfter += 1 }
                if before[offset + 3] == 0 {
                    precondition(after[offset + 3] == 0, "Normal transparent net holes must not be filled")
                }
                precondition(after[offset + 3] <= before[offset + 3], "Net cleanup must not expand the mesh")
                if before[offset..<(offset + 4)] != after[offset..<(offset + 4)] {
                    changed += 1
                    let alpha = Double(before[offset + 3])
                    let red = Double(before[offset]) / alpha
                    let green = Double(before[offset + 1]) / alpha
                    let blue = Double(before[offset + 2]) / alpha
                    precondition(min(red, green, blue) > 0.60 && max(red, green, blue) - min(red, green, blue) < 0.18,
                                 "Pig expressions and colored artwork must not be repainted")
                    precondition(blue >= red - 0.015 && green >= red - 0.015,
                                 "Warm pig colors must not be replaced with mesh colors")
                }
                for channel in 0..<4 {
                    precondition(abs(Int(displayed[offset + channel]) - Int(after[offset + channel])) <= 2,
                                 "The app must use the cleaned frame, not only an offline preview")
                }
            }
            if changed > 0 { changedFrames += 1 }
            totalChanged += changed
        }
        NSLog("Net edge cleanup: %d pixels over %d/%d original frames", totalChanged, changedFrames, original.frames.count)
        NSLog("Net pale neutral/blue pixels: %d -> %d", paleBefore, paleAfter)
        precondition(changedFrames == 62 && totalChanged > 500)
        precondition(paleAfter < paleBefore / 2, "Net white contamination must be measurably reduced")
        let sheet = NSImage(size: NSSize(width: 1200, height: 1400))
        sheet.lockFocus()
        for (row, frame) in [0, 15, 30, 45].enumerated() {
            for column in 0..<4 {
                let black = column < 2
                (black ? NSColor.black : NSColor.white).setFill()
                NSRect(x: column * 300, y: row * 350, width: 300, height: 350).fill()
                let image = column.isMultiple(of: 2) ? original.frames[frame] : artwork.net.frames[frame]
                image.draw(in: NSRect(x: column * 300 + 5, y: row * 350 + 40, width: 290, height: 280))
                "\(column.isMultiple(of: 2) ? "Before" : "Cleaned") frame \(frame)"
                    .draw(at: NSPoint(x: column * 300 + 10, y: row * 350 + 10),
                          withAttributes: [.foregroundColor: black ? NSColor.white : NSColor.black])
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode net edge comparison")
        }
        do {
            try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("net-edge-comparison.png"))
        } catch { preconditionFailure("Cannot save net edge comparison: \(error)") }
    }
}
