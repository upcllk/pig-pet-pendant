import Foundation
import CoreGraphics

struct BambooBend {
    var progress: CGFloat = 1
    private var stillTime: CGFloat = 0
    private var progressVelocity: CGFloat = 0
    var isSettled: Bool { progress >= 1 && abs(progressVelocity) < 0.01 }
    var angle: CGFloat { -.pi / 2 * progress * progress * (3 - 2 * progress) }

    init(progress: CGFloat = 1) {
        self.progress = progress
    }

    mutating func advance(elapsed: CGFloat, moving: Bool) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        let step = min(0.1, elapsed)
        if moving { stillTime = 0 } else { stillTime += step }
        let bendingDown = !moving && stillTime > 0.2
        let targetVelocity: CGFloat = moving ? -1.2 : (bendingDown ? 0.62 : 0)
        let response: CGFloat = moving || bendingDown ? 4 : 14
        let decay = CGFloat(exp(Double(-response * step)))
        let initialVelocity = progressVelocity
        let delta = targetVelocity * step
            + (initialVelocity - targetVelocity) * (1 - decay) / response
        progressVelocity = targetVelocity + (initialVelocity - targetVelocity) * decay
        progress = min(1, max(0, progress + delta))
        if (progress == 0 && progressVelocity < 0) || (progress == 1 && progressVelocity > 0) {
            progressVelocity = 0
        }
    }
}

struct BambooPose {
    static let frontFoot = V2(0.365, 0.0125)
    static let rearFoot = V2(0.747, 0.005)
    static let shortFoot = V2(0.115, 0.105)
    static let feet = [frontFoot, rearFoot, shortFoot]
    let angle: CGFloat
    let bendProgress: CGFloat
    let tip: V2
    let points: [V2]
    private let initialPosition: CGFloat

    init(anchor: V2, length: CGFloat, bend: BambooBend, sway: CGFloat, initialPosition: CGFloat = 0.5) {
        angle = bend.angle + sway
        bendProgress = min(1, max(0, bend.progress))
        self.initialPosition = min(1, max(0, initialPosition))
        let direction = V2(cos(angle), sin(angle))
        let turn = -bend.angle
        let rootDirection = V2(cos(sway), sin(sway))
        let rootNormal = V2(-sin(sway), cos(sway))
        let horizontal = turn > 0.0001 ? length * sin(turn) / turn : length
        let vertical = turn > 0.0001 ? length * (cos(turn) - 1) / turn : 0
        let end = anchor + rootDirection * horizontal + rootNormal * vertical
        tip = end
        let handle = turn > 0.0001 ? length / turn * (4 / 3) * tan(turn / 4) : length / 3
        let first = anchor + rootDirection * handle
        let second = end - direction * handle
        points = (0...24).map { index in
            let progress = CGFloat(index) / 24
            let inverse = 1 - progress
            return anchor * (inverse * inverse * inverse)
                + first * (3 * inverse * inverse * progress)
                + second * (3 * inverse * progress * progress)
                + end * (progress * progress * progress)
        }
    }

    func pigDistanceFromTip(width: CGFloat) -> CGFloat {
        let progress = bendProgress * bendProgress * (3 - 2 * bendProgress)
        let arcLength = zip(points, points.dropFirst()).reduce(CGFloat(0)) {
            $0 + ($1.1 - $1.0).magnitude
        }
        let gripSpan = (Self.rearFoot - Self.shortFoot).magnitude * width
        let startDistance = min(arcLength * (1 - initialPosition), max(0, arcLength - gripSpan * 1.15))
        let endDistance = min(startDistance, width * 0.30)
        return startDistance + (endDistance - startDistance) * progress
    }

    func point(distanceFromTip: CGFloat) -> V2 {
        var remaining = max(0, distanceFromTip)
        for index in stride(from: points.count - 1, through: 1, by: -1) {
            let delta = points[index - 1] - points[index]
            let length = delta.magnitude
            if remaining <= length && length > 0 {
                return points[index] + delta * (remaining / length)
            }
            remaining -= length
        }
        return points[0]
    }

    func grip(width: CGFloat) -> (origin: V2, angle: CGFloat) {
        let rearDistance = pigDistanceFromTip(width: width)
        let rear = point(distanceFromTip: rearDistance)
        let sourceDelta = Self.rearFoot - Self.shortFoot
        let separation = sourceDelta.magnitude * width
        var lower = rearDistance
        var upper = rearDistance + separation * 1.15
        for _ in 0..<24 {
            let middle = (lower + upper) * 0.5
            if (point(distanceFromTip: middle) - rear).magnitude < separation {
                lower = middle
            } else {
                upper = middle
            }
        }
        let front = point(distanceFromTip: (lower + upper) * 0.5)
        let delta = rear - front
        let angle = atan2(delta.y, delta.x) - atan2(sourceDelta.y, sourceDelta.x)
        let sourceFront = Self.shortFoot * width
        let offset = V2(sourceFront.x * cos(angle) - sourceFront.y * sin(angle),
                        sourceFront.x * sin(angle) + sourceFront.y * cos(angle))
        return (front - offset, angle)
    }

    func contact(for foot: V2, width: CGFloat) -> V2 {
        let grip = grip(width: width)
        let direction = V2(cos(grip.angle), sin(grip.angle))
        let normal = V2(-direction.y, direction.x)
        let local = points.map { point -> V2 in
            let offset = (point - grip.origin) / width
            return V2(offset.x * direction.x + offset.y * direction.y,
                      offset.x * normal.x + offset.y * normal.y)
        }
        for (start, end) in zip(local, local.dropFirst()) {
            guard start.x <= foot.x, end.x >= foot.x,
                  end.x - start.x > 0.00001 else { continue }
            let fraction = (foot.x - start.x) / (end.x - start.x)
            return V2(foot.x, start.y + (end.y - start.y) * fraction)
        }
        return foot
    }
}
