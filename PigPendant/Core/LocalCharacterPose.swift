import Foundation

struct LocalCharacterPose: Hashable {
    enum Gesture: Int { case blink, ears, nuzzle }

    let gesture: Gesture
    let step: Int
    static let steps = 32
    static let rest = LocalCharacterPose(gesture: .blink, step: 0)

    private var phase: Double { Double(step) / Double(Self.steps) }
    private var envelope: Double { pow(sin(.pi * phase), 2) }
    var blink: Double {
        guard gesture == .blink else { return 0 }
        let value = max(0, 1 - abs(phase - 0.5) * 4)
        return value * value * (3 - 2 * value)
    }
    var earAngle: Double {
        gesture == .ears ? sin(4 * .pi * phase) * envelope * 0.18 : 0
    }
    var nuzzle: Double { gesture == .nuzzle ? envelope : 0 }
}
