import AppKit

extension PendantCoordinator {
    func smokeCheckLocalCharacters() {
        let character = mode == .balloon ? artwork.balloonCharacter : artwork.bambooCharacter
        func pose(_ gesture: LocalCharacterPose.Gesture, _ phase: Double) -> LocalCharacterPose {
            LocalCharacterPose(gesture: gesture, step: Int((phase * Double(LocalCharacterPose.steps)).rounded()))
        }
        func bitmap(_ pose: LocalCharacterPose) -> NSBitmapImageRep {
            guard let image = character.image(for: pose).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect local character pose")
            }
            return NSBitmapImageRep(cgImage: image)
        }
        func eyeBounds(_ image: NSBitmapImageRep) -> NSRect {
            let region = mode == .balloon ? NSRect(x: 0.16, y: 0.43, width: 0.13, height: 0.18)
                : NSRect(x: 0.065, y: 0.30, width: 0.075, height: 0.16)
            var bounds = NSRect.null
            for y in Int(region.minY * CGFloat(image.pixelsHigh))..<Int(region.maxY * CGFloat(image.pixelsHigh)) {
                for x in Int(region.minX * CGFloat(image.pixelsWide))..<Int(region.maxX * CGFloat(image.pixelsWide)) {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.9,
                          max(color.redComponent, color.greenComponent, color.blueComponent) < 0.3 else { continue }
                    bounds = bounds.union(NSRect(x: x, y: y, width: 1, height: 1))
                }
            }
            return bounds
        }
        let rest = bitmap(.rest)
        let open = eyeBounds(rest)
        let closedBitmap = bitmap(pose(.blink, 0.4))
        let closed = eyeBounds(closedBitmap)
        precondition(character.image(for: pose(.blink, 0.32)) === character.image(for: pose(.blink, 0.48)),
                     "The closed-eye hold should reuse the same rendered pose")
        precondition(!open.isNull && !closed.isNull && closed.height < open.height * 0.3,
                     "Local blink must compress the eye, not move the whole character")
        precondition(closed.width >= open.width * 0.8)
        let noseRegion = mode == .balloon ? NSRect(x: 0.12, y: 0.59, width: 0.50, height: 0.30)
            : NSRect(x: 0.06, y: 0.44, width: 0.21, height: 0.22)
        for y in Int(noseRegion.minY * CGFloat(rest.pixelsHigh))..<Int(noseRegion.maxY * CGFloat(rest.pixelsHigh)) {
            for x in Int(noseRegion.minX * CGFloat(rest.pixelsWide))..<Int(noseRegion.maxX * CGFloat(rest.pixelsWide)) {
                guard let color = rest.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.9, color.redComponent > 0.85, color.greenComponent < 0.6 else { continue }
                if rest.colorAt(x: x, y: y) != closedBitmap.colorAt(x: x, y: y) {
                    NSLog("Blink touches nose in %@ at %d,%d (%@ -> %@)", mode.rawValue, x, y,
                          String(describing: rest.colorAt(x: x, y: y)),
                          String(describing: closedBitmap.colorAt(x: x, y: y)))
                    preconditionFailure("Blink deformation must not pinch the neighboring pink nose")
                }
            }
        }
        func displayBitmap(_ pose: LocalCharacterPose) -> NSBitmapImageRep {
            let image = character.image(for: pose)
            let height = Int((96 * image.size.height / image.size.width).rounded())
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                preconditionFailure("Cannot render character at 48 pt / 2x")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 96, height: height),
                       from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        func featureCentroid(_ image: NSBitmapImageRep, region: NSRect, pink: Bool) -> V2 {
            var sum = V2(0, 0)
            var total: CGFloat = 0
            for y in Int(region.minY * CGFloat(image.pixelsHigh))..<Int(region.maxY * CGFloat(image.pixelsHigh)) {
                for x in Int(region.minX * CGFloat(image.pixelsWide))..<Int(region.maxX * CGFloat(image.pixelsWide)) {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let contrast = pink ? color.redComponent - color.greenComponent - 0.2
                        : 0.4 - max(color.redComponent, color.greenComponent, color.blueComponent)
                    let weight = max(0, contrast) * color.alphaComponent
                    sum = sum + V2(CGFloat(x), CGFloat(y)) * weight
                    total += weight
                }
            }
            precondition(total > 0, "Cannot locate original feature at actual display size")
            return sum / total
        }
        let displayRest = displayBitmap(.rest)
        var heights = Set<CGFloat>()
        for step in 0...LocalCharacterPose.steps {
            let bounds = eyeBounds(displayBitmap(LocalCharacterPose(gesture: .blink, step: step)))
            heights.insert(bounds.isNull ? 0 : bounds.height)
        }
        precondition(heights.count >= 5, "Blink needs several rendered eye heights at 48 pt, not just open / closed")
        let earRegion = NSRect(x: 0, y: 0, width: 0.25, height: mode == .balloon ? 0.43 : 0.30)
        let earMotion = (featureCentroid(displayBitmap(pose(.ears, 0.375)), region: earRegion, pink: true)
                         - featureCentroid(displayRest, region: earRegion, pink: true)).magnitude
        let noseMotion = (featureCentroid(displayBitmap(pose(.nuzzle, 0.5)), region: noseRegion, pink: false)
                          - featureCentroid(displayRest, region: noseRegion, pink: false)).magnitude
        NSLog("Local gesture at 48 pt %@: eye heights=%d, ear movement=%.2f px, nose movement=%.2f px (2x)",
              mode.rawValue, heights.count, earMotion, noseMotion)
        precondition(earMotion >= 1.2 && noseMotion >= 1.0,
                     "Local gestures must move real feature pixels at normal pendant size")

        let sheet = NSImage(size: NSSize(width: 1800, height: 750))
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1800, height: 750).fill()
        let started = ProcessInfo.processInfo.systemUptime
        for (row, gesture) in [LocalCharacterPose.Gesture.blink, .ears, .nuzzle].enumerated() {
            for (column, step) in stride(from: 0, through: LocalCharacterPose.steps, by: 9).enumerated() {
                let pose = LocalCharacterPose(gesture: gesture, step: step)
                let image = character.image(for: pose)
                let check = bitmap(pose)
                if (gesture == .ears && step == 27) || (gesture == .nuzzle && step == 36) {
                    var changed = 0
                    for y in stride(from: 0, to: Int(CGFloat(check.pixelsHigh) * 0.75), by: 2) {
                        for x in stride(from: 0, to: check.pixelsWide, by: 2) {
                            if check.colorAt(x: x, y: y) != rest.colorAt(x: x, y: y) { changed += 1 }
                        }
                    }
                    precondition(changed > 20, "Ears and nose must change actual local pixels")
                }
                let protectedY = mode == .bamboo ? 0.75 : 0.9
                for y in Int(CGFloat(check.pixelsHigh) * protectedY)..<check.pixelsHigh {
                    for x in 0..<check.pixelsWide {
                        precondition(check.colorAt(x: x, y: y) == rest.colorAt(x: x, y: y),
                                     "Local gestures must preserve the feet / bottom attachment pixels")
                    }
                }
                let rect = NSRect(x: CGFloat(column) * 200 + 12, y: 750 - CGFloat(row + 1) * 250 + 30,
                                  width: 176, height: 176 * image.size.height / image.size.width)
                image.draw(in: rect)
                "\(gesture) \(step)/\(LocalCharacterPose.steps)".draw(at: NSPoint(x: rect.minX, y: rect.minY - 20),
                                             withAttributes: [.foregroundColor: NSColor.darkGray])
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode local gesture atlas")
        }
        let directory = Bundle.main.bundleURL.deletingLastPathComponent()
        do {
            try png.write(to: directory.appendingPathComponent("\(mode.rawValue)-local-poses.png"))
        } catch { preconditionFailure("Cannot save local gesture atlas: \(error)") }
        NSLog("Local gesture atlas %@ generated in %.3f s", mode.rawValue, ProcessInfo.processInfo.systemUptime - started)

        var previewSettings = settings
        do {
            try previewSettings.set(120, for: .size)
            try previewSettings.set(180, for: .length)
        } catch { preconditionFailure("Cannot set local animation preview: \(error)") }
        previewSettings.setCount(8)
        let preview = PendantSimulation(settings: previewSettings, frameDurations: netAnimation.frameDurations,
                                        ropeFrameDurations: ropeAnimation.frameDurations, animationSeed: 2026)
        let anchor = V2(350, mode == .balloon ? 220 : 550)
        preview.reset(anchor: anchor)
        let view = PigOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 760))
        var sawMotion = false
        var sawFall = false
        for frame in 0..<600 {
            let time = Double(frame) / 60
            let position = anchor + V2(min(60, max(0, time - 3) * 300), -min(80, max(0, time - 6) * 400))
            preview.advance(anchor: position, elapsed: 1.0 / 60)
            let players = mode == .balloon ? preview.balloonAnimations : [preview.ropeAnimation]
            sawMotion = sawMotion || players.contains { $0.action == .moving }
            sawFall = sawFall || players.contains { $0.action == .falling }
            if frame % 12 == 0 {
                let scene = SceneSnapshot(simulation: preview, artwork: artwork, isVisible: true)
                if mode == .balloon {
                    precondition(scene.ropes.count == 8 && scene.ropes.allSatisfy { $0.characterImage != nil })
                    for index in scene.ropes.indices {
                        precondition(scene.ropes[index].characterImage ===
                                     artwork.balloonCharacter.image(for: players[index].localPose))
                    }
                }
                view.scene = scene
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    preconditionFailure("Cannot render local character scene")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    preconditionFailure("Cannot encode local character scene")
                }
                do {
                    try png.write(to: directory.appendingPathComponent(String(format: "%@-local-%04d.png", mode.rawValue, frame)))
                } catch { preconditionFailure("Cannot save local scene: \(error)") }
            }
        }
        precondition(sawMotion && sawFall)
        tick(at: lastTick + 0.05)
        let held = simulation.ropeAnimation.elapsed
        let balloonTimes = simulation.balloonAnimations.map(\.elapsed)
        toggleVisible()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        precondition(simulation.balloonAnimations.map(\.elapsed) == balloonTimes)
        toggleVisible()
        suspend()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        precondition(simulation.balloonAnimations.map(\.elapsed) == balloonTimes)
        resume()
        tick(at: lastTick + 0.05)
        if mode == .balloon {
            precondition(zip(simulation.balloonAnimations.map(\.elapsed), balloonTimes).allSatisfy { $0 > $1 })
        } else {
            precondition(simulation.ropeAnimation.elapsed > held)
        }
        simulation.restartAnimation()
        reset()
        tick()
        NSLog("PASS: %@ local blink/ear/nose pixels, protected attachments, independent scene images, state reactions, hidden/sleep pause and resume", mode.rawValue)
    }
}
