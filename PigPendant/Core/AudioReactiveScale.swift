import Foundation

enum AudioReactiveScale {
    static func scale(forRMS rms: Double) -> CGFloat {
        guard rms.isFinite, rms > 0 else { return 0.55 }
        let decibels = 20 * log10(rms)
        let normalized = min(1, max(0, (decibels + 48) / 42))
        return CGFloat(0.55 + normalized * 1.25)
    }
}
