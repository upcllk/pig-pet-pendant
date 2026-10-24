import Foundation

struct CharacterFrameSample: Equatable {
    let firstIndex: Int
    let secondIndex: Int
    let fraction: Double

    static let rest = CharacterFrameSample(firstIndex: 0, secondIndex: 0, fraction: 0)
}

struct RopeCharacterAnimation {
    enum Action: CaseIterable, Hashable {
        case blink, ears, stretch, moving, falling

        private static let blinkFrames = Array(0...28)
        private static let earFrames = Array(0...11) + Array((0..<11).reversed())
        private static let stretchFrames = Array(28...51) + Array((28..<51).reversed())

        var frames: [Int] {
            switch self {
            case .blink: return Self.blinkFrames
            case .ears, .moving: return Self.earFrames
            case .stretch, .falling: return Self.stretchFrames
            }
        }

        var isMotion: Bool { self == .moving || self == .falling }
    }

    private let frameDurations: [TimeInterval]
    private var randomState: UInt64
    private var actionTime: TimeInterval = 0
    private var idleRemaining: TimeInterval = 0
    private var motionCooldown: TimeInterval = 0
    private var motionSpeed = 0.0
    private var fallingSpeed = 0.0
    private var wasMoving = false
    private var wasFalling = false
    private var pendingMotion: Action?
    private var lastIdleChoice: Int?
    private var idleRate = 1.0
    private(set) var action: Action?
    private(set) var elapsed: TimeInterval = 0

    init(frameDurations: [TimeInterval], seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        precondition(frameDurations.count == 75 && frameDurations.allSatisfy { $0.isFinite && $0 > 0 })
        self.frameDurations = frameDurations
        randomState = seed
        reset()
    }

    var isAnimating: Bool { action != nil }

    var sample: CharacterFrameSample {
        guard let action = action else { return .rest }
        let frames = action.frames
        var time = actionTime
        if frames[0] != 0 {
            if time < 0.14 {
                return CharacterFrameSample(firstIndex: 0, secondIndex: frames[0],
                                            fraction: smoothstep(time / 0.14))
            }
            time -= 0.14
        }
        for (position, index) in frames.enumerated() {
            let duration = frameDurations[index]
            if time < duration {
                let next = frames[min(position + 1, frames.count - 1)]
                return CharacterFrameSample(firstIndex: index, secondIndex: next,
                                            fraction: next == index ? 0 : time / duration)
            }
            time -= duration
        }
        guard frames.last != 0 else { return .rest }
        return CharacterFrameSample(firstIndex: frames.last!, secondIndex: 0,
                                    fraction: smoothstep(min(1, time / 0.18)))
    }

    mutating func reset() {
        action = nil
        actionTime = 0
        elapsed = 0
        idleRemaining = 1.2 + randomUnit() * 1.3
        motionCooldown = 0
        pendingMotion = nil
        lastIdleChoice = nil
        resetMotion()
    }

    mutating func resetMotion() {
        motionSpeed = 0
        fallingSpeed = 0
        wasMoving = false
        wasFalling = false
        pendingMotion = nil
    }

    @discardableResult
    mutating func advance(elapsed delta: TimeInterval, anchorVelocity: V2, bobVelocity: V2) -> Bool {
        guard delta.isFinite, delta > 0,
              anchorVelocity.x.isFinite, anchorVelocity.y.isFinite,
              bobVelocity.x.isFinite, bobVelocity.y.isFinite else { return false }
        let before = sample
        let step = min(0.1, delta)
        elapsed += step
        let response = 1 - exp(-12 * step)
        let speed = min(2000, Double(max(anchorVelocity.magnitude, bobVelocity.magnitude)))
        let downward = min(2000, Double(max(0, -bobVelocity.y)))
        motionSpeed += (speed - motionSpeed) * response
        fallingSpeed += (downward - fallingSpeed) * response
        let moving = motionSpeed > (wasMoving ? 45 : 90)
        let falling = fallingSpeed > (wasFalling ? 55 : 110)
        if falling && !wasFalling {
            pendingMotion = .falling
        } else if moving && !wasMoving && pendingMotion != .falling {
            pendingMotion = .moving
        }
        wasMoving = moving
        wasFalling = falling
        motionCooldown = max(0, motionCooldown - step)

        if action == nil {
            if motionCooldown == 0, let requested = pendingMotion ?? (falling ? .falling : moving ? .moving : nil) {
                action = requested
                pendingMotion = nil
                actionTime = 0
            } else if !moving {
                idleRemaining -= step
                if idleRemaining <= 0 {
                    let choices: [Action] = [.blink, .ears, .stretch]
                    let choice = lastIdleChoice.map { ($0 + 1 + Int(randomUnit() * 2)) % choices.count }
                        ?? Int(randomUnit() * Double(choices.count))
                    action = choices[choice]
                    lastIdleChoice = choice
                    idleRate = 0.9 + randomUnit() * 0.2
                    actionTime = 0
                }
            }
        }
        if let action = action {
            let rate: Double
            switch action {
            case .moving: rate = 0.95 + min(1, motionSpeed / 800) * 0.5
            case .falling: rate = 1.05 + min(1, fallingSpeed / 800) * 0.5
            default: rate = idleRate
            }
            actionTime += step * rate
            let frames = action.frames
            let duration = (frames[0] == 0 ? 0 : 0.14) + frames.reduce(0) { $0 + frameDurations[$1] }
                + (frames.last == 0 ? 0 : 0.18)
            if actionTime >= duration {
                self.action = nil
                actionTime = 0
                idleRemaining = 2 + randomUnit() * 3
                motionCooldown = 0.6 + randomUnit() * 0.6
            }
        }
        return sample != before
    }

    private func smoothstep(_ value: Double) -> Double { value * value * (3 - 2 * value) }

    private mutating func randomUnit() -> Double {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Double(randomState >> 11) / 9007199254740992
    }
}
