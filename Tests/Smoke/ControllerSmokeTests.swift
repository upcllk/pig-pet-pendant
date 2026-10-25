import AppKit
import Foundation

extension PendantCoordinator {
    func smokeCheck() {
        validationAnchor = ropeAnchor()
        defer { validationAnchor = nil }
        smokeCheckSceneIsolation()
        precondition(!windows.isEmpty && windows.count == NSScreen.screens.count)
        for panel in windows {
            precondition(!panel.isOpaque && !panel.hasShadow && panel.ignoresMouseEvents)
            precondition(!panel.canBecomeKey && !panel.canBecomeMain)
            precondition(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
            NSLog("Overlay frame=%@ scale=%.1f visible=%d", NSStringFromRect(panel.frame),
                  panel.backingScaleFactor, panel.isVisible ? 1 : 0)
        }
        let frameBeforeHiding = netFrameIndex
        toggleVisible()
        precondition(timer == nil && windows.allSatisfy { !$0.isVisible })
        tick(at: lastTick + 1)
        precondition(netFrameIndex == frameBeforeHiding)
        rebuildWindows()
        precondition(timer == nil && windows.allSatisfy { !$0.isVisible })
        toggleVisible()
        precondition(timer != nil && windows.allSatisfy { $0.isVisible })
        let frameBeforeSleep = netFrameIndex
        suspend()
        precondition(timer == nil)
        tick(at: lastTick + 1)
        precondition(netFrameIndex == frameBeforeSleep)
        resume()
        precondition(timer != nil)
        reset()
        tick()
        if !isIdle || timerInterval != idleTimerInterval {
            NSLog("Controller reset check %@ count=%d idle=%d timer=%.6f expected=%.6f settled=%@",
                  mode.rawValue, balloonCount, isIdle ? 1 : 0, timerInterval, idleTimerInterval,
                  simulation.activeRopes.map { $0.isSettled ? "yes" : "no" }.joined(separator: ","))
            preconditionFailure("Controller reset must reach the idle schedule")
        }
        if mode == .rope { smokeCheckRopeAnimation() }
        if mode == .balloon || mode == .bamboo { smokeCheckLocalCharacters() }
        if mode == .hanging || mode == .net { smokeCheckCustomCharacter() }
        if mode == .ghost { smokeCheckGhostAnimation() }
        if mode == .bamboo {
            let savedLength = physics.length
            physics.length = 180
            var compressed = false
            for rate in [30, 60, 120, 144] {
                physics.reset(anchor: V2(-500, 300))
                var previousLength = max(pigSize * 1.5, physics.length)
                for frame in 1...(rate * 3) {
                    let time = CGFloat(frame) / CGFloat(rate)
                    let anchor = V2(-500 + sin(time * 11) * 160, 300 - sin(time * 7) * 135)
                    physics.advance(anchor: anchor, timeStep: 1 / CGFloat(rate))
                    compressed = compressed || (physics.endPoint - anchor).magnitude < physics.length * 0.7
                    bambooBend.advance(elapsed: 1 / CGFloat(rate), moving: frame < rate || frame > rate * 2)
                    let points = bambooPose.points
                    let renderedLength = zip(points, points.dropFirst()).reduce(CGFloat(0)) {
                        $0 + ($1.1 - $1.0).magnitude
                    }
                    let nominal = max(pigSize * 1.5, physics.length)
                    precondition(abs(renderedLength - nominal) < nominal * 0.002)
                    precondition(abs(renderedLength - previousLength) < nominal * 0.002,
                                 "Bamboo must not shorten during rapid movement or reversals")
                    previousLength = renderedLength
                }
            }
            precondition(compressed, "Movement regression must exercise a slack reference rope")
            NSLog("PASS: fixed bamboo arc length during slack, rapid reversals and motion/rest transitions at 30/60/120/144 Hz")
            physics.length = savedLength
            reset()
            tick()
        }
        if mode == .net {
            precondition(artwork.netImage.size == NSSize(width: 512, height: 768))
            let heldNodes = physics.nodes
            tick(at: lastTick + 0.045)
            precondition(isIdle)
            precondition(zip(physics.nodes, heldNodes).allSatisfy { ($0 - $1).magnitude < 0.0001 })
            reset()
        }
        if mode == .bamboo {
            precondition(bambooImage.size == NSSize(width: 1917, height: 1367))
            precondition(displayImage === bambooImage && physics.endPoint.y < physics.nodes[0].y)
            let heldNodes = physics.nodes
            tick(at: lastTick + 0.08)
            precondition(isIdle && timerInterval == idleTimerInterval)
            precondition(zip(physics.nodes, heldNodes).allSatisfy { ($0 - $1).magnitude < 0.0001 })
            bambooBend = BambooBend(progress: 0)
            tick(at: lastTick + 0.05)
            precondition(!isIdle && timerInterval == 1.0 / 60.0)
            for _ in 0..<50 { tick(at: lastTick + 0.05) }
            precondition(bambooBend.isSettled && isIdle && timerInterval == idleTimerInterval)
            bambooBend = BambooBend(progress: 0.4)
            toggleVisible()
            tick(at: lastTick + 1)
            precondition(bambooBend.progress == 0.4 && timer == nil)
            toggleVisible()
            bambooBend = BambooBend(progress: 0.4)
            suspend()
            tick(at: lastTick + 1)
            precondition(bambooBend.progress == 0.4 && timer == nil)
            resume()
        }
        if activeRopes.count > 1 {
            reset()
            balloons[balloons.count - 1].reset(anchor: ropeAnchor() + V2(100, 0))
            tick()
            precondition(!isIdle && timerInterval == 1.0 / 60.0)
        }
        if mode == .ghost {
            let previousAnchor = ropeAnchor()
            let previousPosition = simulation.ghostPosition
            validationAnchor = previousAnchor + V2(100, 0)
            tick()
            precondition(!isIdle && timerInterval == 1.0 / 60.0)
            precondition(simulation.ghostPosition.x > previousPosition.x)
            validationAnchor = previousAnchor
        } else {
            physics.reset(anchor: ropeAnchor() + V2(100, 0))
            tick()
            precondition(!isIdle && timerInterval == 1.0 / 60.0)
        }
        reset()
        let defaults = validationDefaults
        let sizeKey = ParameterID.size.storageKey(for: mode)
        let lengthKey = ParameterID.length.storageKey(for: mode)
        let oldSize = defaults.object(forKey: sizeKey)
        let oldLength = defaults.object(forKey: lengthKey)
        let size = pigSize
        let length = physics.length
        changeSize(10000)
        changeLength(-1)
        precondition(pigSize == 256 && physics.length == 20)
        changeSize(size)
        changeLength(length)
        defaults.set(oldSize, forKey: sizeKey)
        defaults.set(oldLength, forKey: lengthKey)
        if let view = views.first, let panel = windows.first,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            for balloon in activeRopes { balloon.reset(anchor: V2(panel.frame.midX, panel.frame.midY)) }
            view.scene = sceneSnapshot()
            view.cacheDisplay(in: view.bounds, to: bitmap)
            var painted = 0
            var clear = 0
            for vertical in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for horizontal in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    let alpha = bitmap.colorAt(x: horizontal, y: vertical)?.alphaComponent ?? 0
                    if alpha > 0 { painted += 1 } else { clear += 1 }
                }
            }
            precondition(painted > 0 && clear > painted)
            NSLog("Render check: painted=%d transparent=%d bitmap=%dx%d", painted, clear,
                  bitmap.pixelsWide, bitmap.pixelsHigh)
            reset()
        } else {
            preconditionFailure("Cannot capture overlay backing for render check")
        }
        NSLog("PASS: GUI smoke checks (panel flags, visibility, screen rebuild, suspend/resume, idle/active timers, settings bounds, transparent rendering)")
    }
}
