import AppKit
import ImageIO
import UniformTypeIdentifiers

func smokeCheckGhostHemLoop(name: String, aspectRatio: Double,
                           image: (GhostBodyPose) -> NSImage) {
    let width = 96
    let height = Int(Double(width) * aspectRatio)
    func raster(_ image: NSImage) -> [UInt8] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("Cannot inspect \(name) hem loop")
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        precondition(success)
        return bytes
    }
    func difference(_ first: [UInt8], _ second: [UInt8], alphaOnly: Bool) -> Double {
        var total = 0
        for offset in stride(from: 0, to: first.count, by: 4) {
            for channel in (alphaOnly ? 3 : 0)..<4 {
                total += abs(Int(first[offset + channel]) - Int(second[offset + channel]))
            }
        }
        return Double(total) / Double(width * height * (alphaOnly ? 1 : 4))
    }

    let previewURL = SmokeArtifactDirectory.url.appendingPathComponent("\(name)-hem-loop-preview.png")
    guard let destination = CGImageDestinationCreateWithURL(
        previewURL as CFURL, UTType.png.identifier as CFString, 64, nil
    ) else { preconditionFailure("Cannot create \(name) hem loop preview") }
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
    ] as CFDictionary)

    // Exercise both the idle fast path and the full gesture rendering path.
    for base in [GhostBodyPose(), GhostBodyPose(step: 54, drift: 16)] {
        let frames = (0..<GhostBodyPose.hemSteps).map { step -> [UInt8] in
            var pose = base
            pose.hemStep = step
            let rendered = image(pose)
            if base.step == 0 && step % 3 == 0 {
                let canvas = NSImage(size: NSSize(width: 400, height: 300))
                canvas.lockFocus()
                for side in 0..<2 {
                    (side == 0 ? NSColor.white : NSColor.black).setFill()
                    CGRect(x: side * 200, y: 0, width: 200, height: 300).fill()
                    for size in [48.0, 140.0] {
                        rendered.draw(in: CGRect(x: Double(side * 200) + (200 - size) / 2,
                                                 y: size == 48 ? 12 : 88,
                                                 width: size, height: size * aspectRatio))
                    }
                }
                canvas.unlockFocus()
                guard let cg = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    preconditionFailure("Cannot render \(name) loop preview")
                }
                CGImageDestinationAddImage(destination, cg, [kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: 0.05,
                    kCGImagePropertyAPNGUnclampedDelayTime: 0.05
                ]] as CFDictionary)
            }
            return raster(rendered)
        }
        for alphaOnly in [false, true] {
            let interior = (2..<(frames.count - 1)).map {
                difference(frames[$0 - 1], frames[$0], alphaOnly: alphaOnly)
            }.max()!
            let entering = difference(frames.last!, frames[0], alphaOnly: alphaOnly)
            let leaving = difference(frames[0], frames[1], alphaOnly: alphaOnly)
            NSLog("%@ hem loop step=%d alphaOnly=%d: interior max %.6f, entering %.6f, leaving %.6f",
                  name, base.step, alphaOnly ? 1 : 0, interior, entering, leaving)
            precondition(max(entering, leaving) <= interior * 1.25 + 0.001,
                         "\(name) must not pop into or out of phase zero; check both color and silhouette")
        }
        var repeated = base
        repeated.hemStep = GhostBodyPose.hemSteps
        precondition(raster(image(repeated)) == frames[0],
                     "\(name) phase zero and a full turn must render identically")
    }
    precondition(CGImageDestinationFinalize(destination), "Cannot finalize \(name) hem preview")
    guard let exported = CGImageSourceCreateWithURL(previewURL as CFURL, nil) else {
        preconditionFailure("Cannot reopen \(name) hem preview")
    }
    precondition(CGImageSourceGetCount(exported) == 64)
    let seamSteps = [189, 190, 191, 0, 1, 2, 3]
    let sheet = NSImage(size: NSSize(width: seamSteps.count * 160, height: 640))
    sheet.lockFocus()
    for row in 0..<2 {
        (row == 0 ? NSColor.white : NSColor.black).setFill()
        CGRect(x: 0, y: row * 320, width: seamSteps.count * 160, height: 320).fill()
        for (index, step) in seamSteps.enumerated() {
            let rendered = image(GhostBodyPose(hemStep: step))
            for size in [48.0, 140.0] {
                rendered.draw(in: CGRect(x: Double(index * 160) + (160 - size) / 2,
                                         y: Double(row * 320) + (size == 48 ? 30 : 105),
                                         width: size, height: size * aspectRatio))
            }
            "phase \(step)".draw(at: CGPoint(x: index * 160 + 40, y: row * 320 + 8),
                                withAttributes: [.foregroundColor: row == 0 ? NSColor.black : NSColor.white])
        }
    }
    sheet.unlockFocus()
    guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        preconditionFailure("Cannot encode \(name) seam contact sheet")
    }
    do {
        try png.write(to: SmokeArtifactDirectory.url.appendingPathComponent("\(name)-hem-seam-contact.png"))
    } catch { preconditionFailure("Cannot save \(name) seam contact sheet: \(error)") }
    NSLog("PASS: %@ full hem cycle, both seam edges, gesture path, color/alpha continuity and black/white normal-size preview", name)
}
