import Foundation

enum ParameterID: Int, CaseIterable {
    case length, size, weight, elasticity, damping, gravity

    var storageKey: String {
        switch self {
        case .length: return "RopeLength"
        case .size: return "PigSize"
        case .weight: return "Weight"
        case .elasticity: return "Elasticity"
        case .damping: return "DampingRate"
        case .gravity: return "Gravity"
        }
    }

    func storageKey(for mode: DisplayMode) -> String {
        "\(storageKey).\(mode.rawValue)"
    }

    var range: ClosedRange<Double> {
        switch self {
        case .length: return 20...1200
        case .size: return 16...256
        case .weight, .elasticity: return 0...200
        case .damping: return 0.2...8
        case .gravity: return 100...10000
        }
    }

    var defaultValue: Double {
        switch self {
        case .length: return 140
        case .size: return 48
        case .weight: return 65
        case .elasticity: return 55
        case .damping: return -60 * log(0.985)
        case .gravity: return 1350
        }
    }

    func title(mode: DisplayMode) -> String {
        switch self {
        case .length: return mode == .bamboo ? "竹子长度" : "绳子长度"
        case .size: return "小猪尺寸"
        case .weight: return "重量感"
        case .elasticity: return mode == .bamboo ? "竹子弹性" : "绳子弹性"
        case .damping: return "摆动衰减"
        case .gravity: return mode == .balloon ? "浮力" : "重力"
        }
    }

    func help(mode: DisplayMode) -> String {
        switch self {
        case .length:
            return mode == .bamboo
                ? "竹子显示弧长，单位点；不随参考绳松弛缩短，至少为小猪宽度的1.5倍"
                : "未受力绳长，单位点；长绳可能超出屏幕"
        case .size: return "小猪宽度，单位点"
        case .weight: return "数值越大，末端质量越大；配合弹性产生拉伸滞后"
        case .elasticity:
            return mode == .bamboo
                ? "调节参考绳的受力响应以影响摆动；竹子显示弧长固定，非真实竹竿力学模拟"
                : "数值越大越容易伸长，最多额外伸长百分之十二"
        case .damping: return "数值越小，摆动持续越久"
        case .gravity:
            return mode == .balloon
                ? "向上净浮力加速度，单位点每平方秒；包含轻微侧向气流"
                : "向下重力加速度，单位点每平方秒"
        }
    }

    func readout(_ value: Double) -> String {
        switch self {
        case .length, .size: return String(format: "%.0f 点", value)
        case .weight, .elasticity: return String(format: "%.0f", value)
        case .damping: return String(format: "%.2f /s", value)
        case .gravity: return String(format: "%.0f pt/s²", value)
        }
    }
}

enum GhostOffsetAxis: Int, CaseIterable {
    case horizontal
    case vertical

    static let range: ClosedRange<Double> = -300...300

    var storageKey: String {
        switch self {
        case .horizontal: return "GhostOffsetX"
        case .vertical: return "GhostOffsetY"
        }
    }

    var title: String {
        switch self {
        case .horizontal: return "水平偏移"
        case .vertical: return "垂直偏移"
        }
    }

    var help: String {
        switch self {
        case .horizontal: return "幽灵猪相对鼠标的水平偏移；正值向右，负值向左，单位点"
        case .vertical: return "幽灵猪相对鼠标的垂直偏移；正值向上，负值向下，单位点"
        }
    }

    var defaultValue: Double {
        switch self {
        case .horizontal: return 44
        case .vertical: return 32
        }
    }

    func readout(_ value: Double) -> String { String(format: "%.0f 点", value) }

    static func clamped(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

struct PendantSettings {
    static let countRange = 1...8
    static let defaultCount = 2
    var mode: DisplayMode = .rope
    private(set) var balloonCount = defaultCount
    private var values: [DisplayMode: [ParameterID: Double]] = [:]
    private var ghostOffsets: [GhostOffsetAxis: Double] = [:]
    var bambooPosition = BambooPigPosition.defaultValue

    subscript(parameter: ParameterID) -> Double {
        self[parameter, mode: mode]
    }

    subscript(parameter: ParameterID, mode mode: DisplayMode) -> Double {
        values[mode]?[parameter] ?? parameter.defaultValue
    }

    subscript(axis: GhostOffsetAxis) -> Double {
        ghostOffsets[axis] ?? axis.defaultValue
    }

    mutating func set(_ value: Double, for parameter: ParameterID) throws {
        try set(value, for: parameter, mode: mode)
    }

    mutating func set(_ value: Double, for parameter: ParameterID, mode: DisplayMode) throws {
        guard value.isFinite else { throw SettingsError.nonFinite(parameter) }
        values[mode, default: [:]][parameter] = min(parameter.range.upperBound, max(parameter.range.lowerBound, value))
    }

    mutating func set(_ value: Double, for axis: GhostOffsetAxis) throws {
        guard let clamped = GhostOffsetAxis.clamped(value) else {
            throw SettingsError.nonFiniteGhostOffset(axis)
        }
        ghostOffsets[axis] = clamped
    }

    mutating func setCount(_ count: Int) {
        balloonCount = min(Self.countRange.upperBound, max(Self.countRange.lowerBound, count))
    }
}

enum SettingsError: Error {
    case nonFinite(ParameterID)
    case nonFiniteGhostOffset(GhostOffsetAxis)
}
