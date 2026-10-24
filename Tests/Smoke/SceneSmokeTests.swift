import AppKit

extension PendantCoordinator {
    func smokeCheckRopeAnimation() {
        precondition(ropeAnimation.frames.count == 75 && abs(ropeAnimation.duration - 3) < 0.0001)
        precondition(ropeAnimation.frames.allSatisfy { $0.size == NSSize(width: 297, height: 266) })
        var elapsed = 0.0
        for (index, delay) in ropeAnimation.frameDurations.enumerated() {
            precondition(abs(delay - 0.04) < 0.0001)
            precondition(ropeAnimation.frameIndex(at: elapsed + delay * 0.5) == index)
            guard let image = ropeAnimation.frames[index].cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect rope animation frame \(index)")
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            precondition((bitmap.colorAt(x: 153, y: 29)?.alphaComponent ?? 0) > 0.9,
                         "Every animation frame must meet the same rope attachment")
            precondition((bitmap.colorAt(x: 153, y: 0)?.alphaComponent ?? 1) == 0,
                         "The source's long upper rope must be removed")
            elapsed += delay
        }
        precondition(ropeAnimation.frameIndex(at: 3.02) == 0)

        func darkBounds(frame: Int, region: NSRect) -> NSRect {
            guard let image = ropeAnimation.frames[frame].cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                preconditionFailure("Cannot inspect blink frame")
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            var bounds = NSRect.null
            for y in Int(region.minY)..<Int(region.maxY) {
                for x in Int(region.minX)..<Int(region.maxX) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.9,
                          max(color.redComponent, color.greenComponent, color.blueComponent) < 0.3 else { continue }
                    bounds = bounds.union(NSRect(x: x, y: y, width: 1, height: 1))
                }
            }
            return bounds
        }
        let openEye = darkBounds(frame: 0, region: NSRect(x: 50, y: 105, width: 28, height: 35))
        let closedEye = darkBounds(frame: 15, region: NSRect(x: 40, y: 140, width: 35, height: 18))
        precondition(!openEye.isNull && openEye.height >= 14)
        precondition(!closedEye.isNull && closedEye.width >= 18 && closedEye.height <= 6,
                     "Blink must change the eye's shape, not translate a static pig")

        var previewSettings = settings
        do {
            try previewSettings.set(180, for: .size)
            try previewSettings.set(140, for: .length)
        } catch {
            preconditionFailure("Cannot configure rope animation preview: \(error)")
        }
        let previewSimulation = PendantSimulation(settings: previewSettings,
                                                  frameDurations: netAnimation.frameDurations,
                                                  ropeFrameDurations: ropeAnimation.frameDurations)
        let anchor = V2(230, 450)
        previewSimulation.reset(anchor: anchor)
        let preview = PigOverlayView(frame: NSRect(x: 0, y: 0, width: 460, height: 500))
        var sawWaiting = false
        var sawMoving = false
        var sawFalling = false
        var blendedFrames = 0
        for index in 0..<(14 * 60) {
            let time = Double(index + 1) / 60
            let position = anchor + V2(min(45, max(0, CGFloat(time - 4) * 300)),
                                       -min(60, max(0, CGFloat(time - 7) * 400)))
            previewSimulation.advance(anchor: position, elapsed: 1.0 / 60)
            let animation = previewSimulation.ropeAnimation
            sawWaiting = sawWaiting || !animation.isAnimating
            sawMoving = sawMoving || animation.action == .moving
            sawFalling = sawFalling || animation.action == .falling
            let scene = SceneSnapshot(simulation: previewSimulation, artwork: artwork, isVisible: true)
            let sample = animation.sample
            precondition(!(sample.firstIndex == 51 && sample.secondIndex == 0),
                         "A turned face must return through neighboring poses before blending to rest")
            precondition(scene.displayImage === ropeAnimation.frames[sample.firstIndex])
            precondition(scene.imageBlend == CGFloat(sample.fraction))
            if let next = scene.nextDisplayImage { precondition(next === ropeAnimation.frames[sample.secondIndex]) }
            preview.scene = scene
            guard let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds) else {
                preconditionFailure("Cannot render rope animation frame")
            }
            preview.cacheDisplay(in: preview.bounds, to: bitmap)
            if scene.nextDisplayImage != nil && scene.imageBlend > 0 && scene.imageBlend < 1 {
                let rope = scene.ropes[0]
                let angle = rope.endAngle * -0.70
                let offsetY = (29 - CGFloat(120)) * rope.width / 297
                let point = rope.endPoint + V2(-offsetY * sin(angle), offsetY * cos(angle))
                let scale = CGFloat(bitmap.pixelsWide) / preview.bounds.width
                let x = Int((point.x * scale).rounded())
                let y = Int(((preview.bounds.height - point.y) * scale).rounded())
                precondition((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.98,
                             "Frame mixing must not fade the opaque body or expose the rope underneath")
                blendedFrames += 1
            }
            if index % 4 == 0 {
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    preconditionFailure("Cannot encode rope animation preview")
                }
                let url = Bundle.main.bundleURL.deletingLastPathComponent()
                    .appendingPathComponent(String(format: "rope-state-%04d.png", index))
                do { try png.write(to: url) } catch { preconditionFailure("Rope animation snapshot: \(error)") }
            }
        }
        precondition(sawWaiting && sawMoving && sawFalling && blendedFrames > 30)

        tick(at: lastTick + 0.085)
        let heldTime = simulation.ropeAnimation.elapsed
        let heldSample = simulation.ropeAnimation.sample
        toggleVisible()
        tick(at: lastTick + 1)
        precondition(simulation.ropeAnimation.elapsed == heldTime && simulation.ropeAnimation.sample == heldSample && timer == nil)
        toggleVisible()
        precondition(simulation.ropeAnimation.elapsed == heldTime && simulation.ropeAnimation.sample == heldSample)
        suspend()
        tick(at: lastTick + 1)
        precondition(simulation.ropeAnimation.elapsed == heldTime && simulation.ropeAnimation.sample == heldSample && timer == nil)
        resume()
        tick(at: lastTick + 0.04)
        precondition(simulation.ropeAnimation.elapsed > heldTime && timer != nil)
        reset()
        NSLog("PASS: 75 original source frames, real blink shape, fixed attachment, random idle, movement/falling reactions, opaque frame blending, hidden/sleep pause and resume")
    }

    func smokeCheckSceneIsolation() {
        let snapshot = sceneSnapshot()
        let heldNodes = snapshot.ropes.map(\.nodes)
        let heldBounds = snapshot.bounds
        if mode == .ghost {
            guard let heldPosition = snapshot.ghostPosition else {
                preconditionFailure("Ghost scene is missing its follow position")
            }
            let originalAnchor = ropeAnchor()
            validationAnchor = originalAnchor + V2(100, -80)
            simulation.advance(anchor: ropeAnchor(), elapsed: 1.0 / 60.0)
            let changed = sceneSnapshot()
            guard let changedPosition = changed.ghostPosition else {
                preconditionFailure("Updated ghost scene is missing its follow position")
            }
            precondition(snapshot.ghostPosition.map { ($0 - heldPosition).magnitude == 0 } ?? false)
            precondition((changedPosition - heldPosition).magnitude > 0)
            precondition(snapshot.bounds == heldBounds && changed.bounds != heldBounds)
            validationAnchor = originalAnchor
            reset()
            NSLog("PASS: ghost scene snapshots retain positions and bounds independently of mutable simulation")
            return
        }
        for rope in activeRopes { rope.reset(anchor: ropeAnchor() + V2(100, -80)) }
        let changed = sceneSnapshot()
        precondition(changed.ropes.count == heldNodes.count)
        for (index, rope) in snapshot.ropes.enumerated() {
            precondition(zip(rope.nodes, heldNodes[index]).allSatisfy { ($0 - $1).magnitude == 0 })
            precondition((changed.ropes[index].nodes[0] - rope.nodes[0]).magnitude > 100)
        }
        precondition(snapshot.bounds == heldBounds)
        precondition(changed.bounds != heldBounds)
        reset()
        NSLog("PASS: scene snapshots retain geometry and bounds independently of mutable simulation")
    }
}
