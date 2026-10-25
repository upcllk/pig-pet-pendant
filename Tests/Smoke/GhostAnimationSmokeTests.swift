import AppKit
import ImageIO
import UniformTypeIdentifiers

extension PendantCoordinator {
    func smokeCheckGhostAnimation() {
        smokeCheckGhostBody()
        let animation = artwork.ghostBlink
        precondition(animation.frames.count == 8)
        precondition(zip(animation.frameDurations, GhostBlinkAnimation.keyDurations).allSatisfy { abs($0 - $1) < 0.000001 })
        func raster(_ image: NSImage) -> [UInt8] {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect ghost body")
            }
            var bytes = [UInt8](repeating: 0, count: 768 * 1152 * 4)
            let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: 768, height: 1152,
                                              bitsPerComponent: 8, bytesPerRow: 768 * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 768, height: 1152))
                return true
            }
            precondition(ok)
            return bytes
        }
        guard let suppliedBody = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("ghost-body.png")) else {
            preconditionFailure("Cannot load supplied body reference")
        }
        let reference = raster(suppliedBody)
        let first = raster(animation.frames[0])
        precondition(first == raster(animation.frames[7]), "Blink endpoints must be exactly identical")
        for (index, image) in animation.frames.enumerated() {
            let pixels = raster(image)
            var changes = 0
            for pixel in 0..<(768 * 1152) {
                let offset = pixel * 4
                precondition(pixels[offset + 3] == first[offset + 3], "Blink must not change body alpha")
                let eye = (150..<450).contains(pixel % 768) && (350..<500).contains(pixel / 768)
                if !eye {
                    precondition(pixels[offset..<(offset + 4)] == first[offset..<(offset + 4)],
                                 "Hands, ears, body and empty halo region must not change during blinking")
                }
                if pixels[offset..<(offset + 3)] != first[offset..<(offset + 3)] { changes += 1 }
                for channel in 0..<4 where !eye || index == 0 {
                    if abs(Int(pixels[offset + channel]) - Int(reference[offset + channel])) > 1 {
                        NSLog("Ghost body mismatch frame=%d at %d,%d channel=%d: %d -> %d",
                              index, pixel % 768, pixel / 768, channel,
                              reference[offset + channel], pixels[offset + channel])
                        preconditionFailure("Non-eye pixels must preserve the supplied body")
                    }
                }
            }
            if index > 0 && index < 7 { precondition(changes > 1000) }
        }
        func eyeBounds(_ image: NSImage, normalSize: Bool) -> CGRect {
            let width = normalSize ? 96 : 768
            let height = width * 3 / 2
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else {
                preconditionFailure("Cannot render ghost eye")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
            let region = CGRect(x: CGFloat(width) * 0.21, y: CGFloat(height) * 0.31,
                                width: CGFloat(width) * 0.13, height: CGFloat(height) * 0.09)
            var bounds = CGRect.null
            for y in Int(region.minY)..<Int(region.maxY) {
                for x in Int(region.minX)..<Int(region.maxX) {
                    let color = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if color.alphaComponent > 0.9 && max(color.redComponent, color.greenComponent, color.blueComponent) < 0.35 {
                        bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
            return bounds
        }
        for normalSize in [false, true] {
            let open = eyeBounds(animation.frames[0], normalSize: normalSize)
            let closed = eyeBounds(animation.frames[3], normalSize: normalSize)
            precondition(!open.isNull && !closed.isNull && closed.height < open.height * 0.4 && closed.width > open.width * 0.5)
            NSLog("Ghost eye at %@: open %.1f x %.1f, closed %.1f x %.1f",
                  normalSize ? "48 pt / 2x" : "source size", open.width, open.height, closed.width, closed.height)
        }
        let movingOpen = eyeBounds(artwork.ghostCharacters[0].image(for: GhostBodyPose(step: 24)), normalSize: true)
        let movingClosed = eyeBounds(artwork.ghostCharacters[3].image(for: GhostBodyPose(step: 24)), normalSize: true)
        precondition(!movingOpen.isNull && !movingClosed.isNull && movingClosed.height < movingOpen.height * 0.4,
                     "Normal-size blinking must remain visible during local ear/hand/hem motion")
        let halo = raster(artwork.ghostHalo)
        precondition(halo[(90 * 768 + 480) * 4 + 3] == 0, "Halo hole must be truly transparent")
        precondition((0..<(768 * 1152)).allSatisfy { $0 / 768 < 240 || halo[$0 * 4 + 3] == 0 },
                     "Independent halo layer must not contain a second body")
        precondition((0..<(768 * 160)).allSatisfy { first[$0 * 4 + 3] == 0 },
                     "Body frames must not retain a duplicate halo")

        let sheet = NSImage(size: NSSize(width: 1280, height: 560))
        sheet.lockFocus()
        for row in 0..<2 {
            (row == 0 ? NSColor.black : NSColor.white).setFill()
            CGRect(x: 0, y: row * 280, width: 1280, height: 280).fill()
            for index in 0..<8 {
                let rect = CGRect(x: CGFloat(index * 160 + 12), y: CGFloat(row * 280 + 45), width: 136, height: 204)
                animation.frames[index].draw(in: rect)
                artwork.ghostHalo.draw(in: rect)
                "key \(index)".draw(at: CGPoint(x: rect.minX, y: rect.minY - 22),
                                   withAttributes: [.foregroundColor: row == 0 ? NSColor.white : NSColor.black])
            }
        }
        sheet.unlockFocus()
        let directory = SmokeArtifactDirectory.url
        guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode layered ghost contact sheet")
        }
        do { try png.write(to: directory.appendingPathComponent("ghost-layered-contact.png")) }
        catch { preconditionFailure("Cannot save ghost contact sheet: \(error)") }

        var settings = self.settings
        do {
            try settings.set(140, for: .size)
            try settings.set(0, for: GhostOffsetAxis.horizontal)
            try settings.set(0, for: GhostOffsetAxis.vertical)
        } catch { preconditionFailure("Cannot configure ghost preview: \(error)") }
        let preview = PendantSimulation(settings: settings, frameDurations: artwork.net.frameDurations,
                                        ropeFrameDurations: artwork.rope.frameDurations, animationSeed: 17,
                                        ghostFrameDurations: animation.frameDurations)
        let anchor = V2(230, 230)
        preview.reset(anchor: anchor)
        let view = PigOverlayView(frame: CGRect(x: 0, y: 0, width: 560, height: 480))
        let previewURL = directory.appendingPathComponent("ghost-layered-preview.png")
        guard let destination = CGImageDestinationCreateWithURL(previewURL as CFURL, UTType.png.identifier as CFString, 160, nil) else {
            preconditionFailure("Cannot create ghost layered APNG preview")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
        var sawBlink = false
        var sawHalo = false
        var sawMix = false
        for frame in 0..<960 {
            let time = Double(frame) / 60
            let position = anchor + V2(min(70, max(0, time - 4) * 280), -min(50, max(0, time - 7) * 250))
            preview.advance(anchor: position, elapsed: 1.0 / 60)
            let scene = SceneSnapshot(simulation: preview, artwork: artwork, isVisible: true)
            let sample = preview.ghostBlink.sample
            precondition(scene.displayImage === artwork.ghostCharacters[sample.firstIndex].image(for: preview.ghostBody.pose))
            precondition(scene.haloImage === artwork.ghostHalo && scene.haloPose == preview.haloAnimation.pose)
            if let next = scene.nextDisplayImage {
                precondition(next === artwork.ghostCharacters[sample.secondIndex].image(for: preview.ghostBody.pose))
            }
            sawBlink = sawBlink || preview.ghostBlink.isAnimating
            sawHalo = sawHalo || scene.haloPose.offset.magnitude > 0.015
            if frame % 6 == 0 {
                view.scene = scene
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    preconditionFailure("Cannot render layered ghost scene")
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                for x in 0..<rep.pixelsWide {
                    precondition(rep.colorAt(x: x, y: 0)!.alphaComponent == 0 &&
                                 rep.colorAt(x: x, y: rep.pixelsHigh - 1)!.alphaComponent == 0,
                                 "Body or independently moving halo must not be cropped vertically")
                }
                for y in 0..<rep.pixelsHigh {
                    precondition(rep.colorAt(x: 0, y: y)!.alphaComponent == 0 &&
                                 rep.colorAt(x: rep.pixelsWide - 1, y: y)!.alphaComponent == 0,
                                 "Body or independently moving halo must not be cropped horizontally")
                }
                if scene.imageBlend > 0 && scene.imageBlend < 1 {
                    let center = preview.ghostPosition
                    let point = center + V2(0, -CGFloat(settings[.size]) * 0.15)
                    let scale = CGFloat(rep.pixelsWide) / view.bounds.width
                    let alpha = rep.colorAt(x: Int(point.x * scale),
                                            y: Int((view.bounds.height - point.y) * scale))!.alphaComponent
                    precondition(alpha > 0.98, "Blending must not make the ghost body translucent")
                    sawMix = true
                }
                guard let image = rep.cgImage else { preconditionFailure("Cannot encode ghost scene") }
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: 0.1, kCGImagePropertyAPNGUnclampedDelayTime: 0.1
                ]] as CFDictionary)
            }
        }
        precondition(CGImageDestinationFinalize(destination) && sawBlink && sawHalo && sawMix)
        guard let exported = CGImageSourceCreateWithURL(previewURL as CFURL, nil) else {
            preconditionFailure("Cannot reopen exported ghost preview")
        }
        precondition(CGImageSourceGetCount(exported) == 160)
        tick(at: lastTick + 0.05)
        let clock = simulation.ghostBlink.elapsed
        let sample = simulation.ghostBlink.sample
        let haloPose = simulation.haloAnimation.pose
        let bodyPose = simulation.ghostBody.pose
        toggleVisible()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ghostBlink.elapsed == clock && simulation.haloAnimation.pose == haloPose &&
                     simulation.ghostBody.pose == bodyPose)
        toggleVisible()
        suspend()
        tick(at: lastTick + 2)
        precondition(timer == nil && simulation.ghostBlink.elapsed == clock && simulation.ghostBlink.sample == sample &&
                     simulation.ghostBody.pose == bodyPose)
        resume()
        precondition(simulation.ghostBlink.sample == sample && simulation.haloAnimation.pose == haloPose &&
                     simulation.ghostBody.pose == bodyPose)
        tick(at: lastTick + 0.05)
        precondition(simulation.ghostBlink.elapsed > clock)
        simulation.restartAnimation()
        reset()
        tick()
        NSLog("PASS: ghost original eye keys, body-only frames, independent original halo, opaque blend, actual scene playback and hidden/sleep pause/resume")
    }
}
