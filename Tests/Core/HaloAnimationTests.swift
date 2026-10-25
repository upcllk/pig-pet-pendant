import Foundation
@testable import PigPendantCore

final class HaloAnimationTests {
    func testLagReboundAndSettlingAcrossFrameRates() throws {
        var results: [HaloPose] = []
        for rate in [30, 60, 120, 144] {
            var halo = HaloAnimation(seed: 17)
            for _ in 0..<(rate / 2) {
                halo.advance(elapsed: 1.0 / Double(rate), localVelocity: V2(700, -500), characterActive: true)
            }
            try expect(halo.pose.offset.x * 48 < -2 && halo.pose.offset.y * 48 > 2 && halo.pose.angle < -0.14)
            try expect(halo.isAnimating)
            results.append(halo.pose)
            var rebounded = false
            var maxAngle: CGFloat = 0
            var maxOffset: CGFloat = 0
            for _ in 0..<(rate * 3) {
                halo.advance(elapsed: 1.0 / Double(rate), localVelocity: V2(0, 0), characterActive: true)
                rebounded = rebounded || halo.pose.angle > 0.002
                maxAngle = max(maxAngle, abs(halo.pose.angle))
                maxOffset = max(maxOffset, halo.pose.offset.magnitude)
            }
            try expect(rebounded)
            try expect(!halo.isAnimating)
            try expectEqual(halo.pose, HaloPose())
            try expect(maxAngle < 0.224 && maxOffset < 0.096)
        }
        for pose in results.dropFirst() {
            try expectEqual(Double(pose.angle), Double(results[0].angle), accuracy: 0.002)
            try expectLessThan((pose.offset - results[0].offset).magnitude, 0.001)
        }
    }

    func testIdleSpacingAndInvalidInput() throws {
        var halo = HaloAnimation(seed: 17)
        for _ in 0..<600 {
            halo.advance(elapsed: 1.0 / 60, localVelocity: V2(0, 0), characterActive: true)
        }
        try expect(!halo.isAnimating)
        var starts = 0
        var wasActive = false
        var sawRest = false
        for _ in 0..<3600 {
            halo.advance(elapsed: 1.0 / 60, localVelocity: V2(0, 0), characterActive: false)
            if halo.isAnimating && !wasActive { starts += 1 }
            sawRest = sawRest || !halo.isAnimating
            wasActive = halo.isAnimating
        }
        try expect(starts >= 4 && starts <= 8 && sawRest)
        let held = halo.pose
        for delta in [0, -1, .infinity, .nan] {
            try expect(!halo.advance(elapsed: delta, localVelocity: V2(0, 0), characterActive: false))
            try expectEqual(halo.pose, held)
        }
        try expect(!halo.advance(elapsed: 0.05, localVelocity: V2(.nan, 0), characterActive: false))
        halo.reset()
        try expectEqual(halo.pose, HaloPose())
        try expect(!halo.isAnimating)
    }

    func testSimulationSchedulingResumeAndModeReset() throws {
        var settings = PendantSettings()
        settings.mode = .hanging
        let simulation = PendantSimulation(settings: settings, frameDurations: Array(repeating: 0.04, count: 62),
                                           ropeFrameDurations: Array(repeating: 0.04, count: 75), animationSeed: 17)
        let anchor = V2(-400, 300)
        simulation.reset(anchor: anchor)
        simulation.advance(anchor: anchor, elapsed: 0.01)
        let heldNodes = simulation.physics.nodes
        var sawHaloOnly = false
        var sawFullIdle = false
        for _ in 0..<3600 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            try expect(simulation.isIdle)
            if simulation.haloAnimation.isAnimating && !simulation.ropeAnimation.isAnimating {
                sawHaloOnly = true
                try expectEqual(simulation.updateInterval, 1.0 / 60)
            }
            if !simulation.haloAnimation.isAnimating && !simulation.ropeAnimation.isAnimating {
                sawFullIdle = true
                try expectEqual(simulation.updateInterval, 1.0 / 15)
            }
            try expect(zip(simulation.physics.nodes, heldNodes).allSatisfy { ($0 - $1).magnitude < 0.0001 })
        }
        try expect(sawHaloOnly && sawFullIdle)
        for _ in 0..<1200 {
            simulation.advance(anchor: anchor, elapsed: 1.0 / 60)
            if simulation.haloAnimation.isAnimating { break }
        }
        try expect(simulation.haloAnimation.isAnimating)
        let held = simulation.haloAnimation.pose
        simulation.reset(anchor: anchor)
        try expectEqual(simulation.haloAnimation.pose, held)
        settings.mode = .balloon
        simulation.apply(settings)
        try expectEqual(simulation.haloAnimation.pose, HaloPose())
        try expect(!simulation.haloAnimation.isAnimating)
        var halo = HaloAnimation(seed: 17)
        for frame in 0..<3600 {
            let direction: CGFloat = (frame / 15).isMultiple(of: 2) ? 1 : -1
            let velocity = frame < 600 ? V2(0, 0) : V2(2000 * direction, -2000 * direction)
            halo.advance(elapsed: 1.0 / 60, localVelocity: velocity, characterActive: false)
            try expect(abs(halo.pose.angle) < 0.24 && halo.pose.offset.magnitude < 0.096)
        }
    }
}
