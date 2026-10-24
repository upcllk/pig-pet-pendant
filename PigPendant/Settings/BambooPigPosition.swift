import Foundation

enum BambooPigPosition {
    static let range = 0.0...100.0
    static let defaultValue = 50.0

    static func clamped(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
