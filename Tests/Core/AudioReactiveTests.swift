import Foundation
@testable import PigPendantCore

final class AudioReactiveTests {
    func testRepeatedLowFrequencyHitsProduceSeparatePulses() throws {
        let sampleRate = 48_000.0
        let detector = try requireValue(DrumBeatDetector(sampleRate: sampleRate))
        let blockSize = 256
        let pulseStarts = [12_000, 36_000, 60_000]
        let pulseLength = 3_840
        let totalSamples = 96_000
        var pulses: [Double] = []

        for blockStart in stride(from: 0, to: totalSamples, by: blockSize) {
            let blockEnd = min(blockStart + blockSize, totalSamples)
            let samples = (blockStart..<blockEnd).map { index -> Float in
                let active = pulseStarts.contains { index >= $0 && index < $0 + pulseLength }
                guard active else { return 0 }
                return Float(0.8 * sin(2 * .pi * 80 * Double(index) / sampleRate))
            }
            let strength = detector.process(samples)
            if strength > 0 { pulses.append(strength) }
        }

        try expectEqual(pulses.count, 3)
        try expect(pulses.allSatisfy { $0 > 0.08 && $0 <= 1 })
    }

    func testSteadyToneDoesNotProduceRepeatedPulses() throws {
        let sampleRate = 48_000.0
        let detector = try requireValue(DrumBeatDetector(sampleRate: sampleRate))
        let blockSize = 256
        let toneStart = 24_000
        let totalSamples = 72_000
        var pulseCount = 0

        for blockStart in stride(from: 0, to: totalSamples, by: blockSize) {
            let blockEnd = min(blockStart + blockSize, totalSamples)
            let samples = (blockStart..<blockEnd).map { index -> Float in
                guard index >= toneStart else { return 0 }
                return Float(0.8 * sin(2 * .pi * 80 * Double(index) / sampleRate))
            }
            if detector.process(samples) > 0 { pulseCount += 1 }
        }

        try expect(pulseCount >= 1 && pulseCount <= 2)
    }
}
