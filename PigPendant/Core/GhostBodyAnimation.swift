import Foundation

struct GhostBodyPose: Equatable {
    static let steps = 144
    static let hemSteps = 192
    static let hemPeriod: TimeInterval = 3.2
    var step = 0
    var drift = 0
    var hemStep = 0
    var phase: Double { Double(step) / Double(Self.steps) }
    var hemPhase: Double { Double(hemStep) / Double(Self.hemSteps) }
    var key: Int { (step * 33 + drift + 16) * Self.hemSteps + hemStep }

    func pulse(start: Double, end: Double) -> Double {
        guard phase > start, phase < end else { return 0 }
        return pow(sin(.pi * (phase - start) / (end - start)), 2)
    }
}

struct GhostBodyAnimation {
    private var actionTime: TimeInterval?
    private var wasBlinking = false
    private var drift = 0.0
    private var hemTime: TimeInterval = 0
    private(set) var pose = GhostBodyPose()
    var isGesturing: Bool { actionTime != nil || abs(drift) > 0.015 }

    mutating func reset() { self = GhostBodyAnimation() }

    @discardableResult
    mutating func advance(elapsed: TimeInterval, blinking: Bool, horizontalVelocity: Double) -> Bool {
        guard elapsed.isFinite, elapsed > 0, horizontalVelocity.isFinite else { return false }
        let previous = pose
        let delta = min(0.1, elapsed)
        hemTime = (hemTime + delta).truncatingRemainder(dividingBy: GhostBodyPose.hemPeriod)
        if blinking && !wasBlinking && actionTime == nil { actionTime = 0 }
        wasBlinking = blinking
        if let time = actionTime {
            let next = time + delta
            actionTime = next < 2.4 ? next : nil
        }
        let target = elapsed > 0.25 ? 0 : tanh(horizontalVelocity / 300)
        drift += (target - drift) * (1 - exp(-delta * 12))
        if target == 0 && abs(drift) < 0.015 { drift = 0 }
        pose = GhostBodyPose(step: actionTime.map {
            min(GhostBodyPose.steps, Int(($0 / 2.4 * Double(GhostBodyPose.steps)).rounded()))
        } ?? 0, drift: Int((drift * 16).rounded()),
           hemStep: Int((hemTime / GhostBodyPose.hemPeriod * Double(GhostBodyPose.hemSteps)).rounded()) % GhostBodyPose.hemSteps)
        return pose != previous
    }
}
