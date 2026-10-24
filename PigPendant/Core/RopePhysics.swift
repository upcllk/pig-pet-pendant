import Foundation
import CoreGraphics

// 物理方式：细分 Verlet/XPBD 弹性绳，允许松弛、受力伸长与惯性甩动。
// 原 EXE 确认：RopeSegments=4、RopeLength=140、Gravity=11000、
// SpringK=760、SpringDamp=28、MassBall=19.2。
// *参数保留为逆向参考；算法和单位换算不是原 .NET IL 的逐行还原。*
final class RopePhysics {
    private(set) var nodes: [V2] = []
    private var previous: [V2] = []
    let segments = 12
    var length = CGFloat(ParameterID.length.defaultValue)
    private(set) var currentLength = CGFloat(ParameterID.length.defaultValue)
    var gravity = CGFloat(ParameterID.gravity.defaultValue)
    var dampingPerFrame = CGFloat(exp(-ParameterID.damping.defaultValue / 60))
    var weight = CGFloat(ParameterID.weight.defaultValue)
    var elasticity = CGFloat(ParameterID.elasticity.defaultValue)
    var forceDirection = V2(0, -1)
    var direction: V2 { forceDirection / max(forceDirection.magnitude, 0.00001) }
    var bobMass: CGFloat { 6 * pow(10, weight / 100) }
    var compliance: CGFloat {
        currentLength * 0.12 * pow(elasticity / 100, 2) / (1350 * 40 * CGFloat(segments))
    }
    var maximumStretch: CGFloat { 0.12 * sqrt(min(100, elasticity) / 100) }
    var maximumSegmentLength: CGFloat { currentLength * (1 + maximumStretch) / CGFloat(segments) }
    private var accumulator: CGFloat = 0
    private var lastAnchor: V2?
    let fixedStep: CGFloat = 1.0 / 120.0

    func reset(anchor: V2) {
        currentLength = length
        let distance = currentLength / CGFloat(segments)
        nodes = [anchor]
        for index in 0..<segments {
            let load = bobMass + CGFloat(segments - index - 1)
            let stretch = min(distance * maximumStretch, compliance * gravity * load)
            nodes.append(nodes[index] + direction * (distance + stretch))
        }
        previous = nodes
        accumulator = 0
        lastAnchor = anchor
    }

    func settle() {
        previous = nodes
        accumulator = 0
        lastAnchor = nodes.first
    }

    func advance(anchor: V2, timeStep: CGFloat) {
        if nodes.count != segments + 1 { reset(anchor: anchor) }
        guard anchor.x.isFinite, anchor.y.isFinite, timeStep.isFinite, timeStep > 0 else { return }
        let startAnchor = lastAnchor ?? anchor
        let anchorDisplacement = anchor - startAnchor
        if timeStep > 0.25 || anchorDisplacement.magnitude > max(600, length * 4) {
            for index in nodes.indices {
                nodes[index] = nodes[index] + anchorDisplacement
                previous[index] = previous[index] + anchorDisplacement
            }
            accumulator = 0
            lastAnchor = anchor
            return
        }
        let elapsed = min(timeStep, 0.1)
        let carriedTime = accumulator
        accumulator += elapsed
        var simulatedTime: CGFloat = 0
        while accumulator + 1e-10 >= fixedStep {
            simulatedTime += fixedStep
            let fraction = min(1, max(0, (simulatedTime - carriedTime) / elapsed))
            integrate(anchor: startAnchor + (anchor - startAnchor) * fraction)
            accumulator = max(0, accumulator - fixedStep)
        }
        lastAnchor = anchor
    }

    private func integrate(anchor: V2) {
        let h = fixedStep
        let lengthBlend = 1 - CGFloat(exp(Double(-8 * h)))
        currentLength += (length - currentLength) * lengthBlend
        if abs(length - currentLength) < 0.01 { currentLength = length }
        let segmentLength = max(1, currentLength / CGFloat(segments))
        let damping = pow(dampingPerFrame, h * 60)
        let acceleration = direction * (gravity * h * h)

        nodes[0] = anchor
        previous[0] = anchor
        for index in 1..<nodes.count {
            var velocity = (nodes[index] - previous[index]) * damping
            let maxTravel: CGFloat = 2400 * h
            if velocity.magnitude > maxTravel {
                velocity = velocity * (maxTravel / velocity.magnitude)
            }
            previous[index] = nodes[index]
            nodes[index] = nodes[index] + velocity + acceleration
        }

        let scaledCompliance = compliance / (h * h)
        let endWeight = 1 / bobMass
        let maximumLength = maximumSegmentLength
        var multipliers = Array(repeating: CGFloat(0), count: segments)
        for _ in 0..<40 {
            nodes[0] = anchor
            for index in 0..<segments {
                let delta = nodes[index + 1] - nodes[index]
                let distance = delta.magnitude
                guard distance > 0.00001 else { continue }
                let firstWeight: CGFloat = index == 0 ? 0 : 1
                let secondWeight: CGFloat = index + 1 == segments ? endWeight : 1
                let change = (-(distance - segmentLength) - scaledCompliance * multipliers[index]) /
                    (firstWeight + secondWeight + scaledCompliance)
                let multiplier = min(0, multipliers[index] + change)
                let correction = delta * ((multiplier - multipliers[index]) / distance)
                multipliers[index] = multiplier
                nodes[index] = nodes[index] - correction * firstWeight
                nodes[index + 1] = nodes[index + 1] + correction * secondWeight
            }
        }
        nodes[0] = anchor
        for index in 0..<segments {
            let delta = nodes[index + 1] - nodes[index]
            if delta.magnitude > maximumLength {
                nodes[index + 1] = nodes[index] + delta * (maximumLength / delta.magnitude)
            }
        }
    }

    var isSettled: Bool {
        guard nodes.count == segments + 1, abs(length - currentLength) < 0.01 else { return false }
        let axis = direction
        let displacement = endPoint - nodes[0]
        let drop = displacement.x * axis.x + displacement.y * axis.y
        guard drop >= currentLength * 0.98 && drop <= currentLength * 1.12 + 0.001 else { return false }
        for index in 1...segments {
            let offset = nodes[index] - nodes[0]
            if abs(offset.x * axis.y - offset.y * axis.x) > 0.2 ||
                (nodes[index] - previous[index]).magnitude / fixedStep > 0.5 {
                return false
            }
        }
        return true
    }

    var endPoint: V2 { nodes.last ?? V2(0, 0) }
    var endAngle: CGFloat {
        guard nodes.count > 1 else { return 0 }
        let delta = nodes[nodes.count - 1] - nodes[nodes.count - 2]
        // 限定相对竖直方向的旋转，避免角色翻滚。
        let angle = direction.y > 0 ? atan2(-delta.x, delta.y) : atan2(delta.x, -delta.y)
        return max(-0.85, min(0.85, angle))
    }
}
