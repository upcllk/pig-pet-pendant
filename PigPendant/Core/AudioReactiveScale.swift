import Foundation

enum AudioReactiveScale {
    static func scale(forRMS rms: Double) -> CGFloat {
        guard rms.isFinite, rms > 0 else { return 0.55 }
        let decibels = 20 * log10(rms)
        let normalized = min(1, max(0, (decibels + 48) / 42))
        return CGFloat(0.55 + normalized * 0.85)
    }

    static func smoothed(current: CGFloat, target: CGFloat, elapsed: TimeInterval) -> CGFloat {
        let step = CGFloat(min(0.1, max(0, elapsed)))
        let response: CGFloat = target > current ? 12 : 5
        let amount = 1 - CGFloat(exp(Double(-response * step)))
        return current + (target - current) * amount
    }
}
