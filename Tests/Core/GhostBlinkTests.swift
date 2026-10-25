import Foundation
@testable import PigPendantCore

final class GhostBlinkTests {
    func testRandomBlinksHaveClosedHoldAndIdenticalRest() throws {
        var blink = GhostBlinkAnimation(seed: 17)
        var starts: [Double] = []
        var lastEnd = 0.0
        var hold = 0.0
        var phases = Set<Int>()
        for frame in 0..<3600 {
            let active = blink.isAnimating
            blink.advance(elapsed: 1.0 / 120)
            if !active && blink.isAnimating {
                starts.append(Double(frame + 1) / 120 - lastEnd)
                hold = 0
            }
            let sample = blink.sample
            try expect((0..<8).contains(sample.firstIndex) && (0..<8).contains(sample.secondIndex))
            if blink.isAnimating { phases.insert(sample.firstIndex) }
            if sample.firstIndex == 3 || sample.firstIndex == 4 { hold += 1.0 / 120 }
            if active && !blink.isAnimating {
                try expectEqual(hold, 0.28, accuracy: 0.02)
                try expectEqual(blink.sample, .rest)
                lastEnd = Double(frame + 1) / 120
            }
        }
        try expectGreaterThan(starts.count, 4)
        try expect(phases == Set(0..<8))
        try expect(starts[0] >= 1.2 && starts[0] <= 2.51)
        try expect(starts.dropFirst().allSatisfy { $0 >= 2.99 && $0 <= 6.01 })
    }

    func testSeedFrameRatesAndInvalidClock() throws {
        func firstStarts(rate: Int) -> [Double] {
            var blink = GhostBlinkAnimation(seed: 17)
            var result: [Double] = []
            for frame in 0..<(rate * 20) {
                let active = blink.isAnimating
                blink.advance(elapsed: 1.0 / Double(rate))
                if !active && blink.isAnimating { result.append(Double(frame + 1) / Double(rate)) }
            }
            return result
        }
        let reference = firstStarts(rate: 60)
        for rate in [15, 30, 120, 144] {
            for (a, b) in zip(reference.prefix(3), firstStarts(rate: rate).prefix(3)) {
                try expectEqual(a, b, accuracy: 0.25)
            }
        }
        var blink = GhostBlinkAnimation(seed: 17)
        for _ in 0..<300 { blink.advance(elapsed: 1.0 / 60) }
        let held = blink.sample
        let clock = blink.elapsed
        for delta in [0, -1, .nan, .infinity] {
            try expect(!blink.advance(elapsed: delta))
            try expectEqual(blink.sample, held)
            try expectEqual(blink.elapsed, clock)
        }
        blink.reset()
        try expectEqual(blink.sample, .rest)
        try expectEqual(blink.elapsed, 0)
    }

    func testGhostIdleUpdatesBlinkAndHaloWithoutRopeIntegration() throws {
        var settings = PendantSettings()
        settings.mode = .ghost
        let simulation = PendantSimulation(settings: settings, frameDurations: Array(repeating: 0.04, count: 62),
                                           ropeFrameDurations: Array(repeating: 0.04, count: 75), animationSeed: 17)
        let anchor = V2(-300, 200)
        simulation.reset(anchor: anchor)
        let position = simulation.ghostPosition
        let nodes = simulation.physics.nodes
        var sawBlink = false
        var sawHalo = false
        var sawQuietGestures = false
        var sawBodyTail = false
        for _ in 0..<3600 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            try expect(simulation.isIdle)
            try expectEqual((simulation.ghostPosition - position).magnitude, 0)
            try expect(zip(nodes, simulation.physics.nodes).allSatisfy { ($0 - $1).magnitude == 0 })
            sawBlink = sawBlink || simulation.ghostBlink.isAnimating
            sawHalo = sawHalo || simulation.haloAnimation.isAnimating
            sawQuietGestures = sawQuietGestures || (!simulation.ghostBlink.isAnimating && !simulation.ghostBody.isGesturing)
            sawBodyTail = sawBodyTail || (simulation.ghostBody.isGesturing && !simulation.ghostBlink.isAnimating)
            try expectEqual(simulation.updateInterval, 1.0 / 60)
        }
        try expect(sawBlink && sawHalo && sawQuietGestures && sawBodyTail)
        let blink = simulation.ghostBlink.sample
        let halo = simulation.haloAnimation.pose
        let body = simulation.ghostBody.pose
        simulation.reset(anchor: anchor)
        try expectEqual(simulation.ghostBlink.sample, blink)
        try expectEqual(simulation.haloAnimation.pose, halo)
        try expectEqual(simulation.ghostBody.pose, body)
        simulation.advance(anchor: anchor + V2(120, -80), elapsed: 0.05)
        try expect(!simulation.isIdle)
        settings.mode = .rope
        simulation.apply(settings)
        try expectEqual(simulation.ghostBlink.sample, .rest)
        try expectEqual(simulation.haloAnimation.pose, HaloPose())
        try expectEqual(simulation.ghostBody.pose, GhostBodyPose())
    }

    func testWaveGhostIdleUpdatesBlinkAndHaloWithoutRopeIntegration() throws {
        var settings = PendantSettings()
        settings.mode = .ghostWave
        let simulation = PendantSimulation(settings: settings, frameDurations: Array(repeating: 0.04, count: 62),
                                           ropeFrameDurations: Array(repeating: 0.04, count: 75), animationSeed: 17)
        let anchor = V2(320, -120)
        simulation.reset(anchor: anchor)
        let position = simulation.ghostPosition
        let nodes = simulation.physics.nodes
        var sawBlink = false
        var sawHalo = false
        var sawBodyGesture = false
        for _ in 0..<3600 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            try expect(simulation.isIdle)
            try expectEqual((simulation.ghostPosition - position).magnitude, 0)
            try expect(zip(nodes, simulation.physics.nodes).allSatisfy { ($0 - $1).magnitude == 0 })
            sawBlink = sawBlink || simulation.ghostBlink.isAnimating
            sawHalo = sawHalo || simulation.haloAnimation.isAnimating
            sawBodyGesture = sawBodyGesture || simulation.ghostBody.isGesturing
            try expectEqual(simulation.updateInterval, 1.0 / 60)
        }
        try expect(sawBlink && sawHalo && sawBodyGesture)
        try expect(simulation.isGhostMode)
        settings.mode = .ghost
        simulation.apply(settings)
        try expect(simulation.isGhostMode)
        settings.mode = .rope
        simulation.apply(settings)
        try expect(!simulation.isGhostMode)
        try expectEqual(simulation.ghostBlink.sample, .rest)
    }

    func testBodyLagContinuityAndSettling() throws {
        for rate in [15, 30, 60, 120, 144] {
            var body = GhostBodyAnimation()
            var steps = Set<Int>()
            var previous = body.pose
            for frame in 0..<(rate * 4) {
                body.advance(elapsed: 1.0 / Double(rate), blinking: frame < rate / 2, horizontalVelocity: 0)
                steps.insert(body.pose.step)
                if body.pose.step != 0 {
                    try expect(abs(body.pose.phase - previous.phase) < 0.04)
                }
                previous = body.pose
                if frame == rate { try expect(body.isGesturing) }
            }
            try expectGreaterThan(steps.count, 30)
            try expectEqual(body.pose.step, 0)
            try expectEqual(body.pose.drift, 0)
            try expect(!body.isGesturing)
            for direction in [1.0, -1.0] {
                for _ in 0..<rate {
                    body.advance(elapsed: 1.0 / Double(rate), blinking: false, horizontalVelocity: direction * 900)
                }
                try expect(Double(body.pose.drift) * direction > 14)
            }
            let held = body.pose
            for delta in [0, -1, .nan, .infinity] {
                try expect(!body.advance(elapsed: delta, blinking: true, horizontalVelocity: 500))
                try expectEqual(body.pose, held)
            }
            for _ in 0..<(rate * 2) {
                body.advance(elapsed: 1.0 / Double(rate), blinking: false, horizontalVelocity: 0)
            }
            try expectEqual(body.pose.step, 0)
            try expectEqual(body.pose.drift, 0)
            try expect(!body.isGesturing)
            let hemPhase = body.pose.hemPhase
            body.advance(elapsed: 1, blinking: false, horizontalVelocity: 10000)
            try expectEqual(body.pose.drift, 0)
            try expectEqual(body.pose.hemPhase, (hemPhase + 0.1 / GhostBodyPose.hemPeriod).truncatingRemainder(dividingBy: 1),
                            accuracy: 1.0 / Double(GhostBodyPose.hemSteps))
            body.advance(elapsed: 0.05, blinking: true, horizontalVelocity: 600)
            body.reset()
            try expectEqual(body.pose, GhostBodyPose())
            try expect(!body.isGesturing)
        }
    }

    func testHemFlowsWithoutBlinksAcrossFrameRatesAndLoopSeam() throws {
        for rate in [15, 30, 60, 120, 144] {
            var body = GhostBodyAnimation()
            var steps = Set<Int>()
            var wraps = 0
            for _ in 0..<(rate * 12) {
                let previous = body.pose
                body.advance(elapsed: 1.0 / Double(rate), blinking: false, horizontalVelocity: 0)
                steps.insert(body.pose.hemStep)
                if body.pose.hemStep < previous.hemStep { wraps += 1 }
                let delta = (body.pose.hemPhase - previous.hemPhase + 1).truncatingRemainder(dividingBy: 1)
                try expect(delta <= 1.0 / Double(rate) / GhostBodyPose.hemPeriod + 1.0 / Double(GhostBodyPose.hemSteps))
                try expectEqual(body.pose.step, 0)
                try expectEqual(body.pose.drift, 0)
                try expect(!body.isGesturing)
            }
            try expectEqual(wraps, 3)
            try expectGreaterThan(steps.count, 40)
            try expectEqual(body.pose.hemPhase, 0.75, accuracy: 1.0 / Double(GhostBodyPose.hemSteps))
            let held = body.pose
            for delta in [0, -1, .nan, .infinity] {
                try expect(!body.advance(elapsed: delta, blinking: false, horizontalVelocity: 0))
                try expectEqual(body.pose, held)
            }
        }
    }
}
