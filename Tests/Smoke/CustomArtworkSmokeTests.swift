import AppKit

extension PendantCoordinator {
    func smokeCheckCustomArtworkResources() {
        guard let originalHanging = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("hanging-pig-custom.png")) else {
            preconditionFailure("Cannot read supplied hanging image")
        }
        func rgba(_ image: NSImage) -> [UInt8] {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect band color")
            }
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let success = bytes.withUnsafeMutableBytes { data -> Bool in
                guard let context = CGContext(data: data.baseAddress, width: cg.width, height: cg.height,
                                              bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                return true
            }
            precondition(success)
            return bytes
        }
        let uncolored = rgba(originalHanging)
        let colored = rgba(artwork.hanging)
        let reference = rgba(artwork.rope.frames[0])
        let referenceIndex = (70 * 297 + 180) * 4
        let referenceSum = Double(reference[referenceIndex]) + Double(reference[referenceIndex + 1]) +
            Double(reference[referenceIndex + 2])
        var bandChanges = 0
        for pixel in 0..<(768 * 768) {
            let index = pixel * 4
            if uncolored[index + 3] != colored[index + 3] {
                NSLog("Band alpha mismatch at %d,%d: %d -> %d", pixel % 768, pixel / 768,
                      uncolored[index + 3], colored[index + 3])
                preconditionFailure("Band tint must not alter the silhouette or alpha")
            }
            if uncolored[index..<(index + 3)] != colored[index..<(index + 3)] {
                let alpha = Double(uncolored[index + 3])
                let r = Double(uncolored[index]) / max(1, alpha)
                let g = Double(uncolored[index + 1]) / max(1, alpha)
                let b = Double(uncolored[index + 2]) / max(1, alpha)
                let inBand = (Int(768 * 0.19)..<Int(768 * 0.78)).contains(pixel % 768) &&
                             (Int(768 * 0.30)..<Int(768 * 0.69)).contains(pixel / 768) &&
                             b > r + 0.02 && b > g + 0.04
                if !inBand {
                    NSLog("Unexpected band tint change at %d,%d: %@ -> %@", pixel % 768, pixel / 768,
                          Array(uncolored[index..<(index + 4)]).description, Array(colored[index..<(index + 4)]).description)
                    preconditionFailure("Only the purple band may be recolored")
                }
                if alpha > 128 {
                    let sum = Double(colored[index]) + Double(colored[index + 1]) + Double(colored[index + 2])
                    for channel in 0..<3 {
                        if abs(Double(colored[index + channel]) / sum
                                 - Double(reference[referenceIndex + channel]) / referenceSum) >= 0.01 {
                            NSLog("Band hue mismatch: %@ vs reference %@", Array(colored[index..<(index + 3)]).description,
                                  Array(reference[referenceIndex..<(referenceIndex + 3)]).description)
                            preconditionFailure("Band hue must match the rope reference while retaining shading")
                        }
                    }
                }
                bandChanges += 1
            }
        }
        precondition(bandChanges > 1000)
        NSLog("PASS: hanging band matches original rope brown, %d tinted pixels, all other source RGBA preserved", bandChanges)
        precondition(artwork.hanging.size == NSSize(width: 768, height: 768))
        precondition(artwork.netImage.size == NSSize(width: 512, height: 768))
        guard let cg = artwork.hanging.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bodyCG = artwork.hangingLayers.body.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let haloCG = artwork.hangingLayers.halo.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("Cannot inspect custom source layers")
        }
        let original = NSBitmapImageRep(cgImage: cg)
        let body = NSBitmapImageRep(cgImage: bodyCG)
        let halo = NSBitmapImageRep(cgImage: haloCG)
        var haloPixels = 0
        for y in 0..<768 {
            for x in 0..<768 {
                let a = original.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let b = body.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let h = halo.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                precondition(!(b.alphaComponent > 0 && h.alphaComponent > 0))
                precondition((h.alphaComponent > 0 ? h : b) == a,
                             "Custom source pixels must be preserved, including pale edge pixels")
                if h.alphaComponent > 0 { haloPixels += 1 }
            }
        }
        precondition(haloPixels > 4000)
        guard let netSource = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("net-pig-custom.png")),
              let netCG = netSource.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropCG = artwork.netImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("Cannot inspect net crop")
        }
        let full = NSBitmapImageRep(cgImage: netCG)
        let crop = NSBitmapImageRep(cgImage: cropCG)
        var removedEyePixels = 0
        for y in 0..<768 {
            for x in 0..<768 {
                if x < 256 {
                    if full.colorAt(x: x, y: y)!.alphaComponent > 0.02 {
                        NSLog("Net crop margin has source pixel at %d,%d alpha=%.4f", x, y,
                              full.colorAt(x: x, y: y)!.alphaComponent)
                        preconditionFailure("Cropping nearly transparent padding must not cut off visible artwork")
                    }
                } else if (550..<605).contains(x) && (398..<448).contains(y) {
                    let sourcePixel = full.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let resultPixel = crop.colorAt(x: x - 256, y: y)!.usingColorSpace(.deviceRGB)!
                    let wasEye = sourcePixel.alphaComponent > 0.1 &&
                        sourcePixel.redComponent < 0.68 &&
                        sourcePixel.greenComponent < 0.58 &&
                        sourcePixel.blueComponent < 0.50
                    if wasEye {
                        precondition(resultPixel.redComponent > resultPixel.greenComponent &&
                                     resultPixel.alphaComponent == sourcePixel.alphaComponent,
                                     "Only the open black eye is filled with the surrounding skin color")
                        removedEyePixels += 1
                    } else {
                        precondition(sourcePixel == resultPixel,
                                     "Only the indicated black eye may change; retain the mesh and nearby face pixels")
                    }
                } else {
                    if full.colorAt(x: x, y: y) != crop.colorAt(x: x - 256, y: y) {
                        NSLog("Net crop color mismatch at %d,%d: %@ -> %@", x, y,
                              String(describing: full.colorAt(x: x, y: y)),
                              String(describing: crop.colorAt(x: x - 256, y: y)))
                        preconditionFailure("Net crop must preserve source pixels")
                    }
                }
            }
        }
        precondition(removedEyePixels > 250)
        NSLog("PASS: user 768px artwork, source-preserving disjoint halo/body layers (%d halo pixels), only indicated net eye removed (%d pixels)",
              haloPixels, removedEyePixels)
    }

    func smokeCheckCustomCharacter() {
        let character = mode == .net ? artwork.netCharacter : artwork.hangingCharacter
        func raster(_ image: NSImage) -> NSBitmapImageRep {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect custom character")
            }
            return NSBitmapImageRep(cgImage: cg)
        }
        let restImage = character.image(for: .rest)
        let rest = raster(restImage)
        let sheet = NSImage(size: NSSize(width: 1400, height: 850))
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1400, height: 850).fill()
        var earChanges = 0
        var noseChanges = 0
        for (row, gesture) in [LocalCharacterPose.Gesture.ears, .nuzzle].enumerated() {
            for (column, step) in [0, 18, 27, 36, 45, 54, 72].enumerated() {
                let image = character.image(for: LocalCharacterPose(gesture: gesture, step: step))
                let bitmap = raster(image)
                var changes = 0
                for y in 0..<rest.pixelsHigh {
                    for x in 0..<rest.pixelsWide {
                        let a = rest.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        let b = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if a != b { changes += 1 }
                        if mode == .net && (a.alphaComponent == 0 || a.blueComponent > a.redComponent + 0.04) {
                            precondition(a == b, "Custom blue mesh and transparent holes must stay pixel-identical")
                        }
                        if mode == .hanging && a.alphaComponent > 0.9 &&
                            max(a.redComponent, a.greenComponent, a.blueComponent) < 0.35 &&
                            ((CGFloat(x) / CGFloat(rest.pixelsWide) > 0.59 && CGFloat(y) / CGFloat(rest.pixelsHigh) > 0.25) ||
                             (CGFloat(x) / CGFloat(rest.pixelsWide) > 0.40 && CGFloat(y) / CGFloat(rest.pixelsHigh) > 0.34)) {
                            precondition(a == b, "Custom cross eyes must not blink or move")
                        }
                    }
                }
                if gesture == .ears { earChanges = max(earChanges, changes) }
                if gesture == .nuzzle { noseChanges = max(noseChanges, changes) }
                let rect = NSRect(x: CGFloat(column * 200 + 15), y: CGFloat((1 - row) * 425 + 65),
                                  width: 170, height: 170 * image.size.height / image.size.width)
                image.draw(in: rect)
                if mode == .hanging { artwork.hangingLayers.halo.draw(in: rect) }
                "\(gesture) \(step)/72".draw(at: NSPoint(x: rect.minX, y: rect.minY - 25),
                    withAttributes: [.foregroundColor: NSColor.white])
            }
        }
        sheet.unlockFocus()
        NSLog("Custom %@ local gesture pixels: ears=%d nose=%d", mode.rawValue, earChanges, noseChanges)
        precondition(earChanges > 50 && noseChanges > 50)
        func displayed(_ pose: LocalCharacterPose) -> NSBitmapImageRep {
            let image = character.image(for: pose)
            let height = Int((96 * image.size.height / image.size.width).rounded())
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else {
                preconditionFailure("Cannot render normal-size custom character")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 96, height: height))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        func feature(_ bitmap: NSBitmapImageRep, nose: Bool) -> V2 {
            let region: NSRect
            if mode == .net {
                region = nose ? NSRect(x: 0.12, y: 0.65, width: 0.24, height: 0.14)
                    : NSRect(x: 0.48, y: 0.69, width: 0.22, height: 0.20)
            } else {
                region = nose ? NSRect(x: 0.43, y: 0.16, width: 0.20, height: 0.14)
                    : NSRect(x: 0.72, y: 0.26, width: 0.17, height: 0.18)
            }
            var sum = V2(0, 0)
            var total: CGFloat = 0
            for y in Int(region.minY * CGFloat(bitmap.pixelsHigh))..<Int(region.maxY * CGFloat(bitmap.pixelsHigh)) {
                for x in Int(region.minX * CGFloat(bitmap.pixelsWide))..<Int(region.maxX * CGFloat(bitmap.pixelsWide)) {
                    let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let weight = max(0, nose ? 0.4 - max(c.redComponent, c.greenComponent, c.blueComponent)
                        : c.redComponent - c.greenComponent - 0.2) * c.alphaComponent
                    sum = sum + V2(CGFloat(x), CGFloat(y)) * weight
                    total += weight
                }
            }
            precondition(total > 0)
            return sum / total
        }
        let normalRest = displayed(.rest)
        let earMotion = (feature(displayed(LocalCharacterPose(gesture: .ears, step: 27)), nose: false)
                         - feature(normalRest, nose: false)).magnitude
        let noseMotion = (feature(displayed(LocalCharacterPose(gesture: .nuzzle, step: 36)), nose: true)
                          - feature(normalRest, nose: true)).magnitude
        NSLog("Custom %@ normal-size movement at 48 pt / 2x: ear=%.2f nose=%.2f px", mode.rawValue, earMotion, noseMotion)
        precondition(earMotion > 0.4 && noseMotion > 0.6)
        guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode user artwork preview")
        }
        do {
            try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("\(mode.rawValue)-custom-poses.png"))
        } catch { preconditionFailure("Cannot save custom poses: \(error)") }
        var sawEar = false
        var sawNose = false
        var sawHalo = false
        for _ in 0..<2400 {
            tick(at: lastTick + 1.0 / 60)
            let pose = simulation.ropeAnimation.localPose
            sawEar = sawEar || (pose.gesture != .nuzzle && pose.step > 10)
            sawNose = sawNose || pose.nuzzle > 0.5
            let scene = sceneSnapshot()
            precondition(scene.displayImage === character.image(for: pose))
            if mode == .hanging {
                precondition(scene.haloImage === artwork.hangingLayers.halo && scene.haloPose == simulation.haloAnimation.pose)
                sawHalo = sawHalo || scene.haloPose.offset.magnitude > 0.01
            }
        }
        precondition(sawEar && sawNose)
        precondition(mode != .hanging || sawHalo)
        let held = simulation.ropeAnimation.elapsed
        let halo = simulation.haloAnimation.pose
        toggleVisible()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        toggleVisible()
        suspend()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ropeAnimation.elapsed == held)
        resume()
        precondition(simulation.haloAnimation.pose == halo)
        tick(at: lastTick + 0.05)
        precondition(simulation.ropeAnimation.elapsed > held)
        simulation.restartAnimation()
        reset()
        tick()
        NSLog("PASS: custom %@ ear/nose actions, correct scene mapping, physical idle and pause/resume", mode.rawValue)
    }
}
