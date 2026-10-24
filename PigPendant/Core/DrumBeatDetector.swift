import Foundation

final class DrumBeatDetector {
    private let sampleRate: Double
    private let windowSize = 1024
    private let hopSize = 512
    private let window: [Double]
    private let bins: [(frequency: Double, weight: Double)]
    private var frame: [Double] = []
    private var previousLevels: [Double]?
    private var averageFlux = 0.0
    private var samplePosition = 0
    private var lastBeatPosition: Int?

    init?(sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        let windowSize = 1024
        self.sampleRate = sampleRate
        let frequencies: [(Double, Double)] = [
            (45, 1), (60, 1), (75, 1), (90, 1), (110, 1), (130, 1), (155, 1),
            (200, 0.45), (250, 0.45), (315, 0.45), (400, 0.45), (500, 0.45),
            (630, 0.45), (800, 0.45), (1000, 0.45), (1250, 0.45), (1600, 0.45),
            (2000, 0.45), (2500, 0.45), (3150, 0.45)
        ]
        bins = frequencies
            .filter { $0.0 < sampleRate * 0.45 }
            .map { (frequency: $0.0, weight: $0.1) }
        guard bins.count >= 4 else { return nil }
        window = (0..<windowSize).map {
            0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(windowSize - 1))
        }
        frame.reserveCapacity(windowSize * 2)
    }

    func process(_ samples: [Float]) -> Double {
        var strongestBeat = 0.0
        for sample in samples where sample.isFinite {
            frame.append(Double(sample))
            if frame.count >= windowSize {
                strongestBeat = max(strongestBeat, analyzeFrame())
                frame.removeFirst(hopSize)
                samplePosition += hopSize
            }
        }
        return strongestBeat
    }

    private func analyzeFrame() -> Double {
        var levels: [Double] = []
        levels.reserveCapacity(bins.count)
        for bin in bins {
            let coefficient = 2 * cos(2 * .pi * bin.frequency / sampleRate)
            var previous = 0.0
            var previousPrevious = 0.0
            for index in 0..<windowSize {
                let value = frame[index] * window[index] + coefficient * previous - previousPrevious
                previousPrevious = previous
                previous = value
            }
            let power = max(0, previousPrevious * previousPrevious + previous * previous
                            - coefficient * previous * previousPrevious)
                / Double(windowSize * windowSize)
            levels.append(log1p(power * 1000))
        }

        var flux = 0.0
        if let previousLevels = previousLevels {
            for index in bins.indices {
                flux += max(0, levels[index] - previousLevels[index]) * bins[index].weight
            }
        }
        previousLevels = levels

        let elapsed = Double(hopSize) / sampleRate
        let averageAmount = 1 - exp(-elapsed / 1.2)
        let threshold = max(0.12, averageFlux * 2.5)
        let strength = min(1, max(0, (flux - threshold) / 1.4))
        averageFlux += (flux - averageFlux) * averageAmount

        let position = samplePosition + windowSize
        let refractorySamples = Int(sampleRate * 0.12)
        if strength < 0.08
            || (lastBeatPosition.map { position - $0 < refractorySamples } ?? false) {
            return 0
        }
        lastBeatPosition = position
        return strength
    }
}
