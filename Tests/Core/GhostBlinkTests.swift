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
        var sawRest = false
        for _ in 0..<3600 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            try expect(simulation.isIdle)
            try expectEqual((simulation.ghostPosition - position).magnitude, 0)
            try expect(zip(nodes, simulation.physics.nodes).allSatisfy { ($0 - $1).magnitude == 0 })
            sawBlink = sawBlink || simulation.ghostBlink.isAnimating
            sawHalo = sawHalo || simulation.haloAnimation.isAnimating
            let active = simulation.ghostBlink.isAnimating || simulation.haloAnimation.isAnimating
            sawRest = sawRest || !active
            try expectEqual(simulation.updateInterval, active ? 1.0 / 60 : 1.0 / 15)
        }
        try expect(sawBlink && sawHalo && sawRest)
        let blink = simulation.ghostBlink.sample
        let halo = simulation.haloAnimation.pose
        simulation.reset(anchor: anchor)
        try expectEqual(simulation.ghostBlink.sample, blink)
        try expectEqual(simulation.haloAnimation.pose, halo)
        simulation.advance(anchor: anchor + V2(120, -80), elapsed: 0.05)
        try expect(!simulation.isIdle)
        settings.mode = .rope
        simulation.apply(settings)
        try expectEqual(simulation.ghostBlink.sample, .rest)
        try expectEqual(simulation.haloAnimation.pose, HaloPose())
    }
}
