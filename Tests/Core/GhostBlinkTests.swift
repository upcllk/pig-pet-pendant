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

    func testHemSpeedResponseContinuityFrameRatesAndRecovery() throws {
        func run(rate: Int, speed: Double) throws -> Double {
            var body = GhostBodyAnimation()
            var cycles = 0.0
            for _ in 0..<(rate * 4) {
                let previous = body.pose
                body.advance(elapsed: 1.0 / Double(rate), blinking: false, horizontalVelocity: 0,
                             mouseSpeed: speed)
                let delta = (body.pose.hemPhase - previous.hemPhase + 1).truncatingRemainder(dividingBy: 1)
                try expect(delta <= 4.0 / Double(rate) / GhostBodyPose.hemPeriod + 1.0 / Double(GhostBodyPose.hemSteps))
                cycles += delta
                try expectEqual(body.pose.step, 0)
                try expectEqual(body.pose.drift, 0)
                try expect(body.hemPlaybackRate >= 1 && body.hemPlaybackRate <= 4)
            }
            return cycles
        }
        let reference = try run(rate: 60, speed: 1800)
        for rate in [15, 30, 60, 120, 144] {
            let idle = try run(rate: rate, speed: 0)
            let slow = try run(rate: rate, speed: 150)
            let medium = try run(rate: rate, speed: 600)
            let fast = try run(rate: rate, speed: 1800)
            try expectEqual(idle, 4 / GhostBodyPose.hemPeriod, accuracy: 1.0 / Double(GhostBodyPose.hemSteps))
            try expect(slow > idle && medium > slow && fast > medium)
            try expect(fast > idle * 3)
            try expectEqual(fast, reference, accuracy: 1.0 / Double(GhostBodyPose.hemSteps))
        }
        var body = GhostBodyAnimation()
        body.advance(elapsed: 1.0 / 60, blinking: false, horizontalVelocity: 0, mouseSpeed: 1800)
        try expect(body.hemPlaybackRate > 1 && body.hemPlaybackRate < 1.4)
        for _ in 0..<120 {
            body.advance(elapsed: 1.0 / 60, blinking: false, horizontalVelocity: 0, mouseSpeed: 1800)
        }
        let fastRate = body.hemPlaybackRate
        body.advance(elapsed: 1.0 / 60, blinking: false, horizontalVelocity: 0)
        try expect(body.hemPlaybackRate < fastRate && body.hemPlaybackRate > 2.5)
        for _ in 0..<120 {
            body.advance(elapsed: 1.0 / 60, blinking: false, horizontalVelocity: 0)
        }
        try expectEqual(body.hemPlaybackRate, 1, accuracy: 0.000001)
        let held = body.pose
        let heldRate = body.hemPlaybackRate
        for speed in [-1, Double.nan, .infinity] {
            try expect(!body.advance(elapsed: 0.05, blinking: true, horizontalVelocity: 0, mouseSpeed: speed))
            try expectEqual(body.pose, held)
            try expectEqual(body.hemPlaybackRate, heldRate)
        }
        body.advance(elapsed: 0.1, blinking: false, horizontalVelocity: 0, mouseSpeed: 1e9)
        try expect(body.hemPlaybackRate > 1)
        let phase = body.pose.hemPhase
        body.advance(elapsed: 10, blinking: false, horizontalVelocity: 0, mouseSpeed: 1e9)
        try expectEqual(body.hemPlaybackRate, 1)
        try expectEqual(body.pose.hemPhase,
                        (phase + 0.1 / GhostBodyPose.hemPeriod).truncatingRemainder(dividingBy: 1),
                        accuracy: 1.0 / Double(GhostBodyPose.hemSteps))
        var idleBody = GhostBodyAnimation()
        var fastBody = GhostBodyAnimation()
        for frame in 0..<240 {
            let blinking = frame < 30 || (120..<150).contains(frame)
            idleBody.advance(elapsed: 1.0 / 60, blinking: blinking, horizontalVelocity: 300)
            fastBody.advance(elapsed: 1.0 / 60, blinking: blinking, horizontalVelocity: 300,
                             mouseSpeed: .greatestFiniteMagnitude)
            try expectEqual(fastBody.pose.step, idleBody.pose.step)
            try expectEqual(fastBody.pose.drift, idleBody.pose.drift)
            try expect(fastBody.hemPlaybackRate.isFinite && fastBody.hemPlaybackRate <= 4)
        }
        try expectEqual(fastBody.hemPlaybackRate, 4, accuracy: 0.000001)
    }

    func testBothGhostModesUseMouseSpeedInAllDirectionsAndResetMotion() throws {
        for mode in [DisplayMode.ghost, .ghostWave] {
            for direction in [V2(1, 0), V2(-1, 0), V2(0, 1), V2(0, -1), V2(0.6, 0.8)] {
                var settings = PendantSettings()
                settings.mode = mode
                let simulation = PendantSimulation(settings: settings, frameDurations: Array(repeating: 0.04, count: 62),
                                                   ropeFrameDurations: Array(repeating: 0.04, count: 75), animationSeed: 17)
                var anchor = V2(-300, -200)
                simulation.reset(anchor: anchor)
                let nodes = simulation.physics.nodes
                for _ in 0..<120 {
                    anchor = anchor + direction * 30
                    simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                }
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 3.25, accuracy: 0.000001)
                try expect(zip(nodes, simulation.physics.nodes).allSatisfy { ($0 - $1).magnitude == 0 })
                for _ in 0..<12 {
                    anchor = anchor - direction * 30
                    simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                    try expectEqual(simulation.ghostBody.hemPlaybackRate, 3.25, accuracy: 0.000001)
                }
                let pose = simulation.ghostBody.pose
                anchor = anchor + V2(5000, -3000)
                simulation.reset(anchor: anchor)
                try expectEqual(simulation.ghostBody.pose, pose)
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 1)
                simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 1)
                anchor = anchor + V2(-5000, 3000)
                simulation.advance(anchor: anchor, elapsed: 5)
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 1)
                simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 1)
                for _ in 0..<120 {
                    anchor = anchor - direction * 30
                    simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
                }
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 3.25, accuracy: 0.000001)
                for _ in 0..<120 { simulation.advance(anchor: anchor, elapsed: 1.0 / 60) }
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 1, accuracy: 0.000001)
                try expect(simulation.isIdle)
                settings.mode = .rope
                simulation.apply(settings)
                try expectEqual(simulation.ghostBody.pose, GhostBodyPose())
                try expectEqual(simulation.ghostBody.hemPlaybackRate, 1)
            }
        }
    }
}
