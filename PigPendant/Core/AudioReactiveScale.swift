import Foundation

enum AudioReactiveScale {
    static let minimumScale: CGFloat = 0.73
    static let maximumScale: CGFloat = 1.6

    static func decayedBeatStrength(_ strength: Double, elapsed: TimeInterval) -> Double {
        let boundedStrength = strength.isFinite ? min(1, max(0, strength)) : 0
        let age = elapsed.isFinite ? max(0, elapsed) : Double.greatestFiniteMagnitude
        return boundedStrength * exp(-age / 0.28)
    }

    static func scale(forBeatStrength strength: Double, elapsed: TimeInterval) -> CGFloat {
        let beat = decayedBeatStrength(strength, elapsed: elapsed)
        return minimumScale + (maximumScale - minimumScale) * CGFloat(beat)
    }

    static func average(current: Double, sample: Double, elapsed: TimeInterval) -> Double {
        let step = min(10, max(0, elapsed))
        let amount = 1 - exp(-step / 2)
        return current + (sample - current) * amount
    }

    static func smoothed(current: CGFloat, target: CGFloat, elapsed: TimeInterval) -> CGFloat {
        let step = CGFloat(min(0.1, max(0, elapsed)))
        let response: CGFloat = target > current ? 8 : 12
        let amount = 1 - CGFloat(exp(Double(-response * step)))
        return current + (target - current) * amount
    }
}
