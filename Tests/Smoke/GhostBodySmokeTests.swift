import AppKit

extension PendantCoordinator {
    func smokeCheckGhostBody() {
        let character = artwork.ghostCharacters[0]
        func raster(_ image: NSImage, width: Int) -> NSBitmapImageRep {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width * 3 / 2,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                preconditionFailure("Cannot rasterize ghost body motion")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: width * 3 / 2))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        let regions = [
            CGRect(x: 0.118, y: 0.164, width: 0.22, height: 0.148),
            CGRect(x: 0.525, y: 0.250, width: 0.214, height: 0.140),
            CGRect(x: 0.075, y: 0.526, width: 0.26, height: 0.190),
            CGRect(x: 0.550, y: 0.531, width: 0.28, height: 0.190)
        ]
        func pinkCenter(_ bitmap: NSBitmapImageRep, region: CGRect) -> CGPoint {
            var sum = CGPoint.zero
            var total = 0.0
            for y in Int(region.minY * Double(bitmap.pixelsHigh))..<Int(region.maxY * Double(bitmap.pixelsHigh)) {
                for x in Int(region.minX * Double(bitmap.pixelsWide))..<Int(region.maxX * Double(bitmap.pixelsWide)) {
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let weight = max(0, Double(color.redComponent - color.greenComponent) - 0.25)
                        * max(0, Double(color.blueComponent - color.greenComponent) - 0.12) * Double(color.alphaComponent)
                    sum.x += Double(x) * weight
                    sum.y += Double(y) * weight
                    total += weight
                }
            }
            precondition(total > 0, "Each original pink ear and U-shaped hand must remain visible")
            return CGPoint(x: sum.x / total, y: sum.y / total)
        }
        func bottom(_ bitmap: NSBitmapImageRep, x: Int) -> Int {
            for y in (0..<bitmap.pixelsHigh).reversed() {
                if bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.5 { return y }
            }
            preconditionFailure("Missing ghost hem contour")
        }
        let rest = raster(character.image(for: GhostBodyPose()), width: 384)
        let normalRest = raster(character.image(for: GhostBodyPose()), width: 96)
        let centers = regions.map { pinkCenter(normalRest, region: $0) }
        var movement = [Double](repeating: 0, count: 4)
        var hemMovement = 0
        let sheet = NSImage(size: NSSize(width: 960, height: 640))
        sheet.lockFocus()
        for row in 0..<2 {
            (row == 0 ? NSColor.black : NSColor.white).setFill()
            CGRect(x: 0, y: row * 320, width: 960, height: 320).fill()
        }
        sheet.unlockFocus()
        let poses = stride(from: 0, through: 144, by: 12).map { GhostBodyPose(step: $0) } +
            [GhostBodyPose(drift: -16), GhostBodyPose(drift: 16),
             GhostBodyPose(step: 72, drift: -16), GhostBodyPose(step: 72, drift: 16)]
        for (index, pose) in poses.enumerated() {
            let image = character.image(for: pose)
            precondition(image === character.image(for: pose), "Repeated poses must use the bounded cache")
            let current = raster(image, width: 384)
            let normal = raster(image, width: 96)
            for (feature, region) in regions.enumerated() {
                let center = pinkCenter(normal, region: region)
                movement[feature] = max(movement[feature], hypot(center.x - centers[feature].x, center.y - centers[feature].y))
            }
            for x in 15..<85 {
                hemMovement = max(hemMovement, abs(bottom(normal, x: x) - bottom(normalRest, x: x)))
            }
            for y in 0..<576 {
                for x in 0..<384 {
                    let point = CGPoint(x: (Double(x) + 0.5) / 384, y: (Double(y) + 0.5) / 576)
                    let activeRegion = point.y > 0.75 || regions.contains { $0.contains(point) }
                    if !activeRegion {
                        var a = [Int](repeating: 0, count: 4)
                        var b = a
                        current.getPixel(&a, atX: x, y: y)
                        rest.getPixel(&b, atX: x, y: y)
                        precondition(a == b, "Local motion must preserve non-action pixels")
                    }
                    if x == 0 || x == 383 || y == 0 || y == 575 {
                        if current.colorAt(x: x, y: y)!.alphaComponent != 0 {
                            NSLog("Ghost canvas clipping step=%d drift=%d pixel=%d,%d", pose.step, pose.drift, x, y)
                            preconditionFailure("Moving body must fit the canvas")
                        }
                    }
                    if (0.17...0.79).contains(point.x) && (0.53...0.72).contains(point.y) {
                        if current.colorAt(x: x, y: y)!.alphaComponent <= 0.98 {
                            NSLog("Ghost body alpha step=%d drift=%d pixel=%d,%d alpha=%.3f",
                                  pose.step, pose.drift, x, y, current.colorAt(x: x, y: y)!.alphaComponent)
                            preconditionFailure("Hand motion must not open transparent cracks inside the body")
                        }
                    }
                }
            }
            // Eyes and nose stay fixed even while the ears and hands move.
            for region in [CGRect(x: 0.21, y: 0.325, width: 0.10, height: 0.065),
                           CGRect(x: 0.46, y: 0.363, width: 0.085, height: 0.06),
                           CGRect(x: 0.19, y: 0.40, width: 0.24, height: 0.11)] {
                for y in Int(region.minY * 576)..<Int(region.maxY * 576) {
                    for x in Int(region.minX * 384)..<Int(region.maxX * 384) {
                        precondition(current.colorAt(x: x, y: y) == rest.colorAt(x: x, y: y),
                                     "Body motion must not distort the blink keys or nose")
                    }
                }
            }
            if index % 2 == 0 && index < 12 {
                sheet.lockFocus()
                for row in 0..<2 {
                    let rect = CGRect(x: index / 2 * 160 + 10, y: row * 320 + 95, width: 140, height: 210)
                    image.draw(in: rect)
                    artwork.ghostHalo.draw(in: rect)
                    let small = CGRect(x: rect.minX + 46, y: CGFloat(row * 320 + 12), width: 48, height: 72)
                    image.draw(in: small)
                    artwork.ghostHalo.draw(in: small)
                }
                sheet.unlockFocus()
            }
        }
        for (index, distance) in movement.enumerated() {
            NSLog("Ghost body feature %d peak pink centroid movement: %.2f pixels at 48 pt / 2x", index, distance)
            precondition(distance > 0.45, "Ears and hands must visibly move at normal size")
        }
        NSLog("Ghost hem peak contour movement: %d pixels at 48 pt / 2x", hemMovement)
        precondition(hemMovement >= 2, "Hem motion must change the actual normal-size contour")
        guard let data = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode body motion contact sheet")
        }
        do {
            try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("ghost-body-motion-contact.png"))
        } catch { preconditionFailure("Cannot save ghost body motion contact sheet: \(error)") }
        NSLog("PASS: ghost ear/hand local movement, waving hem contour, fixed face, bounded pose cache and black/white normal-size contact sheet")
    }
}
