import Foundation
@testable import PigPendantCore

final class SimulationTests {
    private let anchor = V2(-500, 300)
    private let durations = Array(repeating: 0.04, count: 62)
    private let ropeDurations = Array(repeating: 0.04, count: 75)

    func testEightBalloonsShareAnchorAndNonFirstActivityPreventsIdle() throws {
        var settings = PendantSettings()
        settings.mode = .balloon
        settings.setCount(8)
        let simulation = PendantSimulation(settings: settings, frameDurations: durations, ropeFrameDurations: ropeDurations)
        simulation.reset(anchor: anchor)
        try expectEqual(simulation.activeRopes.count, 8)
        for rope in simulation.activeRopes {
            try expectEqual(rope.nodes[0].x, anchor.x)
            try expectEqual(rope.nodes[0].y, anchor.y)
            try expectGreaterThan(rope.endPoint.y, anchor.y)
            try expect(rope.isSettled)
        }
        for _ in 0..<7200 {
            simulation.advance(anchor: anchor, elapsed: simulation.physics.fixedStep)
            if simulation.isIdle { break }
        }
        try expect(simulation.isIdle)
        simulation.balloons[7].reset(anchor: anchor + V2(100, 0))
        simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
        try expect(!(simulation.isIdle))
        try expectEqual(simulation.updateInterval, 1.0 / 60)
    }

    func testBalloonCountExtremesAndNonBalloonModesUseOneRope() throws {
        var settings = PendantSettings()
        for count in [1, 8] {
            settings.setCount(count)
            for mode in DisplayMode.allCases {
                settings.mode = mode
                let simulation = PendantSimulation(settings: settings, frameDurations: durations, ropeFrameDurations: ropeDurations)
                simulation.reset(anchor: anchor)
                try expectEqual(simulation.activeRopes.count, mode == .balloon ? count : 1)
                try expectEqual(simulation.settings.balloonCount, count)
                try expectEqual(simulation.physics.direction.y > 0, mode == .balloon)
            }
        }
    }

    func testNetAnimationContinuesWithoutIntegratingSettledRope() throws {
        var settings = PendantSettings()
        settings.mode = .net
        let simulation = PendantSimulation(settings: settings, frameDurations: durations, ropeFrameDurations: ropeDurations)
        simulation.reset(anchor: anchor)
        simulation.advance(anchor: anchor, elapsed: 0.01)
        try expect(simulation.isIdle)
        let nodes = simulation.physics.nodes
        try expectEqual(simulation.updateInterval, 1.0 / 15)
        for _ in 0..<300 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            if simulation.ropeAnimation.isAnimating { break }
        }
        try expect(simulation.ropeAnimation.isAnimating)
        let pose = simulation.ropeAnimation.localPose
        for _ in 0..<6 { simulation.advance(anchor: anchor, elapsed: 1.0 / 60) }
        try expectNotEqual(simulation.ropeAnimation.localPose, pose)
        for (before, after) in zip(nodes, simulation.physics.nodes) {
            try expectEqual((after - before).magnitude, 0)
        }
        try expectEqual(simulation.updateInterval, 1.0 / 60)
    }

    func testSettledRopeNudgeTriggersSwingOnlyDuringStretchAction() throws {
        var nudgedSimulation: PendantSimulation?
        for seed in 0..<32 {
            let candidate = PendantSimulation(settings: PendantSettings(), frameDurations: durations,
                                              ropeFrameDurations: ropeDurations, animationSeed: UInt64(seed))
            candidate.reset(anchor: anchor)
            candidate.advance(anchor: anchor, elapsed: 1.0 / 60)
            try expect(candidate.isIdle)
            for _ in 0..<1200 {
                let wasIdle = candidate.isIdle
                candidate.advance(anchor: anchor, elapsed: 1.0 / 60)
                if wasIdle && !candidate.isIdle {
                    if candidate.ropeAnimation.action == .stretch {
                        nudgedSimulation = candidate
                    }
                    break
                }
            }
            if nudgedSimulation != nil { break }
        }
        guard let simulation = nudgedSimulation else {
            throw CheckFailure(description: "No settled-rope nudge was triggered by the seeded stretch actions")
        }

        let restingNodes = simulation.physics.nodes
        var maximumHorizontalDisplacement = Array(repeating: CGFloat(0), count: restingNodes.count)
        for _ in 0..<60 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            for index in simulation.physics.nodes.indices {
                maximumHorizontalDisplacement[index] = max(
                    maximumHorizontalDisplacement[index],
                    abs(simulation.physics.nodes[index].x - restingNodes[index].x)
                )
            }
        }
        try expectGreaterThan(maximumHorizontalDisplacement[3], 1)
        try expectGreaterThan(maximumHorizontalDisplacement[6], 3)
        try expectGreaterThan(maximumHorizontalDisplacement[9], 4)
        try expectGreaterThan(maximumHorizontalDisplacement[12], 5)
        try expectEqual(simulation.physics.nodes[0].x, anchor.x)

        for _ in 0..<720 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            if simulation.isIdle { break }
        }
        try expect(simulation.isIdle)
    }

    func testSettledRopeSwingAmplitudeScalesAndCanBeDisabled() throws {
        func peakDisplacement(amplitude: Double, seed: UInt64) throws -> CGFloat? {
            var settings = PendantSettings()
            try settings.set(amplitude, for: .sway)
            let simulation = PendantSimulation(settings: settings, frameDurations: durations,
                                               ropeFrameDurations: ropeDurations, animationSeed: seed)
            simulation.reset(anchor: anchor)
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            let restingX = simulation.physics.endPoint.x
            for _ in 0..<1200 {
                let wasIdle = simulation.isIdle
                simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                if wasIdle && !simulation.isIdle {
                    guard simulation.ropeAnimation.action == .stretch else { continue }
                    var peak: CGFloat = 0
                    for _ in 0..<60 {
                        simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                        peak = max(peak, abs(simulation.physics.endPoint.x - restingX))
                    }
                    return peak
                }
            }
            return nil
        }

        var comparison: (seed: UInt64, defaultPeak: CGFloat)?
        for seed in 0..<32 {
            if let peak = try peakDisplacement(amplitude: 100, seed: UInt64(seed)) {
                comparison = (UInt64(seed), peak)
                break
            }
        }
        guard let comparison,
              let amplifiedPeak = try peakDisplacement(amplitude: 200, seed: comparison.seed) else {
            throw CheckFailure(description: "No seeded stretch action could compare nudge amplitudes")
        }
        let defaultPeak = comparison.defaultPeak
        try expectGreaterThan(defaultPeak, 5)
        try expectGreaterThan(amplifiedPeak, defaultPeak * 1.5)

        var disabledSettings = PendantSettings()
        try disabledSettings.set(0, for: .sway)
        let disabled = PendantSimulation(settings: disabledSettings, frameDurations: durations,
                                         ropeFrameDurations: ropeDurations, animationSeed: 2026)
        disabled.reset(anchor: anchor)
        disabled.advance(anchor: anchor, elapsed: 1.0 / 60)
        let restingEnd = disabled.physics.endPoint
        for _ in 0..<1200 {
            disabled.advance(anchor: anchor, elapsed: 1.0 / 60)
        }
        try expect(disabled.isIdle)
        try expectEqual((disabled.physics.endPoint - restingEnd).magnitude, 0)
    }

    func testRopeCharacterAnimationContinuesWithoutIntegratingSettledRope() throws {
        var selectedSimulation: PendantSimulation?
        for seed in 0..<32 {
            let candidate = PendantSimulation(settings: PendantSettings(), frameDurations: durations,
                                              ropeFrameDurations: ropeDurations, animationSeed: UInt64(seed))
            candidate.reset(anchor: anchor)
            candidate.advance(anchor: anchor, elapsed: 1.0 / 60.0)
            for _ in 0..<300 {
                candidate.advance(anchor: anchor, elapsed: 1.0 / 60)
                if candidate.ropeAnimation.isAnimating {
                    if candidate.ropeAnimation.action != .stretch { selectedSimulation = candidate }
                    break
                }
            }
            if selectedSimulation != nil { break }
        }
        guard let simulation = selectedSimulation else {
            throw CheckFailure(description: "No seeded non-stretch idle animation was selected")
        }
        let nodes = simulation.physics.nodes
        let sample = simulation.ropeAnimation.sample
        try expect(simulation.advance(anchor: anchor, elapsed: 1.0 / 60))
        try expect(simulation.isIdle)
        try expectNotEqual(simulation.ropeAnimation.sample, sample)
        try expectEqual(simulation.updateInterval, 1.0 / 60)
        for (before, after) in zip(nodes, simulation.physics.nodes) {
            try expectEqual((after - before).magnitude, 0)
        }

        var otherMode = simulation.settings
        otherMode.mode = .balloon
        simulation.apply(otherMode)
        try expectEqual(simulation.timeline.frameIndex, 0)
        try expectEqual(simulation.updateInterval, 1.0 / 15.0)
        otherMode.mode = .net
        simulation.apply(otherMode)
        try expectEqual(simulation.timeline.frameDurations.count, 62)
        otherMode.mode = .rope
        simulation.apply(otherMode)
        try expectEqual(simulation.ropeAnimation.sample, .rest)
        try expect(!simulation.ropeAnimation.isAnimating)
    }

    func testGhostFollowsNearbyWithoutUsingRopeMotion() throws {
        var settings = PendantSettings()
        settings.mode = .ghost
        let simulation = PendantSimulation(settings: settings, frameDurations: durations, ropeFrameDurations: ropeDurations)
        simulation.reset(anchor: anchor)
        let initialPosition = simulation.ghostPosition
        try expectEqual(initialPosition.x, anchor.x + 44)
        try expectEqual(initialPosition.y, anchor.y + 32)

        try settings.set(-72, for: .horizontal)
        try settings.set(96, for: .vertical)
        simulation.apply(settings)
        simulation.reset(anchor: anchor)
        let customInitialPosition = simulation.ghostPosition
        try expectEqual(simulation.ghostPosition.x, anchor.x - 72)
        try expectEqual(simulation.ghostPosition.y, anchor.y + 96)

        let movedAnchor = anchor + V2(120, 80)
        try expect(simulation.advance(anchor: movedAnchor, elapsed: 1.0 / 60.0))
        try expect(simulation.ghostPosition.x > customInitialPosition.x)
        try expect(simulation.ghostPosition.y > customInitialPosition.y)
        try expect(simulation.ghostPosition.x < movedAnchor.x - 72)
        try expect(simulation.ghostPosition.y < movedAnchor.y + 96)
        try expect(!simulation.isIdle)
        try expectEqual(simulation.physics.nodes[0].x, anchor.x)
        try expectEqual(simulation.physics.nodes[0].y, anchor.y)

        for _ in 0..<120 {
            simulation.advance(anchor: movedAnchor, elapsed: simulation.physics.fixedStep)
            if simulation.isIdle { break }
        }
        try expect(simulation.isIdle)
        try expectEqual(simulation.ghostPosition.x, movedAnchor.x - 72)
        try expectEqual(simulation.ghostPosition.y, movedAnchor.y + 96)
    }

    func testRopeAnimationClockAndPhysicsAcrossFrameRates() throws {
        for rate in [25, 30, 60, 120, 144] {
            var settings = PendantSettings()
            settings.mode = .hanging
            let simulation = PendantSimulation(settings: settings, frameDurations: durations,
                                               ropeFrameDurations: ropeDurations)
            simulation.reset(anchor: anchor)
            simulation.advance(anchor: anchor, elapsed: 0.01)
            try expect(simulation.isIdle)
            let nodes = simulation.physics.nodes
            for _ in 0..<(rate * 3 + rate / 2) {
                simulation.advance(anchor: anchor, elapsed: 1.0 / Double(rate))
            }
            let elapsed = 0.01 + Double(rate * 3 + rate / 2) / Double(rate)
            try expectEqual(simulation.ropeAnimation.elapsed, elapsed, accuracy: 0.000001)
            try expect(simulation.isIdle)
            for (before, after) in zip(nodes, simulation.physics.nodes) {
                try expectEqual((after - before).magnitude, 0)
            }
        }
    }

    func testBambooBendMustCompleteBeforeIdleAndMovementWakesIt() throws {
        var settings = PendantSettings()
        settings.mode = .bamboo
        let simulation = PendantSimulation(settings: settings, frameDurations: durations, ropeFrameDurations: ropeDurations)
        simulation.reset(anchor: anchor)
        simulation.bambooBend = BambooBend(progress: 0)
        simulation.advance(anchor: anchor, elapsed: 0.05)
        try expect(!(simulation.isIdle))
        for _ in 0..<50 { simulation.advance(anchor: anchor, elapsed: 0.05) }
        try expect(simulation.isIdle)
        try expect(simulation.bambooBend.isSettled)
        try expectEqual(simulation.updateInterval, simulation.idleInterval)
        simulation.advance(anchor: anchor + V2(20, 0), elapsed: 0.05)
        try expect(!(simulation.isIdle))
        try expectLessThan(simulation.bambooBend.progress, 1)
    }

    func testLocalCharactersAnimateWithoutWakingPhysics() throws {
        for mode in [DisplayMode.balloon, .bamboo, .hanging, .net] {
            for count in [1, 8] {
                var settings = PendantSettings()
                settings.mode = mode
                settings.setCount(count)
                let simulation = PendantSimulation(settings: settings, frameDurations: durations,
                                                   ropeFrameDurations: ropeDurations, animationSeed: 2026)
                simulation.reset(anchor: anchor)
                for _ in 0..<7200 {
                    simulation.advance(anchor: anchor, elapsed: simulation.physics.fixedStep)
                    if simulation.isIdle { break }
                }
                if !simulation.isIdle {
                    throw CheckFailure(description: "Local animation fixture did not settle: mode=\(mode), count=\(count)")
                }
                let heldNodes = simulation.activeRopes.map(\.nodes)
                var sawAnimation = Array(repeating: false, count: mode == .balloon ? count : 1)
                var sawDifferentPoses = false
                var sawWaiting = false
                for _ in 0..<1200 {
                    simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                    let players = mode == .balloon ? simulation.balloonAnimations : [simulation.ropeAnimation]
                    for index in players.indices {
                        sawAnimation[index] = sawAnimation[index] || players[index].localPose != .rest
                    }
                    sawDifferentPoses = sawDifferentPoses || Set(players.map(\.localPose)).count > 1
                    let animating = players.contains(where: \.isAnimating) ||
                        (mode == .hanging && simulation.haloAnimation.isAnimating)
                    sawWaiting = sawWaiting || !animating
                    try expectEqual(simulation.updateInterval, animating ? 1.0 / 60 : 1.0 / 15)
                    try expect(simulation.isIdle)
                    for (rope, nodes) in zip(simulation.activeRopes, heldNodes) {
                        try expect(zip(rope.nodes, nodes).allSatisfy { ($0 - $1).magnitude == 0 })
                    }
                }
                try expect(sawAnimation.allSatisfy { $0 } && sawWaiting)
                if mode == .balloon && count == 8 { try expect(sawDifferentPoses) }
                let heldPoses = simulation.balloonAnimations.map(\.localPose)
                let heldBambooPose = simulation.ropeAnimation.localPose
                simulation.reset(anchor: anchor)
                try expectEqual(simulation.balloonAnimations.map(\.localPose), heldPoses)
                try expectEqual(simulation.ropeAnimation.localPose, heldBambooPose)
                var other = simulation.settings
                other.mode = .net
                simulation.apply(other)
                try expect(simulation.balloonAnimations.allSatisfy { !$0.isAnimating })
                try expectEqual(simulation.ropeAnimation.localPose, .rest)
                if mode == .hanging || mode == .net {
                    for falling in [false, true] {
                        let reaction = PendantSimulation(settings: settings, frameDurations: durations,
                                                         ropeFrameDurations: ropeDurations, animationSeed: 2026)
                        reaction.reset(anchor: anchor)
                        var sawReaction = false
                        for frame in 1...180 {
                            let distance = CGFloat(min(frame, 30)) * 6
                            let moved = anchor + (falling ? V2(0, -distance) : V2(distance, 0))
                            reaction.advance(anchor: moved, elapsed: 1.0 / 60)
                            sawReaction = sawReaction || reaction.ropeAnimation.action == (falling ? .falling : .moving)
                        }
                        try expect(sawReaction)
                    }
                }
            }
        }
    }

    func testBambooVerticalShakesHaveNoPoseCuts() throws {
        var settings = PendantSettings()
        settings.mode = .bamboo
        let simulation = PendantSimulation(settings: settings, frameDurations: durations, ropeFrameDurations: ropeDurations)
        var anchor = V2(-400, 200)
        simulation.reset(anchor: anchor)
        simulation.bambooBend = BambooBend(progress: 0.55)

        var previousAngle = simulation.bambooPose.angle
        for frame in 1...24 {
            anchor = V2(-400 + CGFloat(frame) * 10, 200)
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60.0)
            try expectLessThan(abs(simulation.bambooPose.angle - previousAngle), 0.2)
            previousAngle = simulation.bambooPose.angle
        }
        for frame in 0..<40 {
            anchor = V2(-160, frame.isMultiple(of: 2) ? 550 : -150)
            let endAngleBefore = simulation.physics.endAngle
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60.0)
            try expectLessThan(abs(simulation.bambooPose.angle - previousAngle), 0.2)
            if frame == 1 {
                try expectEqual(simulation.physics.endAngle, endAngleBefore, accuracy: 0.0001)
            }
            try expect(simulation.bambooPose.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            previousAngle = simulation.bambooPose.angle
        }
        for _ in 0..<90 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60.0)
            try expectLessThan(abs(simulation.bambooPose.angle - previousAngle), 0.2)
            previousAngle = simulation.bambooPose.angle
        }

        let slowStart = anchor
        simulation.reset(anchor: slowStart)
        simulation.bambooBend = BambooBend(progress: 0)
        for frame in 1...30 {
            simulation.advance(anchor: slowStart + V2(CGFloat(frame), 0), elapsed: 1.0 / 60.0)
        }
        try expectLessThan(simulation.bambooBend.progress, 0.02)
    }

    func testLengthChangesPreservePoseAndTransitionSmoothly() throws {
        let simulation = PendantSimulation(settings: PendantSettings(), frameDurations: durations, ropeFrameDurations: ropeDurations)
        simulation.reset(anchor: anchor)
        let initialNode = simulation.physics.nodes[1]

        var settings = simulation.settings
        try settings.set(600, for: .length)
        simulation.apply(settings)
        simulation.wake()
        var previousLength = simulation.physics.currentLength

        for frame in 1...120 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60.0)
            let currentLength = simulation.physics.currentLength
            try expect(currentLength >= previousLength)
            try expectLessThan(currentLength, 600.001)
            if frame == 1 {
                try expectLessThan((simulation.physics.nodes[1] - initialNode).magnitude, 2)
            }
            previousLength = currentLength
        }
        try expectEqual(simulation.physics.currentLength, 600, accuracy: 0.01)

        try settings.set(20, for: .length)
        simulation.apply(settings)
        simulation.wake()
        previousLength = simulation.physics.currentLength
        var previousEnd = simulation.physics.endPoint
        for _ in 1...120 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60.0)
            let currentLength = simulation.physics.currentLength
            try expect(currentLength <= previousLength)
            try expectLessThan((simulation.physics.endPoint - previousEnd).magnitude, 100)
            previousLength = currentLength
            previousEnd = simulation.physics.endPoint
        }
        try expectEqual(simulation.physics.currentLength, 20, accuracy: 0.01)

        var lengthSamples: [CGFloat] = []
        for rate in [30, 60, 120, 144] {
            let candidate = PendantSimulation(settings: PendantSettings(), frameDurations: durations, ropeFrameDurations: ropeDurations)
            candidate.reset(anchor: anchor)
            var candidateSettings = candidate.settings
            try candidateSettings.set(600, for: .length)
            candidate.apply(candidateSettings)
            candidate.wake()
            var elapsed = 0.0
            while elapsed < 0.1 {
                let step = min(1.0 / Double(rate), 0.1 - elapsed)
                candidate.advance(anchor: anchor, elapsed: step)
                elapsed += step
            }
            lengthSamples.append(candidate.physics.currentLength)
        }
        for sample in lengthSamples.dropFirst() {
            try expectEqual(sample, lengthSamples[0], accuracy: 0.02)
        }
    }

    func testApplyingModeUsesIndependentParametersAndRetainsCount() throws {
        var settings = PendantSettings()
        settings.setCount(8)
        for (index, mode) in DisplayMode.allCases.enumerated() {
            try settings.set(777 + Double(index), for: .length, mode: mode)
            try settings.set(188 + Double(index), for: .weight, mode: mode)
        }
        let simulation = PendantSimulation(settings: settings, frameDurations: durations, ropeFrameDurations: ropeDurations)
        for (index, mode) in DisplayMode.allCases.enumerated() {
            settings.mode = mode
            simulation.apply(settings)
            simulation.reset(anchor: anchor)
            try expectEqual(simulation.physics.length, 777 + CGFloat(index))
            try expectEqual(simulation.physics.weight, 188 + CGFloat(index))
            try expectEqual(simulation.settings.balloonCount, 8)
        }
    }

    func testTimelineOriginalFrameOrderDurationAndLooping() throws {
        let timeline = AnimationTimeline(frameDurations: durations)
        try expectEqual(timeline.duration, 2.48, accuracy: 0.0001)
        for index in 0..<62 {
            try expectEqual(timeline.frameIndex(at: Double(index) * 0.04 + 0.02), index)
        }
        try expectEqual(timeline.frameIndex(at: 2.5), 0)
        try expectEqual(timeline.frameIndex(at: -1), 0)
    }

    func testTimelineClampsElapsedAndResetStartsAtFirstFrame() throws {
        var timeline = AnimationTimeline(frameDurations: durations)
        timeline.advance(elapsed: 10)
        try expectEqual(timeline.elapsed, 0.1)
        timeline.advance(elapsed: -5)
        try expectEqual(timeline.elapsed, 0.1)
        timeline.reset()
        try expectEqual(timeline.frameIndex, 0)
        try expectEqual(timeline.elapsed, 0)
    }

    func testExistingPhysicsAndBambooRegression() throws {
        runPhysicsTests()
    }
}
