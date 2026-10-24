import AppKit
import Foundation

extension SettingsWindowController {
    private func checkHangingArtwork() {
        guard let cgImage = model.hangingImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width == 360, cgImage.height == 384 else {
            preconditionFailure("Hanging pig artwork dimensions are invalid")
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let haloXRange = 235..<356
        let haloYRange = 201..<344
        var translucentHaloPixels = 0
        var opaqueHaloPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    preconditionFailure("Cannot inspect hanging pig artwork")
                }
                if color.alphaComponent > 0 {
                    if haloXRange.contains(x) && haloYRange.contains(y) {
                        if color.alphaComponent < 0.999 {
                            translucentHaloPixels += 1
                        } else {
                            opaqueHaloPixels += 1
                        }
                    } else {
                        precondition(color.alphaComponent > 0.999, "Hanging pig body must not be translucent")
                    }
                }
            }
        }
        precondition(translucentHaloPixels > 100 && opaqueHaloPixels > 0, "Hanging pig halo must retain soft edges")

        let xOrigin = 210
        let yOrigin = 180
        let width = 150
        let height = 180
        var halo = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x + xOrigin, y: y + yOrigin)?
                    .usingColorSpace(.deviceRGB) else {
                    preconditionFailure("Cannot inspect hanging pig halo")
                }
                halo[y * width + x] = color.alphaComponent > 0.5
                    && color.redComponent > 245.0 / 255
                    && color.greenComponent > 220.0 / 255
                    && color.blueComponent < 230.0 / 255
            }
        }

        var outside = [Bool](repeating: false, count: halo.count)
        var queue: [Int] = []
        for y in 0..<height {
            for x in 0..<width where x == 0 || x == width - 1 || y == 0 || y == height - 1 {
                let index = y * width + x
                if !halo[index] && !outside[index] {
                    outside[index] = true
                    queue.append(index)
                }
            }
        }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            for (nextX, nextY) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nextX >= 0 && nextX < width && nextY >= 0 && nextY < height {
                let next = nextY * width + nextX
                if !halo[next] && !outside[next] {
                    outside[next] = true
                    queue.append(next)
                }
            }
        }
        let enclosedHaloPixels = halo.indices.filter { !halo[$0] && !outside[$0] }.count
        precondition(enclosedHaloPixels > 0, "Hanging pig halo must be a closed loop")
        NSLog("PASS: hanging pig foreground opacity and closed halo")
    }

    private func captureSettingsSnapshot(named filename: String) {
        guard let content = window?.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            preconditionFailure("Cannot render settings window")
        }
        content.layoutSubtreeIfNeeded()
        for control in sliders + [bambooPositionSlider, visibility, musicReactive, audioStatus, countStepper, countReadout, modeControl] where !control.isHiddenOrHasHiddenAncestor {
            precondition(content.bounds.contains(control.convert(control.bounds, to: content)))
        }
        precondition(content.bounds.contains(audioRow.convert(audioRow.bounds, to: content)))
        for row in ghostOffsetRows where !row.slider.isHiddenOrHasHiddenAncestor {
            precondition(content.bounds.contains(row.slider.convert(row.slider.bounds, to: content)))
            precondition((row.readout.cell?.cellSize.width ?? 0) <= row.readout.bounds.width)
        }
        for row in parameterRows where !row.row.isHidden {
            precondition(content.bounds.contains(row.readout.convert(row.readout.bounds, to: content)))
            precondition((row.readout.cell?.cellSize.width ?? 0) <= row.readout.bounds.width)
        }
        precondition(musicReactive.state == .off && musicReactive.isEnabled)
        precondition(countRow.isHidden == (model.mode != .balloon))
        precondition(bambooPositionRow.isHidden == (model.mode != .bamboo))
        precondition(ghostOffsetRows.allSatisfy { $0.row.isHidden == (model.mode != .ghost) })
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            preconditionFailure("Cannot encode settings snapshot")
        }
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(filename)
        do { try png.write(to: url) } catch { preconditionFailure("Settings snapshot: \(error)") }
    }

    func smokeCheck() {
        checkHangingArtwork()
        let defaults = model.validationDefaults
        let legacyKeys = ParameterID.allCases.map(\.storageKey)
        let modeParameterKeys = DisplayMode.allCases.flatMap { mode in
            ParameterID.allCases.map { $0.storageKey(for: mode) }
        }
        let keys = legacyKeys + ["BalloonCount", "DisplayMode", "BambooPigPosition", "GhostOffsetX", "GhostOffsetY", "SystemAudioReactiveEnabled"] + modeParameterKeys
        let saved = keys.map { defaults.object(forKey: $0) }
        let originalCount = model.balloonCount
        let originalMode = model.mode
        let originalBambooPosition = model.settings.bambooPosition
        let originalGhostOffsets = Dictionary(uniqueKeysWithValues: GhostOffsetAxis.allCases.map { ($0, model.settings[$0]) })
        let originalModeParameters: [DisplayMode: [ParameterID: Double]] = Dictionary(
            uniqueKeysWithValues: DisplayMode.allCases.map { mode in
                (mode, Dictionary(uniqueKeysWithValues: ParameterID.allCases.map { ($0, model.settings[$0, mode: mode]) }))
            })
        let values = [Double(model.physics.length), Double(model.pigSize), Double(model.physics.gravity),
                  model.dampingRate, Double(model.physics.weight), Double(model.physics.elasticity)]
        defer {
            model.changeLength(CGFloat(values[0]))
            model.changeSize(CGFloat(values[1]))
            model.changeGravity(values[2])
            model.changeDamping(values[3])
            model.changeWeight(values[4])
            model.changeElasticity(values[5])
            model.changeBambooPosition(originalBambooPosition)
            for axis in GhostOffsetAxis.allCases {
                model.changeGhostOffset(axis, value: originalGhostOffsets[axis]!)
            }
            model.changeCount(originalCount)
            model.changeMode(originalMode)
            for (index, key) in keys.enumerated() { defaults.set(saved[index], forKey: key) }
            refresh()
            close()
        }
        showWindow(nil)
        precondition(window?.isVisible == true && window?.canBecomeKey == true)
        modeControl.selectedSegment = 0
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        precondition(model.activeRopes.count == 1 && model.physics.endPoint.y < model.physics.nodes[0].y)
        precondition(model.displayImage === model.pigImage && image.image === model.pigImage)
        precondition(!countStepper.isEnabled && parameterLabels[5].stringValue == "重力")
        precondition(countRow.isHidden && window?.contentView?.frame.height == 550)
        precondition(bambooPositionRow.isHidden)
        precondition(ghostOffsetRows.allSatisfy(\.row.isHidden))
        precondition(parameterRows.allSatisfy { !$0.row.isHidden })
        precondition(defaults.string(forKey: "DisplayMode") == "rope")
        modeControl.selectedSegment = 2
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        precondition(model.mode == .net && model.activeRopes.count == 1)
        precondition(model.physics.endPoint.y < model.physics.nodes[0].y)
        precondition(model.displayImage === model.netAnimation.frames[0])
        precondition(image.image === model.displayImage && !countStepper.isEnabled)
        precondition(countRow.isHidden && window?.contentView?.frame.height == 550)
        precondition(bambooPositionRow.isHidden)
        precondition(ghostOffsetRows.allSatisfy(\.row.isHidden))
        precondition(parameterLabels[5].stringValue == "重力")
        precondition(defaults.string(forKey: "DisplayMode") == "net")
        precondition(model.physics.length == CGFloat(originalModeParameters[.net]![.length]!))
        precondition(model.pigSize == CGFloat(originalModeParameters[.net]![.size]!))
        model.smokeCheck()
        modeControl.selectedSegment = 3
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        precondition(model.mode == .bamboo && model.activeRopes.count == 1)
        precondition(model.displayImage === model.bambooImage && image.image === model.bambooImage)
        precondition(defaults.string(forKey: "DisplayMode") == "bamboo")
        precondition(countRow.isHidden && window?.contentView?.frame.height == 590)
        precondition(!bambooPositionRow.isHidden && window?.contentView?.frame.height == 590)
        precondition(bambooPositionSlider.minValue == 0 && bambooPositionSlider.maxValue == 100)
        precondition(model.settings.bambooPosition == 50 && bambooPositionSlider.doubleValue == 50)
        bambooPositionSlider.doubleValue = 73
        bambooPositionSlider.sendAction(bambooPositionSlider.action, to: bambooPositionSlider.target)
        precondition(model.settings.bambooPosition == 73 && defaults.double(forKey: "BambooPigPosition") == 73)
        model.changeMode(.rope)
        refresh()
        precondition(bambooPositionRow.isHidden)
        model.changeMode(.bamboo)
        refresh()
        precondition(!bambooPositionRow.isHidden && bambooPositionSlider.doubleValue == 73)
        precondition(parameterLabels[0].stringValue == "竹子长度" && parameterLabels[3].stringValue == "竹子弹性")
        precondition(model.physics.length == CGFloat(originalModeParameters[.bamboo]![.length]!))
        precondition(model.pigSize == CGFloat(originalModeParameters[.bamboo]![.size]!))
        precondition(model.physics.weight == CGFloat(originalModeParameters[.bamboo]![.weight]!))
        precondition(model.physics.elasticity == CGFloat(originalModeParameters[.bamboo]![.elasticity]!))
        modeControl.selectedSegment = DisplayMode.allCases.firstIndex(of: .hanging)!
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        precondition(model.mode == .hanging && model.displayImage === model.hangingImage)
        precondition(visibility.title == "显示上吊猪" && countRow.isHidden && bambooPositionRow.isHidden)
        precondition(window?.contentView?.frame.height == 550 && model.physics.endPoint.y < model.physics.nodes[0].y)
        modeControl.selectedSegment = DisplayMode.allCases.firstIndex(of: .ghost)!
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        precondition(model.mode == .ghost && model.displayImage === model.ghostImage)
        precondition(visibility.title == "显示幽灵猪" && countRow.isHidden && bambooPositionRow.isHidden)
        precondition(window?.contentView?.frame.height == 430)
        precondition(ghostOffsetRows.allSatisfy { !$0.row.isHidden })
        precondition(ghostOffsetRows.allSatisfy { $0.slider.minValue == -300 && $0.slider.maxValue == 300 })
        precondition(ghostOffsetRows[0].axis == .horizontal && ghostOffsetRows[1].axis == .vertical)
        precondition(parameterRows.allSatisfy { $0.row.isHidden == ($0.parameter != .size) })
        precondition(ghostOffsetRows[0].slider.doubleValue == originalGhostOffsets[.horizontal])
        precondition(ghostOffsetRows[1].slider.doubleValue == originalGhostOffsets[.vertical])
        model.smokeCheck()
        let ghostSizeRow = parameterRows.first { $0.parameter == .size }!
        ghostSizeRow.slider.doubleValue = 72
        ghostSizeRow.slider.sendAction(ghostSizeRow.slider.action, to: ghostSizeRow.slider.target)
        precondition(model.settings[.size] == 72)
        precondition(defaults.double(forKey: ParameterID.size.storageKey(for: .ghost)) == 72)
        precondition(model.settings[.size, mode: .rope] == originalModeParameters[.rope]![.size]!)
        ghostOffsetRows[0].slider.doubleValue = 81
        ghostOffsetRows[0].slider.sendAction(ghostOffsetRows[0].slider.action,
                                             to: ghostOffsetRows[0].slider.target)
        ghostOffsetRows[1].slider.doubleValue = -45
        ghostOffsetRows[1].slider.sendAction(ghostOffsetRows[1].slider.action,
                                             to: ghostOffsetRows[1].slider.target)
        precondition(model.settings[.horizontal] == 81 && defaults.double(forKey: "GhostOffsetX") == 81)
        precondition(model.settings[.vertical] == -45 && defaults.double(forKey: "GhostOffsetY") == -45)
        model.changeMode(.hanging)
        refresh()
        precondition(ghostOffsetRows.allSatisfy(\.row.isHidden))
        model.changeMode(.ghost)
        refresh()
        precondition(ghostOffsetRows.allSatisfy { !$0.row.isHidden })
        precondition(ghostOffsetRows[0].slider.doubleValue == 81 && ghostOffsetRows[1].slider.doubleValue == -45)
        precondition(model.settings[.size] == 72)
        modeControl.selectedSegment = 1
        modeControl.sendAction(modeControl.action, to: modeControl.target)
        precondition(model.displayImage === model.balloonImage && image.image === model.balloonImage)
        precondition(countStepper.isEnabled && parameterLabels[5].stringValue == "浮力")
        precondition(!countRow.isHidden && window?.contentView?.frame.height == 590)
        precondition(model.settings[.size] == originalModeParameters[.balloon]![.size]!)
        precondition(defaults.string(forKey: "DisplayMode") == "balloon")
        for count in 1...8 {
            countStepper.integerValue = count
            countStepper.sendAction(countStepper.action, to: countStepper.target)
            precondition(model.balloonCount == count && model.balloons.count == count)
            precondition(defaults.integer(forKey: "BalloonCount") == count)
            precondition(model.balloons.allSatisfy { $0.endPoint.y > $0.nodes[0].y && $0.isSettled })
        }
        model.changeCount(Int.min)
        precondition(model.balloonCount == 1 && model.balloons.count == 1)
        model.changeCount(Int.max)
        precondition(model.balloonCount == 8 && model.balloons.count == 8)
        refresh()
        model.smokeCheck()
        for slider in sliders {
            slider.doubleValue = slider.minValue
            slider.sendAction(slider.action, to: slider.target)
        }
        precondition(model.physics.length == 20 && model.pigSize == 16 && model.physics.gravity == 100)
        precondition(model.physics.weight == 0 && model.physics.elasticity == 0)
        precondition(abs(model.dampingRate - 0.2) < 0.0001)
        precondition(defaults.double(forKey: ParameterID.length.storageKey(for: .balloon)) == 20)
        precondition(defaults.double(forKey: ParameterID.size.storageKey(for: .balloon)) == 16)
        precondition(defaults.double(forKey: ParameterID.gravity.storageKey(for: .balloon)) == 100)
        precondition(defaults.double(forKey: ParameterID.damping.storageKey(for: .balloon)) == 0.2)
        precondition(defaults.double(forKey: ParameterID.weight.storageKey(for: .balloon)) == 0)
        precondition(defaults.double(forKey: ParameterID.elasticity.storageKey(for: .balloon)) == 0)
        let targets: [Double] = [1200, 256, 200, 200, 8, 10000]
        for (index, value) in targets.enumerated() {
            sliders[index].doubleValue = value
            sliders[index].sendAction(sliders[index].action, to: sliders[index].target)
        }
        precondition(model.physics.length == 1200 && model.pigSize == 256 && model.physics.gravity == 10000)
        precondition(model.physics.weight == 200 && model.physics.elasticity == 200)
        precondition(abs(model.dampingRate - 8) < 0.0001)
        precondition(defaults.double(forKey: ParameterID.length.storageKey(for: .balloon)) == 1200)
        precondition(defaults.double(forKey: ParameterID.size.storageKey(for: .balloon)) == 256)
        precondition(defaults.double(forKey: ParameterID.gravity.storageKey(for: .balloon)) == 10000)
        precondition(defaults.double(forKey: ParameterID.damping.storageKey(for: .balloon)) == 8)
        precondition(defaults.double(forKey: ParameterID.weight.storageKey(for: .balloon)) == 200)
        precondition(defaults.double(forKey: ParameterID.elasticity.storageKey(for: .balloon)) == 200)
        toggleVisibility()
        precondition(!model.isVisible)
        toggleVisibility()
        precondition(model.isVisible)
        captureSettingsSnapshot(named: "settings-smoke.png")
        restoreSettings()
        precondition(model.mode == .rope && model.activeRopes.count == 1)
        precondition(model.balloonCount == 2 && model.balloons.count == 2)
        precondition(model.pigSize == 48 && model.physics.length == 140 && model.physics.gravity == 1350)
        precondition(model.physics.weight == 65 && model.physics.elasticity == 55)
        precondition(abs(Double(model.physics.dampingPerFrame) - 0.985) < 0.0001)
        precondition(model.settings.bambooPosition == 50 && defaults.double(forKey: "BambooPigPosition") == 50)
        precondition(model.settings[.horizontal] == 44 && defaults.double(forKey: "GhostOffsetX") == 44)
        precondition(model.settings[.vertical] == 32 && defaults.double(forKey: "GhostOffsetY") == 32)
        model.changeSize(88)
        model.changeLength(180)
        let previews = DisplayMode.allCases.flatMap { mode -> [(DisplayMode, CGFloat)] in
            let phases: [CGFloat] = mode == .bamboo ? [0, 0.5, 1] : [1]
            return phases.map { (mode, $0) }
        }
        for (previewMode, bendProgress) in previews {
            model.changeMode(previewMode)
            model.bambooBend = BambooBend(progress: bendProgress)
            refresh()
            captureSettingsSnapshot(named: "\(previewMode.rawValue)-settings-smoke.png")
            let previewHeight: CGFloat = previewMode == .bamboo ? 520 : 360
            let preview = PigOverlayView(frame: NSRect(x: 0, y: 0, width: 460, height: previewHeight))
            let anchorY = previewMode == .balloon ? 45
                : previewMode == .ghost ? previewHeight * 0.5 - 38
                : previewHeight - (previewMode == .bamboo ? 90 : 50)
            let anchor = V2(230, anchorY)
            for rope in model.activeRopes { rope.reset(anchor: anchor) }
            if previewMode == .ghost { model.simulation.reset(anchor: anchor) }
            precondition(model.activeRopes.allSatisfy {
                previewMode == .balloon ? $0.endPoint.y > anchor.y : $0.endPoint.y < anchor.y
            })
            guard let previewBitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds) else {
                preconditionFailure("Cannot render mode preview")
            }
            let renderStart = ProcessInfo.processInfo.systemUptime
            preview.scene = model.sceneSnapshot()
            preview.cacheDisplay(in: preview.bounds, to: previewBitmap)
            if previewMode == .bamboo {
                NSLog("Bamboo render at bend=%.1f: %.2f ms", Double(bendProgress),
                      (ProcessInfo.processInfo.systemUptime - renderStart) * 1000)
                var pigBounds = CGRect.null
                for vertical in stride(from: 0, to: previewBitmap.pixelsHigh, by: 2) {
                    for horizontal in stride(from: 0, to: previewBitmap.pixelsWide, by: 2) {
                        guard let color = previewBitmap.colorAt(x: horizontal, y: vertical)?.usingColorSpace(.deviceRGB),
                              color.alphaComponent > 0.5,
                              color.redComponent > color.greenComponent + 0.06,
                              color.redComponent > color.blueComponent + 0.08 else { continue }
                        pigBounds = pigBounds.union(CGRect(x: horizontal, y: vertical, width: 1, height: 1))
                    }
                }
                precondition(!pigBounds.isNull)
                if bendProgress == 0 { precondition(pigBounds.width > pigBounds.height * 1.2) }
                let grip = model.bambooPose.grip(width: model.pigSize)
                if bendProgress == 1 { precondition(sin(grip.angle) < -0.7, "Pig head must stay above its rear feet") }
                let scale = CGFloat(previewBitmap.pixelsWide) / preview.bounds.width
                let radius = Int(ceil(max(3, min(18, model.pigSize * 0.10)) * scale))
                for foot in BambooPose.feet {
                    let source = model.bambooPose.contact(for: foot, width: model.pigSize) * model.pigSize
                    let location = grip.origin + V2(source.x * cos(grip.angle) - source.y * sin(grip.angle),
                                                    source.x * sin(grip.angle) + source.y * cos(grip.angle))
                    let horizontal = Int((location.x * scale).rounded())
                    let vertical = Int(((preview.bounds.height - location.y) * scale).rounded())
                    var hasFoot = false
                    var hasBamboo = false
                    for offsetY in -radius...radius {
                        for offsetX in -radius...radius {
                            let pixelX = horizontal + offsetX
                            let pixelY = vertical + offsetY
                            guard pixelX >= 0, pixelX < previewBitmap.pixelsWide,
                                  pixelY >= 0, pixelY < previewBitmap.pixelsHigh,
                                  let color = previewBitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB),
                                  color.alphaComponent > 0.5 else { continue }
                            if abs(offsetX) <= 4 && abs(offsetY) <= 4,
                               color.redComponent > color.greenComponent + 0.06,
                               color.redComponent > color.blueComponent + 0.08 { hasFoot = true }
                            if color.greenComponent > color.redComponent + 0.1,
                               color.greenComponent > color.blueComponent + 0.15 { hasBamboo = true }
                        }
                    }
                    precondition(hasFoot && hasBamboo, "All three rendered feet must touch visible bamboo")
                }
                precondition(pigBounds.minX > 2 && pigBounds.maxX < CGFloat(previewBitmap.pixelsWide) - 2)
                precondition(pigBounds.minY > 2 && pigBounds.maxY < CGFloat(previewBitmap.pixelsHigh) - 2)
                NSLog("PASS: single bamboo render at bend=%.1f, warm-pixel bounds=%@", Double(bendProgress), NSStringFromRect(pigBounds))
            }
            guard let png = previewBitmap.representation(using: .png, properties: [:]) else {
                preconditionFailure("Cannot encode mode preview")
            }
            let filename: String
            switch previewMode {
            case .rope: filename = "rope-smoke.png"
            case .balloon: filename = "balloons-smoke.png"
            case .net: filename = "net-smoke.png"
            case .bamboo:
                filename = bendProgress == 0 ? "bamboo-moving-smoke.png"
                    : bendProgress == 0.5 ? "bamboo-bending-smoke.png" : "bamboo-smoke.png"
            case .hanging: filename = "hanging-smoke.png"
            case .ghost: filename = "ghost-smoke.png"
            }
            let previewURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(filename)
            do { try png.write(to: previewURL) } catch { preconditionFailure("Mode snapshot: \(error)") }
        }
        NSLog("PASS: six-mode switch, bamboo artwork and idle/resume, 62-frame net animation, idle playback, pause/resume, separate artwork, ghost following and offsets, balloon counts 1–8, persistence, defaults, layout, all mode snapshots and close")
    }
}
