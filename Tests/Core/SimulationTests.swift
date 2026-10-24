import Foundation
@testable import PigPendantCore

final class SimulationTests {
    private let anchor = V2(-500, 300)
    private let durations = Array(repeating: 0.04, count: 62)

    func testEightBalloonsShareAnchorAndNonFirstActivityPreventsIdle() throws {
        var settings = PendantSettings()
        settings.mode = .balloon
        settings.setCount(8)
        let simulation = PendantSimulation(settings: settings, frameDurations: durations)
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
                let simulation = PendantSimulation(settings: settings, frameDurations: durations)
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
        let simulation = PendantSimulation(settings: settings, frameDurations: durations)
        simulation.reset(anchor: anchor)
        simulation.advance(anchor: anchor, elapsed: 0.01)
        try expect(simulation.isIdle)
        let nodes = simulation.physics.nodes
        let frame = simulation.timeline.frameIndex
        try expect(simulation.advance(anchor: anchor, elapsed: 0.045))
        try expectNotEqual(simulation.timeline.frameIndex, frame)
        for (before, after) in zip(nodes, simulation.physics.nodes) {
            try expectEqual((after - before).magnitude, 0)
        }
        try expectEqual(simulation.updateInterval, 0.04)
    }

    func testRopePendantKeepsSubtleAnimationAfterPhysicsSleeps() throws {
        let simulation = PendantSimulation(settings: PendantSettings(), frameDurations: durations)
        simulation.reset(anchor: anchor)
        simulation.advance(anchor: anchor, elapsed: 1.0 / 60.0)
        try expect(simulation.isIdle)
        let nodes = simulation.physics.nodes
        let previousTime = simulation.ropeAnimationTime

        try expect(simulation.advance(anchor: anchor, elapsed: simulation.idleInterval))
        try expect(simulation.isIdle)
        try expectGreaterThan(simulation.ropeAnimationTime, previousTime)
        try expectEqual(simulation.updateInterval, simulation.idleInterval)
        for (before, after) in zip(nodes, simulation.physics.nodes) {
            try expectEqual((after - before).magnitude, 0)
        }

        var otherMode = simulation.settings
        otherMode.mode = .balloon
        simulation.apply(otherMode)
        try expectEqual(simulation.ropeAnimationTime, 0)
    }

    func testGhostFollowsNearbyWithoutUsingRopeMotion() throws {
        var settings = PendantSettings()
        settings.mode = .ghost
        let simulation = PendantSimulation(settings: settings, frameDurations: durations)
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

    func testBambooBendMustCompleteBeforeIdleAndMovementWakesIt() throws {
        var settings = PendantSettings()
        settings.mode = .bamboo
        let simulation = PendantSimulation(settings: settings, frameDurations: durations)
        simulation.reset(anchor: anchor)
        simulation.bambooBend = BambooBend(progress: 0)
        simulation.advance(anchor: anchor, elapsed: 0.05)
        try expect(!(simulation.isIdle))
        for _ in 0..<50 { simulation.advance(anchor: anchor, elapsed: 0.05) }
        try expect(simulation.isIdle)
        try expect(simulation.bambooBend.isSettled)
        try expectEqual(simulation.updateInterval, 1.0 / 15)
        simulation.advance(anchor: anchor + V2(20, 0), elapsed: 0.05)
        try expect(!(simulation.isIdle))
        try expectLessThan(simulation.bambooBend.progress, 1)
    }

    func testBambooVerticalShakesHaveNoPoseCuts() throws {
        var settings = PendantSettings()
        settings.mode = .bamboo
        let simulation = PendantSimulation(settings: settings, frameDurations: durations)
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
        let simulation = PendantSimulation(settings: PendantSettings(), frameDurations: durations)
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
            let candidate = PendantSimulation(settings: PendantSettings(), frameDurations: durations)
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
        let simulation = PendantSimulation(settings: settings, frameDurations: durations)
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
