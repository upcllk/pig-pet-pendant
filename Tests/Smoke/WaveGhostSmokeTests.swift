import AppKit

extension PendantCoordinator {
    func smokeCheckWaveGhostAnimation() {
        smokeCheckGhostHemLoop(name: "ghost-wave", aspectRatio: 1) {
            artwork.ghostWaveCharacter.image(for: $0, blinkSample: .rest)
        }
        precondition(artwork.ghostWave.size == NSSize(width: 768, height: 768))
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("ghost-wave.png"),
              let bundledImage = NSImage(contentsOf: bundled),
              let sourceCG = bundledImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("Cannot read the bundled wave ghost source image")
        }
        precondition(sourceCG.width == 768 && sourceCG.height == 768)
        let sourceBitmap = NSBitmapImageRep(cgImage: sourceCG)
        precondition(sourceBitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0,
                     "The new ghost source must retain its transparent background")

        func raster(_ image: NSImage, width: Int = 192) -> [UInt8] {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect the wave ghost pose")
            }
            let height = Int((Double(cgImage.height) * Double(width) / Double(cgImage.width)).rounded())
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .high
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            precondition(success)
            return bytes
        }

        func changedPixels(_ first: [UInt8], _ second: [UInt8], width: Int,
                           xRange: Range<Int>, yRange: Range<Int>) -> Int {
            var count = 0
            for y in yRange {
                for x in xRange {
                    let offset = (y * width + x) * 4
                    if (0..<4).contains(where: { abs(Int(first[offset + $0]) - Int(second[offset + $0])) > 6 }) {
                        count += 1
                    }
                }
            }
            return count
        }

        let restPose = GhostBodyPose()
        let open = raster(artwork.ghostWaveCharacter.image(for: restPose, blinkSample: .rest))
        let closedSample = CharacterFrameSample(firstIndex: 3, secondIndex: 4, fraction: 0)
        let closed = raster(artwork.ghostWaveCharacter.image(for: restPose, blinkSample: closedSample))
        let ears = raster(artwork.ghostWaveCharacter.image(
            for: GhostBodyPose(step: 54), blinkSample: .rest
        ))
        let hem = raster(artwork.ghostWaveCharacter.image(
            for: GhostBodyPose(hemStep: GhostBodyPose.hemSteps / 4), blinkSample: .rest
        ))
        precondition(changedPixels(open, closed, width: 192, xRange: 0..<192, yRange: 0..<192) > 100,
                     "Blink must visibly change the source eyes")
        precondition(changedPixels(open, ears, width: 192, xRange: 0..<192, yRange: 0..<192) > 40,
                     "Ear movement must be visible at normal pendant size")
        precondition(changedPixels(open, hem, width: 192, xRange: 0..<192, yRange: 0..<192) > 50,
                     "The wave hem must visibly move at normal pendant size")
        let earSnoutChanges = changedPixels(open, ears, width: 192, xRange: 28..<82, yRange: 90..<124)
        let hemSnoutChanges = changedPixels(open, hem, width: 192, xRange: 28..<82, yRange: 90..<124)
        precondition(earSnoutChanges <= 2 && hemSnoutChanges == 0,
                     "Ear and hem motion must preserve the pig snout")
        precondition(artwork.ghostWaveCharacter.image(for: restPose, blinkSample: .rest) ===
                     artwork.ghostWaveCharacter.image(for: restPose, blinkSample: .rest),
                     "Repeated poses should reuse the bounded image cache")

        let sheet = NSImage(size: NSSize(width: 800, height: 500))
        sheet.lockFocus()
        for row in 0..<2 {
            (row == 0 ? NSColor.white : NSColor.black).setFill()
            CGRect(x: 0, y: row * 250, width: 800, height: 250).fill()
            let poses = [
                artwork.ghostWaveCharacter.image(for: restPose, blinkSample: .rest),
                artwork.ghostWaveCharacter.image(for: restPose, blinkSample: closedSample),
                artwork.ghostWaveCharacter.image(for: GhostBodyPose(step: 54), blinkSample: .rest),
                artwork.ghostWaveCharacter.image(
                    for: GhostBodyPose(hemStep: GhostBodyPose.hemSteps / 4), blinkSample: .rest
                )
            ]
            for (index, image) in poses.enumerated() {
                let rect = CGRect(x: index * 200 + 48, y: row * 250 + 34, width: 104, height: 104)
                let haloRect = CGRect(x: rect.minX, y: rect.minY - 22, width: rect.width, height: rect.height * 1.5)
                artwork.ghostHalo.draw(in: haloRect)
                image.draw(in: rect)
            }
        }
        sheet.unlockFocus()
        let destination = SmokeArtifactDirectory.url.appendingPathComponent("ghost-wave-poses.png")
        guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode wave ghost pose preview")
        }
        do { try png.write(to: destination) }
        catch { preconditionFailure("Cannot save wave ghost pose preview: \(error)") }
        NSLog("PASS: new wave ghost source alpha, blink, independent ear/hem motion, snout protection and halo pose preview")
    }
}
