import Foundation

struct LocalCharacterPose: Hashable {
    enum Gesture: Int { case blink, ears, nuzzle }

    let gesture: Gesture
    let step: Int
    static let steps = 72
    static let rest = LocalCharacterPose(gesture: .blink, step: 0)

    private var phase: Double { Double(step) / Double(Self.steps) }
    private var envelope: Double { pow(sin(.pi * phase), 2) }
    var blink: Double {
        guard gesture == .blink else { return 0 }
        if phase < 0.30 { return smoothstep((phase - 0.04) / 0.26) }
        if phase <= 0.50 { return 1 }
        return 1 - smoothstep((phase - 0.50) / 0.44)
    }
    var earAngle: Double {
        gesture == .ears ? sin(4 * .pi * phase) * envelope * 0.36 : 0
    }
    var nuzzle: Double { gesture == .nuzzle ? envelope : 0 }

    private func smoothstep(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
    }
}
