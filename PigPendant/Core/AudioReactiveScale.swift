import Foundation

enum AudioReactiveScale {
    static let minimumScale: CGFloat = 0.73
    static let maximumScale: CGFloat = 1.6

    static func scale(forRMS rms: Double, relativeTo average: Double) -> CGFloat {
        guard rms.isFinite, rms > 0 else { return minimumScale }
        guard average.isFinite, average > 0.002 else { return 1 }
        let relativeDecibels = 20 * log10(rms / average)
        if relativeDecibels <= -10 { return minimumScale }
        if relativeDecibels < 0 {
            return minimumScale + CGFloat((relativeDecibels + 10) / 10) * 0.27
        }
        if relativeDecibels < 8 {
            return 1 + CGFloat(relativeDecibels / 8) * (maximumScale - 1)
        }
        return maximumScale
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
