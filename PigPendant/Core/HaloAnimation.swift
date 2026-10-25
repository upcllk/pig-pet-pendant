import Foundation

struct HaloPose: Equatable {
    var angle: CGFloat = 0
    var offset = V2(0, 0)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.angle == rhs.angle && lhs.offset.x == rhs.offset.x && lhs.offset.y == rhs.offset.y
    }
}

struct HaloAnimation {
    private(set) var pose = HaloPose()
    private var angularVelocity: CGFloat = 0
    private var velocity = V2(0, 0)
    private var randomState: UInt64
    private var idleRemaining: TimeInterval = 0
    private var idleTime: TimeInterval?
    private var idleDirection: CGFloat = 1
    private var idlePlaneAngle: CGFloat = 0

    init(seed: UInt64) {
        randomState = seed
        reset()
    }

    var isAnimating: Bool {
        idleTime != nil || abs(pose.angle) > 0.0001 || pose.offset.magnitude > 0.0001
            || abs(angularVelocity) > 0.001 || velocity.magnitude > 0.001
    }

    mutating func reset() {
        pose = HaloPose()
        angularVelocity = 0
        velocity = V2(0, 0)
        idleTime = nil
        idleRemaining = 5 + randomUnit() * 4
    }

    @discardableResult
    mutating func advance(elapsed: TimeInterval, localVelocity: V2, characterActive: Bool) -> Bool {
        guard elapsed.isFinite, elapsed > 0, localVelocity.x.isFinite, localVelocity.y.isFinite else { return false }
        let before = pose
        var remaining = min(0.1, elapsed)
        while remaining > 0.0000001 {
            let delta = min(1.0 / 120, remaining)
            remaining -= delta
            let step = CGFloat(delta)
            let moving = localVelocity.magnitude > 40
            if let time = idleTime {
                idleTime = time + delta
                if time + delta >= 1.2 {
                    idleTime = nil
                    idleRemaining = 5 + randomUnit() * 4
                }
            } else if !moving && !characterActive && !isAnimating {
                idleRemaining -= delta
                if idleRemaining <= 0 {
                    idleTime = 0
                    idleDirection = randomUnit() < 0.5 ? -1 : 1
                    idlePlaneAngle = CGFloat(randomUnit() * 2 * .pi)
                }
            }
            let idle = idleTime.map { CGFloat(pow(sin(.pi * $0 / 1.2), 2)) } ?? 0
            let horizontal = CGFloat(tanh(Double(localVelocity.x / 450)))
            let vertical = CGFloat(tanh(Double(localVelocity.y / 450)))
            let idleWeight = idle * (1 - max(abs(horizontal), abs(vertical)))
            let phase = CGFloat((idleTime ?? 0) / 1.2)
            let planeAngle = idlePlaneAngle + idleDirection * phase * .pi
            let along = cos(planeAngle) * idleWeight * 0.065
            let across = sin(planeAngle) * idleWeight * 0.040
            let planeOffset = V2(0.64, 0.77) * along + V2(-0.77, 0.64) * across
            let targetAngle = max(-0.168, min(0.168, -horizontal * 0.168 + idleWeight * idleDirection * 0.128))
            let targetOffset = V2(-horizontal * 0.048, -vertical * 0.056) + planeOffset
            // A damped visual follower, independent of rope forces.
            angularVelocity += ((targetAngle - pose.angle) * 100 - angularVelocity * 12) * step
            velocity = velocity + ((targetOffset - pose.offset) * 100 - velocity * 12) * step
            pose.angle += angularVelocity * step
            pose.offset = pose.offset + velocity * step
        }
        if !isAnimating {
            pose = HaloPose()
            angularVelocity = 0
            velocity = V2(0, 0)
        }
        return pose != before
    }

    private mutating func randomUnit() -> Double {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Double(randomState >> 11) / 9007199254740992
    }
}
