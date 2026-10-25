import Foundation

struct GhostBlinkAnimation {
    static let keyDurations: [TimeInterval] = [0.07, 0.10, 0.10, 0.14, 0.14, 0.13, 0.13, 0.10]
    let frameDurations: [TimeInterval]
    private var randomState: UInt64
    private var waiting: TimeInterval = 0
    private var actionTime: TimeInterval?
    private(set) var elapsed: TimeInterval = 0

    init(frameDurations: [TimeInterval] = Self.keyDurations, seed: UInt64) {
        precondition(frameDurations.count == 8 && frameDurations.allSatisfy { $0.isFinite && $0 > 0 })
        self.frameDurations = frameDurations
        randomState = seed
        reset()
    }

    var isAnimating: Bool { actionTime != nil }
    var sample: CharacterFrameSample {
        guard var time = actionTime else { return .rest }
        for (index, duration) in frameDurations.enumerated() {
            if time < duration {
                let next = min(7, index + 1)
                return CharacterFrameSample(firstIndex: index, secondIndex: next,
                                            fraction: next == index ? 0 : time / duration)
            }
            time -= duration
        }
        return .rest
    }

    mutating func reset() {
        elapsed = 0
        actionTime = nil
        waiting = 1.2 + randomUnit() * 1.3
    }

    @discardableResult
    mutating func advance(elapsed delta: TimeInterval) -> Bool {
        guard delta.isFinite, delta > 0 else { return false }
        let previous = sample
        let step = min(0.1, delta)
        elapsed += step
        if let time = actionTime {
            let next = time + step
            if next >= frameDurations.reduce(0, +) {
                actionTime = nil
                waiting = 3 + randomUnit() * 3
            } else {
                actionTime = next
            }
        } else {
            waiting -= step
            if waiting <= 0 { actionTime = max(0, -waiting) }
        }
        return sample != previous
    }

    private mutating func randomUnit() -> Double {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Double(randomState >> 11) / 9007199254740992
    }
}
