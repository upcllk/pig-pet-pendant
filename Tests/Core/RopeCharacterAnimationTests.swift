import Foundation
@testable import PigPendantCore

final class RopeCharacterAnimationTests {
    private let durations = Array(repeating: 0.04, count: 75)
    private let zero = V2(0, 0)

    func testIdleActionsHaveRandomGapsAndDoNotRepeat() throws {
        var player = RopeCharacterAnimation(frameDurations: durations, seed: 2026)
        var actions: [RopeCharacterAnimation.Action] = []
        var gaps: [Double] = []
        var waiting = 0.0
        for _ in 0..<(60 * 60) {
            let previous = player.action
            player.advance(elapsed: 1.0 / 60, anchorVelocity: zero, bobVelocity: zero)
            if player.action == nil {
                waiting += 1.0 / 60
                try expectEqual(player.sample, .rest)
            } else if previous == nil, let action = player.action {
                try expect(!action.isMotion)
                if let previousAction = actions.last { try expectNotEqual(action, previousAction) }
                actions.append(action)
                gaps.append(waiting)
                waiting = 0
            }
        }
        try expect(Set(actions) == Set([.blink, .ears, .stretch]))
        try expectGreaterThan(actions.count, 6)
        try expectGreaterThan(gaps[0], 1.1)
        try expect(gaps.dropFirst().allSatisfy { $0 >= 1.9 && $0 <= 5.1 })
        try expectGreaterThan((gaps.max() ?? 0) - (gaps.min() ?? 0), 1)
    }

    func testMouseMovementAndBobFallingTriggerDifferentActions() throws {
        var moving = RopeCharacterAnimation(frameDurations: durations, seed: 1)
        moving.advance(elapsed: 0.05, anchorVelocity: V2(700, 0), bobVelocity: zero)
        try expectEqual(moving.action, .moving)
        try expect(moving.isAnimating)

        var falling = RopeCharacterAnimation(frameDurations: durations, seed: 1)
        falling.advance(elapsed: 0.05, anchorVelocity: zero, bobVelocity: V2(0, -600))
        try expectEqual(falling.action, .falling)
        try expectNotEqual(falling.sample, moving.sample)

        var still = RopeCharacterAnimation(frameDurations: durations, seed: 1)
        for _ in 0..<60 { still.advance(elapsed: 1.0 / 60, anchorVelocity: zero, bobVelocity: zero) }
        try expect(!still.isAnimating)
        try expectEqual(still.sample, .rest)
    }

    func testTransitionsHaveContinuousWeightsAndNeverWrapLastToFirst() throws {
        var player = RopeCharacterAnimation(frameDurations: durations, seed: 42)
        func weights(_ sample: CharacterFrameSample) -> [Double] {
            var result = Array(repeating: 0.0, count: 75)
            result[sample.firstIndex] += 1 - sample.fraction
            result[sample.secondIndex] += sample.fraction
            return result
        }
        var previous = weights(player.sample)
        var sawEntry = false
        var sawExit = false
        var sawRestAfterAction = false
        var previousAction = player.action
        for frame in 0..<(120 * 30) {
            let velocity = frame >= 120 * 4 && frame < 120 * 6 ? V2(0, -700) : zero
            player.advance(elapsed: 1.0 / 120, anchorVelocity: zero, bobVelocity: velocity)
            let sample = player.sample
            try expect((0..<75).contains(sample.firstIndex) && (0..<75).contains(sample.secondIndex))
            try expect(sample.fraction.isFinite && (0...1).contains(sample.fraction))
            try expect(!(sample.firstIndex == 74 && sample.secondIndex == 0))
            try expect(!(sample.firstIndex == 51 && sample.secondIndex == 0))
            sawEntry = sawEntry || (sample.firstIndex == 0 && sample.secondIndex == 28)
            sawExit = sawExit || (sample.firstIndex != 0 && sample.secondIndex == 0 && sample.fraction > 0)
            sawRestAfterAction = sawRestAfterAction || (previousAction != nil && player.action == nil)
            let current = weights(sample)
            let change = zip(current, previous).reduce(0.0) { $0 + abs($1.0 - $1.1) }
            try expectLessThan(change, 0.7)
            previous = current
            previousAction = player.action
        }
        try expect(sawEntry && sawExit && sawRestAfterAction)
    }

    func testSchedulingIsSeededAndFrameRateIndependent() throws {
        func events(rate: Int) -> [(RopeCharacterAnimation.Action, Double)] {
            var player = RopeCharacterAnimation(frameDurations: durations, seed: 2026)
            var result: [(RopeCharacterAnimation.Action, Double)] = []
            for frame in 0..<(rate * 30) {
                let before = player.action
                player.advance(elapsed: 1.0 / Double(rate), anchorVelocity: zero, bobVelocity: zero)
                if before == nil, let action = player.action { result.append((action, Double(frame + 1) / Double(rate))) }
            }
            return result
        }
        let reference = events(rate: 60)
        for rate in [15, 25, 30, 120, 144] {
            let actual = events(rate: rate)
            try expectGreaterThan(actual.count, 3)
            for (expected, observed) in zip(reference.prefix(3), actual.prefix(3)) {
                try expectEqual(observed.0, expected.0)
                try expectEqual(observed.1, expected.1, accuracy: 0.25)
            }
        }
        var first = RopeCharacterAnimation(frameDurations: durations, seed: 7)
        var second = first
        for _ in 0..<1200 {
            first.advance(elapsed: 1.0 / 60, anchorVelocity: zero, bobVelocity: zero)
            second.advance(elapsed: 1.0 / 60, anchorVelocity: zero, bobVelocity: zero)
            try expectEqual(first.sample, second.sample)
            try expectEqual(first.action, second.action)
        }
    }

    func testInvalidClockDoesNotChangePlaybackAndResetReturnsToRest() throws {
        var player = RopeCharacterAnimation(frameDurations: durations, seed: 3)
        player.advance(elapsed: 0.05, anchorVelocity: V2(700, 0), bobVelocity: zero)
        let sample = player.sample
        let elapsed = player.elapsed
        for delta in [0, -1, .infinity, .nan] {
            try expect(!player.advance(elapsed: delta, anchorVelocity: zero, bobVelocity: zero))
            try expectEqual(player.sample, sample)
            try expectEqual(player.elapsed, elapsed)
        }

        player.resetMotion()
        try expectEqual(player.sample, sample)
        player.reset()
        try expectEqual(player.sample, .rest)
        try expectEqual(player.elapsed, 0)
        try expect(!player.isAnimating)
    }

    func testLocalPoseReturnsSmoothlyToRest() throws {
        for gesture in [LocalCharacterPose.Gesture.blink, .ears, .nuzzle] {
            var previous = LocalCharacterPose.rest
            for step in 0...LocalCharacterPose.steps {
                let pose = LocalCharacterPose(gesture: gesture, step: step)
                try expect((0...1).contains(pose.blink) && (0...1).contains(pose.nuzzle))
                try expectLessThan(abs(pose.blink - previous.blink), 0.19)
                try expectLessThan(abs(pose.earAngle - previous.earAngle), 0.08)
                try expectLessThan(abs(pose.nuzzle - previous.nuzzle), 0.11)
                if step == 0 || step == LocalCharacterPose.steps {
                    try expectEqual(pose.blink, 0, accuracy: 0.000001)
                    try expectEqual(pose.earAngle, 0, accuracy: 0.000001)
                    try expectEqual(pose.nuzzle, 0, accuracy: 0.000001)
                }
                previous = pose
            }
        }
    }
}
