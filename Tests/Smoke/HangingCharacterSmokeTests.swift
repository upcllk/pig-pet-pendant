import AppKit

extension PendantCoordinator {
    func smokeCheckHangingCharacter() {
        let character = artwork.hangingCharacter
        func bitmap(_ image: NSImage, displaySize: Bool = false) -> NSBitmapImageRep {
            if !displaySize {
                guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    preconditionFailure("Cannot inspect hanging character")
                }
                return NSBitmapImageRep(cgImage: cg)
            }
            guard let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 102,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: result) else {
                preconditionFailure("Cannot render hanging character at 48 pt")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 96, height: 102))
            NSGraphicsContext.restoreGraphicsState()
            return result
        }
        func centroid(_ image: NSBitmapImageRep, region: NSRect, dark: Bool) -> V2 {
            var sum = V2(0, 0)
            var total: CGFloat = 0
            for y in Int(region.minY * CGFloat(image.pixelsHigh))..<Int(region.maxY * CGFloat(image.pixelsHigh)) {
                for x in Int(region.minX * CGFloat(image.pixelsWide))..<Int(region.maxX * CGFloat(image.pixelsWide)) {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                        preconditionFailure("Cannot read hanging feature")
                    }
                    let contrast = dark ? 0.4 - max(color.redComponent, color.greenComponent, color.blueComponent)
                        : color.redComponent - color.greenComponent - 0.2
                    let weight = max(0, contrast) * color.alphaComponent
                    sum = sum + V2(CGFloat(x), CGFloat(y)) * weight
                    total += weight
                }
            }
            precondition(total > 0, "Cannot locate hanging feature")
            return sum / total
        }
        let restImage = character.image(for: .rest)
        let rest = bitmap(restImage)
        let displayRest = bitmap(restImage, displaySize: true)
        let sheet = NSImage(size: NSSize(width: 1800, height: 580))
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1800, height: 580).fill()
        for (row, gesture) in [LocalCharacterPose.Gesture.ears, .nuzzle].enumerated() {
            for (column, step) in stride(from: 0, through: LocalCharacterPose.steps, by: 9).enumerated() {
                let pose = LocalCharacterPose(gesture: gesture, step: step)
                let image = character.image(for: pose)
                let check = bitmap(image)
                for y in 0..<rest.pixelsHigh {
                    for x in 0..<rest.pixelsWide {
                        guard let color = rest.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                            preconditionFailure("Cannot inspect hanging protection mask")
                        }
                        let eye = color.alphaComponent > 0.9 &&
                            max(color.redComponent, color.greenComponent, color.blueComponent) < 0.35 &&
                            ((x > 220 && y > 85 && y < 130) || (x > 145 && x < 200 && y > 125 && y < 180))
                        let band = color.blueComponent > color.redComponent + 0.08 &&
                            color.blueComponent > color.greenComponent + 0.08
                        let haloOrAttachment = (x >= 235 && y >= 201) || y >= 305
                        if eye || band || haloOrAttachment {
                            if rest.colorAt(x: x, y: y) != check.colorAt(x: x, y: y) {
                                NSLog("Hanging protected pixel changed: %@ %d at %d,%d", String(describing: gesture), step, x, y)
                                preconditionFailure("Hanging gesture changed cross eyes, band, halo or attachment")
                            }
                        }
                    }
                }
                let rect = NSRect(x: CGFloat(column) * 200 + 12, y: 580 - CGFloat(row + 1) * 280 + 65,
                                  width: 176, height: 176 * 384 / 360)
                image.draw(in: rect)
                image.draw(in: NSRect(x: rect.minX + 65, y: rect.minY - 53, width: 48, height: 51.2))
                "\(gesture) \(step)/72".draw(at: NSPoint(x: rect.minX, y: rect.minY - 65),
                                             withAttributes: [.foregroundColor: NSColor.darkGray])
            }
        }
        sheet.unlockFocus()
        for (gesture, step, region, dark) in [
            (LocalCharacterPose.Gesture.ears, 27, NSRect(x: 0.72, y: 0.23, width: 0.18, height: 0.19), false),
            (.nuzzle, 36, NSRect(x: 0.42, y: 0.13, width: 0.24, height: 0.17), true)
        ] {
            let image = character.image(for: LocalCharacterPose(gesture: gesture, step: step))
            let movement = (centroid(bitmap(image, displaySize: true), region: region, dark: dark)
                            - centroid(displayRest, region: region, dark: dark)).magnitude
            NSLog("Hanging %@ at 48 pt: %.2f px movement (2x)", String(describing: gesture), movement)
            precondition(movement >= 0.7, "Hanging gesture must be visible at normal size")
        }
        precondition(character.image(for: LocalCharacterPose(gesture: .blink, step: 27)) ===
                     character.image(for: LocalCharacterPose(gesture: .ears, step: 27)),
                     "Cross eyes must use an ear gesture instead of blinking")
        guard let tiff = sheet.tiffRepresentation, let image = NSBitmapImageRep(data: tiff),
              let png = image.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode hanging pose atlas")
        }
        do {
            try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("hanging-local-poses.png"))
        } catch { preconditionFailure("Cannot save hanging pose atlas: \(error)") }

        var sawEar = false
        var sawNose = false
        for _ in 0..<1800 {
            tick(at: lastTick + 1.0 / 60)
            let pose = simulation.ropeAnimation.localPose
            sawEar = sawEar || (pose != .rest && pose.gesture != .nuzzle)
            sawNose = sawNose || pose.nuzzle > 0.5
            precondition(sceneSnapshot().displayImage === character.image(for: pose))
        }
        precondition(sawEar && sawNose)
        let held = simulation.ropeAnimation.elapsed
        let sample = simulation.ropeAnimation.localPose
        toggleVisible()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        toggleVisible()
        suspend()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        resume()
        precondition(simulation.ropeAnimation.localPose == sample)
        tick(at: lastTick + 0.05)
        precondition(simulation.ropeAnimation.elapsed > held)
        simulation.restartAnimation()
        reset()
        tick()
        NSLog("PASS: hanging local gestures, protected cross eyes/band/halo/attachment, scene mapping, idle playback and pause/resume")
    }
}
