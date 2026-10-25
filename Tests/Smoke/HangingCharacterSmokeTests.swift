import AppKit

extension PendantCoordinator {
    func smokeCheckHangingCharacter() {
        smokeCheckHangingEdges()
        smokeCheckHangingHalo()
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
        let heldHalo = simulation.haloAnimation.pose
        toggleVisible()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        precondition(simulation.haloAnimation.pose == heldHalo)
        toggleVisible()
        suspend()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        precondition(simulation.haloAnimation.pose == heldHalo)
        resume()
        precondition(simulation.ropeAnimation.localPose == sample)
        precondition(simulation.haloAnimation.pose == heldHalo)
        tick(at: lastTick + 0.05)
        precondition(simulation.ropeAnimation.elapsed > held)
        simulation.restartAnimation()
        reset()
        tick()
        NSLog("PASS: hanging local gestures, protected cross eyes/band/halo/attachment, scene mapping, idle playback and pause/resume")
    }

    private func smokeCheckHangingHalo() {
        func bitmap(_ image: NSImage) -> NSBitmapImageRep {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect hanging halo layers")
            }
            return NSBitmapImageRep(cgImage: cg)
        }
        let source = bitmap(artwork.hanging)
        let body = bitmap(artwork.hangingLayers.body)
        let halo = bitmap(artwork.hangingLayers.halo)
        var count = 0
        var soft = 0
        for y in 0..<source.pixelsHigh {
            for x in 0..<source.pixelsWide {
                guard let original = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = body.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let h = halo.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    preconditionFailure("Cannot normalize halo pixel colors")
                }
                precondition(!(b.alphaComponent > 0 && h.alphaComponent > 0), "Body and halo must not overlap")
                if h.alphaComponent > 0 {
                    if h != original || b.alphaComponent != 0 {
                        NSLog("Halo copy mismatch at %d,%d: %@ -> %@", x, y, original, h)
                        preconditionFailure("Halo pixels must be copied, not redrawn")
                    }
                    count += 1
                    if h.alphaComponent < 0.999 { soft += 1 }
                } else {
                    if b != original {
                        NSLog("Body copy mismatch at %d,%d: %@ -> %@", x, y, original, b)
                        preconditionFailure("Halo extraction must preserve every body pixel")
                    }
                }
            }
        }
        NSLog("Halo split pixel count=%d soft=%d", count, soft)
        precondition(count == 4814 && soft > 100)
        func renderedHalo(_ pose: HaloPose) -> NSBitmapImageRep {
            guard let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 160,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: result) else {
                preconditionFailure("Cannot render normal-size halo")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let rect = NSRect(x: 32, y: 29, width: 96, height: 102.4)
            let center = artwork.hangingLayers.center
            let pivot = CGPoint(x: rect.minX + rect.width * center.x, y: rect.minY + rect.height * center.y)
            context.cgContext.translateBy(x: pivot.x + pose.offset.x * 96, y: pivot.y + pose.offset.y * 96)
            context.cgContext.rotate(by: pose.angle)
            artwork.hangingLayers.halo.draw(in: rect.offsetBy(dx: -pivot.x, dy: -pivot.y))
            NSGraphicsContext.restoreGraphicsState()
            return result
        }
        func alphaCentroid(_ image: NSBitmapImageRep) -> (V2, CGFloat) {
            var sum = V2(0, 0)
            var total: CGFloat = 0
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    let alpha = image.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if alpha > 0 {
                        precondition(x > 0 && x < 159 && y > 0 && y < 159, "Halo must not clip at normal size")
                    }
                    sum = sum + V2(CGFloat(x), CGFloat(y)) * alpha
                    total += alpha
                }
            }
            precondition(total > 0)
            return (sum / total, total)
        }
        var movement = HaloAnimation(seed: 17)
        for _ in 0..<30 {
            movement.advance(elapsed: 1.0 / 60, localVelocity: V2(700, -500), characterActive: true)
        }
        let restHalo = alphaCentroid(renderedHalo(HaloPose()))
        let movedHalo = alphaCentroid(renderedHalo(movement.pose))
        let displacement = (movedHalo.0 - restHalo.0).magnitude
        precondition(displacement > 5, "Halo displacement must exceed 2.5 pt at normal 48 pt pendant size")
        precondition(abs(movedHalo.1 / restHalo.1 - 1) < 0.08, "Halo motion must not fade or clip the original ring")
        NSLog("PASS: halo normal-size movement %.2f px at 2x, full alpha and uncropped contour", displacement)
        let planeSheet = NSImage(size: NSSize(width: 1200, height: 780))
        planeSheet.lockFocus()
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 780).fill()
        var randomHalo = HaloAnimation(seed: 17)
        var activeFrames = 0
        var examples = 0
        var minTravel = V2(0, 0)
        var maxTravel = V2(0, 0)
        for _ in 0..<9000 {
            randomHalo.advance(elapsed: 1.0 / 60, localVelocity: V2(0, 0), characterActive: false)
            activeFrames = randomHalo.isAnimating ? activeFrames + 1 : 0
            guard activeFrames == 36, examples < 12 else { continue }
            let rendered = alphaCentroid(renderedHalo(randomHalo.pose))
            let travel = rendered.0 - restHalo.0
            minTravel = V2(min(minTravel.x, travel.x), min(minTravel.y, travel.y))
            maxTravel = V2(max(maxTravel.x, travel.x), max(maxTravel.y, travel.y))
            precondition(abs(rendered.1 / restHalo.1 - 1) < 0.08)
            let rect = NSRect(x: CGFloat(examples % 4) * 300 + 60,
                              y: 780 - CGFloat(examples / 4 + 1) * 260 + 45,
                              width: 176, height: 176 * 384 / 360)
            artwork.hangingCharacter.image(for: .rest).draw(in: rect)
            let center = artwork.hangingLayers.center
            let pivot = CGPoint(x: rect.minX + rect.width * center.x, y: rect.minY + rect.height * center.y)
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext.current!.cgContext
            context.translateBy(x: pivot.x + randomHalo.pose.offset.x * rect.width,
                                y: pivot.y + randomHalo.pose.offset.y * rect.width)
            context.rotate(by: randomHalo.pose.angle)
            artwork.hangingLayers.halo.draw(in: rect.offsetBy(dx: -pivot.x, dy: -pivot.y))
            NSGraphicsContext.restoreGraphicsState()
            String(format: "Idle %d  (%+.1f, %+.1f) pt", examples + 1,
                   randomHalo.pose.offset.x * 48, randomHalo.pose.offset.y * 48)
                .draw(at: NSPoint(x: rect.minX - 20, y: rect.minY - 25),
                      withAttributes: [.foregroundColor: NSColor.white])
            examples += 1
        }
        planeSheet.unlockFocus()
        precondition(examples == 12)
        precondition(minTravel.x < -2 && minTravel.y < -2 && maxTravel.x > 2 && maxTravel.y > 2,
                     "Random head-plane travel must render in both directions on both screen axes")
        NSLog("PASS: randomized halo rendered travel x=[%.2f,%.2f] y=[%.2f,%.2f] px at 2x",
              minTravel.x, maxTravel.x, minTravel.y, maxTravel.y)
        guard let planeTIFF = planeSheet.tiffRepresentation, let planeBitmap = NSBitmapImageRep(data: planeTIFF),
              let planePNG = planeBitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode randomized head-plane preview")
        }
        do {
            try planePNG.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("hanging-halo-plane.png"))
        } catch { preconditionFailure("Cannot save head-plane preview: \(error)") }
        var settings = self.settings
        do {
            try settings.set(140, for: .size)
            try settings.set(180, for: .length)
        } catch { preconditionFailure("Cannot configure halo preview: \(error)") }
        let preview = PendantSimulation(settings: settings, frameDurations: artwork.net.frameDurations,
                                        ropeFrameDurations: artwork.rope.frameDurations, animationSeed: 17)
        let anchor = V2(320, 500)
        preview.reset(anchor: anchor)
        let view = PigOverlayView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        var previous: HaloPose?
        var changed = 0
        var rebound = false
        var previews: [NSImage] = []
        for frame in 0..<240 {
            let time = Double(frame + 1) / 60
            let target = anchor + V2(min(90, max(0, time - 0.5) * 300), -min(80, max(0, time - 1.7) * 300))
            preview.advance(anchor: target, elapsed: 1.0 / 60)
            let scene = SceneSnapshot(simulation: preview, artwork: artwork, isVisible: true)
            precondition(scene.haloImage === artwork.hangingLayers.halo)
            precondition(scene.haloPose == preview.haloAnimation.pose)
            precondition(abs(scene.haloPose.angle) < 0.24 && scene.haloPose.offset.magnitude < 0.096)
            if let previous = previous {
                if scene.haloPose != previous { changed += 1 }
                precondition(abs(scene.haloPose.angle - previous.angle) < 0.05)
                rebound = rebound || (time > 1.2 && scene.haloPose.angle > 0.001)
            }
            previous = scene.haloPose
            if frame % 15 == 0 {
                view.scene = scene
                guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    preconditionFailure("Cannot render hanging halo scene")
                }
                view.cacheDisplay(in: view.bounds, to: image)
                let previewImage = NSImage(size: view.bounds.size)
                previewImage.addRepresentation(image)
                previews.append(previewImage)
                guard let png = image.representation(using: .png, properties: [:]) else {
                    preconditionFailure("Cannot encode hanging halo scene")
                }
                do {
                    try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent()
                        .appendingPathComponent(String(format: "hanging-halo-%04d.png", frame)))
                } catch { preconditionFailure("Cannot save halo preview: \(error)") }
            }
        }
        precondition(changed > 100 && rebound)
        let sheet = NSImage(size: NSSize(width: 1200, height: 1040))
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 1040).fill()
        for (index, image) in previews.enumerated() {
            let rect = NSRect(x: CGFloat(index % 4) * 300 + 5, y: 1040 - CGFloat(index / 4 + 1) * 260 + 25,
                              width: 290, height: 229)
            image.draw(in: rect)
            String(format: "%.2f s", Double(index) * 0.25).draw(at: NSPoint(x: rect.minX, y: rect.minY - 18),
                                                              withAttributes: [.foregroundColor: NSColor.darkGray])
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode halo scene contact sheet")
        }
        do {
            try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("hanging-halo-contact.png"))
        } catch { preconditionFailure("Cannot save halo scene contact sheet: \(error)") }
        NSLog("PASS: halo 4814 disjoint original pixels, soft alpha, body preservation, real scene lag/rebound, bounded motion")
    }
}
