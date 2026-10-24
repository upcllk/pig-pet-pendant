import Foundation

struct AnimationTimeline {
    let frameDurations: [TimeInterval]
    let duration: TimeInterval
    private(set) var elapsed: TimeInterval = 0

    init(frameDurations: [TimeInterval]) {
        precondition(!frameDurations.isEmpty && frameDurations.allSatisfy { $0.isFinite && $0 > 0 })
        self.frameDurations = frameDurations
        duration = frameDurations.reduce(0, +)
    }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: duration)
        var end = 0.0
        for (index, delay) in frameDurations.enumerated() {
            end += delay
            if phase < end { return index }
        }
        return frameDurations.count - 1
    }

    var frameIndex: Int { frameIndex(at: elapsed) }

    mutating func advance(elapsed: TimeInterval) {
        self.elapsed += min(0.1, max(0, elapsed))
    }

    mutating func reset() { elapsed = 0 }
}
