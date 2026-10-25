import Foundation
import CoreGraphics

final class PendantSimulation {
    let physics = RopePhysics()
    var bambooBend = BambooBend()
    private var bambooSway: CGFloat = 0
    private var bambooMotionAnchor: V2?
    private(set) var ghostPosition = V2(0, 0)
    private(set) var balloons: [RopePhysics] = []
    private(set) var settings: PendantSettings
    private(set) var timeline: AnimationTimeline
    private(set) var ropeAnimation: RopeCharacterAnimation
    private(set) var balloonAnimations: [RopeCharacterAnimation] = []
    private let characterFrameDurations: [TimeInterval]
    private let characterSeed: UInt64
    private(set) var isIdle = false

    init(settings: PendantSettings, frameDurations: [TimeInterval], ropeFrameDurations: [TimeInterval],
         animationSeed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.settings = settings
        timeline = AnimationTimeline(frameDurations: frameDurations)
        characterFrameDurations = ropeFrameDurations
        characterSeed = animationSeed
        ropeAnimation = RopeCharacterAnimation(frameDurations: ropeFrameDurations, seed: animationSeed)
        apply(settings)
    }

    var activeRopes: [RopePhysics] { settings.mode == .balloon ? balloons : [physics] }
    var bambooPose: BambooPose {
        BambooPose(anchor: physics.nodes.first ?? V2(0, 0),
                   length: max(CGFloat(settings[.size]) * 1.5, physics.currentLength),
                   bend: bambooBend, sway: bambooSway,
                   initialPosition: CGFloat(settings.bambooPosition / 100))
    }
    var idleInterval: TimeInterval {
        if settings.mode == .net { return min(1.0 / 15.0, timeline.frameDurations.min()!) }
        if [.rope, .bamboo, .hanging].contains(settings.mode) && ropeAnimation.isAnimating {
            return 1.0 / 60.0
        }
        if settings.mode == .balloon && balloonAnimations.contains(where: \.isAnimating) { return 1.0 / 60.0 }
        return 1.0 / 15.0
    }
    var updateInterval: TimeInterval { isIdle ? idleInterval : 1.0 / 60.0 }
    var artworkFrameIndex: Int { settings.mode == .rope ? ropeAnimation.sample.firstIndex : timeline.frameIndex }

    func apply(_ settings: PendantSettings) {
        let modeChanged = self.settings.mode != settings.mode
        self.settings = settings
        physics.length = CGFloat(settings[.length])
        physics.gravity = CGFloat(settings[.gravity])
        physics.weight = CGFloat(settings[.weight])
        physics.elasticity = CGFloat(settings[.elasticity])
        physics.dampingPerFrame = CGFloat(exp(-settings[.damping] / 60))
        if balloons.count != settings.balloonCount {
            balloons = [physics] + (1..<settings.balloonCount).map { _ in RopePhysics() }
        }
        if balloonAnimations.count != settings.balloonCount {
            balloonAnimations = (0..<settings.balloonCount).map { index in
                RopeCharacterAnimation(frameDurations: characterFrameDurations,
                                       seed: characterSeed &+ (UInt64(index + 1) &* 0x9E3779B97F4A7C15))
            }
        }
        if modeChanged {
            restartAnimation()
        }
    }

    func balloonWidth(at index: Int) -> CGFloat {
        let scales: [CGFloat] = [1, 0.8, 0.92, 0.74, 1.04, 0.84, 0.96, 0.78]
        return CGFloat(settings[.size]) * scales[index % scales.count]
    }

    func rebuildBalloons() {
        balloons = [physics] + (1..<settings.balloonCount).map { _ in RopePhysics() }
    }

    func restartAnimation() {
        timeline.reset()
        ropeAnimation.reset()
        for index in balloonAnimations.indices { balloonAnimations[index].reset() }
    }

    private func updateBalloonParameters() {
        guard settings.mode == .balloon else {
            physics.forceDirection = V2(0, -1)
            return
        }
        for (index, balloon) in balloons.enumerated() {
            if index > 0 {
                balloon.length = physics.length * (0.8 + CGFloat(index % 3) * 0.06)
                balloon.gravity = physics.gravity
                balloon.weight = physics.weight
                balloon.elasticity = physics.elasticity
                balloon.dampingPerFrame = physics.dampingPerFrame
            }
            let count = settings.balloonCount
            let lane = count > 1 ? CGFloat(index) / CGFloat(count - 1) * 2 - 1 : 0
            balloon.forceDirection = V2(lane * (0.45 + CGFloat(count - 1) * 0.08), 1)
        }
    }

    func reset(anchor: V2) {
        bambooBend = BambooBend()
        bambooSway = 0
        bambooMotionAnchor = anchor
        ghostPosition = ghostTarget(anchor)
        ropeAnimation.resetMotion()
        for index in balloonAnimations.indices { balloonAnimations[index].resetMotion() }
        updateBalloonParameters()
        for rope in activeRopes { rope.reset(anchor: anchor) }
        isIdle = false
    }

    func wake() { isIdle = false }

    @discardableResult
    func advance(anchor: V2, elapsed: TimeInterval) -> Bool {
        let previousFrame = timeline.frameIndex
        let previousAnchor = physics.nodes.first ?? anchor
        let previousEndPoints = activeRopes.map(\.endPoint)
        if settings.mode == .net { timeline.advance(elapsed: elapsed) }
        if settings.mode == .ghost {
            let delta = ghostTarget(anchor) - ghostPosition
            guard delta.x.isFinite, delta.y.isFinite, elapsed.isFinite, elapsed > 0 else { return false }
            guard delta.magnitude >= 0.15 else {
                ghostPosition = ghostTarget(anchor)
                isIdle = true
                return false
            }
            let previousPosition = ghostPosition
            let step = min(0.1, CGFloat(elapsed))
            let blend = 1 - CGFloat(exp(Double(-14 * step)))
            ghostPosition = ghostPosition + delta * blend
            if (ghostTarget(anchor) - ghostPosition).magnitude < 0.15 {
                ghostPosition = ghostTarget(anchor)
                isIdle = true
            } else {
                isIdle = false
            }
            return (ghostPosition - previousPosition).magnitude > 0
        }
        let movementTolerance: CGFloat = settings.mode == .bamboo ? 1 : 0.01
        let anchorUnchanged = activeRopes.allSatisfy {
            guard let first = $0.nodes.first else { return false }
            return (anchor - first).magnitude < movementTolerance
        }
        if settings.mode == .bamboo {
            let motionReference = bambooMotionAnchor ?? anchor
            let meaningfulMovement = (anchor - motionReference).magnitude >= 2
            if meaningfulMovement { bambooMotionAnchor = anchor }
            bambooBend.advance(elapsed: CGFloat(elapsed), moving: meaningfulMovement)
        }
        let bambooSettled = settings.mode != .bamboo || bambooBend.isSettled
        let swaySettled = settings.mode != .bamboo || abs(physics.endAngle * -0.70 - bambooSway) < 0.01
        if isIdle && anchorUnchanged && bambooSettled && swaySettled {
            let artworkChanged = advanceCharacterAnimations(anchor: anchor, previousAnchor: previousAnchor,
                                                             previousEndPoints: previousEndPoints, elapsed: elapsed)
            return artworkChanged || timeline.frameIndex != previousFrame
        }
        isIdle = false
        updateBalloonParameters()
        for rope in activeRopes { rope.advance(anchor: anchor, timeStep: CGFloat(elapsed)) }
        advanceCharacterAnimations(anchor: anchor, previousAnchor: previousAnchor,
                                   previousEndPoints: previousEndPoints, elapsed: elapsed)
        if settings.mode == .bamboo, elapsed.isFinite, elapsed > 0 {
            let response = CGFloat(12)
            let step = min(0.1, CGFloat(elapsed))
            let blend = 1 - CGFloat(exp(Double(-response * step)))
            let targetSway = physics.endAngle * -0.70
            bambooSway += (targetSway - bambooSway) * blend
        }
        let bambooAnimationSettled = settings.mode != .bamboo ||
            (bambooBend.isSettled && abs(physics.endAngle * -0.70 - bambooSway) < 0.01)
        if anchorUnchanged && bambooAnimationSettled && activeRopes.allSatisfy({ $0.isSettled }) {
            for rope in activeRopes { rope.settle() }
            isIdle = true
        }
        return true
    }

    private func ghostTarget(_ anchor: V2) -> V2 {
        anchor + V2(CGFloat(settings[.horizontal]), CGFloat(settings[.vertical]))
    }

    @discardableResult
    private func advanceCharacterAnimations(anchor: V2, previousAnchor: V2, previousEndPoints: [V2],
                                             elapsed: TimeInterval) -> Bool {
        guard [.rope, .bamboo, .balloon, .hanging].contains(settings.mode), elapsed.isFinite, elapsed > 0 else { return false }
        let anchorVelocity = elapsed > 0.25 ? V2(0, 0) : (anchor - previousAnchor) / CGFloat(elapsed)
        if settings.mode == .balloon {
            var changed = false
            for index in balloons.indices {
                let before = balloonAnimations[index].localPose
                let velocity = elapsed > 0.25 ? V2(0, 0)
                    : (balloons[index].endPoint - previousEndPoints[index]) / CGFloat(elapsed)
                balloonAnimations[index].advance(elapsed: elapsed, anchorVelocity: anchorVelocity, bobVelocity: velocity)
                changed = balloonAnimations[index].localPose != before || changed
            }
            return changed
        }
        let before = ropeAnimation.localPose
        let bobVelocity = elapsed > 0.25 ? V2(0, 0) : (physics.endPoint - previousEndPoints[0]) / CGFloat(elapsed)
        if settings.mode == .bamboo || settings.mode == .hanging {
            ropeAnimation.advance(elapsed: elapsed, anchorVelocity: anchorVelocity, bobVelocity: bobVelocity)
            return ropeAnimation.localPose != before
        }
        return ropeAnimation.advance(elapsed: elapsed, anchorVelocity: anchorVelocity, bobVelocity: bobVelocity)
    }
}
            let previousAction = ropeAnimation.action
            if settings.mode == .rope, physics.isSettled,
               previousAction != .stretch, ropeAnimation.action == .stretch {
                let forward = V2(-physics.direction.y, physics.direction.x)
                physics.applyEndImpulse(forward * 150)
                isIdle = false
                return true
            }
