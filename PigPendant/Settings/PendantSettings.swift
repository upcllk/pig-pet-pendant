import Foundation

enum ParameterID: Int, CaseIterable {
    case length, size, weight, elasticity, sway, damping, gravity

    var storageKey: String {
        switch self {
        case .length: return "RopeLength"
        case .size: return "PigSize"
        case .weight: return "Weight"
        case .elasticity: return "Elasticity"
        case .sway: return "NudgeSwingAmplitude"
        case .damping: return "DampingRate"
        case .gravity: return "Gravity"
        }
    }

    var configurationKey: String {
        switch self {
        case .length: return "length"
        case .size: return "size"
        case .weight: return "weight"
        case .elasticity: return "elasticity"
        case .sway: return "sway"
        case .damping: return "damping"
        case .gravity: return "gravity"
        }
    }

    func storageKey(for mode: DisplayMode) -> String {
        "\(storageKey).\(mode.rawValue)"
    }

    var range: ClosedRange<Double> {
        switch self {
        case .length: return 20...1200
        case .size: return 16...256
        case .weight, .elasticity, .sway: return 0...200
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
        case .sway: return 100
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
        case .sway: return "拱身晃动"
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
        case .sway: return "绳子静止后小猪轻拱时带起的前后摆动幅度；0%关闭，100%为默认幅度"
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
        case .sway: return String(format: "%.0f%%", value)
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

    var configurationKey: String {
        switch self {
        case .horizontal: return "horizontal"
        case .vertical: return "vertical"
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

enum HaloSpacing {
    static let modes: [DisplayMode] = [.ghost, .ghostWave, .hanging]
    static let range: ClosedRange<Double> = -120...120
    static let defaultValue = 0.0

    static func storageKey(for mode: DisplayMode) -> String {
        "HaloSpacing.\(mode.rawValue)"
    }

    static func readout(_ value: Double) -> String {
        String(format: "%+.0f 点", value)
    }
}

enum HaloSize {
    static let modes = HaloSpacing.modes
    static let range: ClosedRange<Double> = 25...300
    static let defaultValue = 100.0

    static func storageKey(for mode: DisplayMode) -> String {
        "HaloSize.\(mode.rawValue)"
    }

    static func readout(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}

struct PendantSettings {
    static let countRange = 1...8
    static let defaultCount = 2
    var mode: DisplayMode = .rope
    private(set) var balloonCount = defaultCount
    private var values: [DisplayMode: [ParameterID: Double]] = [:]
    private var ghostOffsets: [GhostOffsetAxis: Double] = [:]
    private var haloSpacings: [DisplayMode: Double] = [:]
    private var haloSizes: [DisplayMode: Double] = [:]
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

    subscript(haloSpacingFor mode: DisplayMode) -> Double {
        haloSpacings[mode] ?? HaloSpacing.defaultValue
    }

    subscript(haloSizeFor mode: DisplayMode) -> Double {
        haloSizes[mode] ?? HaloSize.defaultValue
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

    mutating func setHaloSpacing(_ value: Double, for mode: DisplayMode) throws {
        guard HaloSpacing.modes.contains(mode) else {
            throw SettingsError.unsupportedHaloSpacingMode(mode)
        }
        guard value.isFinite else {
            throw SettingsError.nonFiniteHaloSpacing(mode)
        }
        haloSpacings[mode] = min(HaloSpacing.range.upperBound,
                                 max(HaloSpacing.range.lowerBound, value))
    }

    mutating func setHaloSize(_ value: Double, for mode: DisplayMode) throws {
        guard HaloSize.modes.contains(mode) else {
            throw SettingsError.unsupportedHaloSizeMode(mode)
        }
        guard value.isFinite else {
            throw SettingsError.nonFiniteHaloSize(mode)
        }
        haloSizes[mode] = min(HaloSize.range.upperBound, max(HaloSize.range.lowerBound, value))
    }

    mutating func setCount(_ count: Int) {
        balloonCount = min(Self.countRange.upperBound, max(Self.countRange.lowerBound, count))
    }
}

enum SettingsError: Error {
    case nonFinite(ParameterID)
    case nonFiniteGhostOffset(GhostOffsetAxis)
    case unsupportedHaloSpacingMode(DisplayMode)
    case nonFiniteHaloSpacing(DisplayMode)
    case unsupportedHaloSizeMode(DisplayMode)
    case nonFiniteHaloSize(DisplayMode)
}
