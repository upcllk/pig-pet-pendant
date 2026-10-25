import AppKit
import Foundation

enum DisplayMode: String, CaseIterable {
    case rope
    case balloon
    case net
    case bamboo
    case hanging
    case ghost
    case ghostWave

    static let allCases: [DisplayMode] = [.rope, .ghost, .ghostWave, .balloon, .net, .bamboo, .hanging]

    var title: String {
        switch self {
        case .rope: return "绳子挂件"
        case .balloon: return "猪猪气球"
        case .net: return "网兜小猪"
        case .bamboo: return "竹子小猪"
        case .hanging: return "猪上吊"
        case .ghost: return "幽灵猪"
        case .ghostWave: return "小小幽灵猪"
        }
    }

    var visibilityMenuTitle: String {
        switch self {
        case .rope: return "显示 / 隐藏小猪"
        case .balloon: return "显示 / 隐藏猪猪气球"
        case .net: return "显示 / 隐藏网兜小猪"
        case .bamboo: return "显示 / 隐藏竹子小猪"
        case .hanging: return "显示 / 隐藏上吊猪"
        case .ghost: return "显示 / 隐藏幽灵猪"
        case .ghostWave: return "显示 / 隐藏小小幽灵猪"
        }
    }

    var visibilityCheckboxTitle: String {
        switch self {
        case .ghost: return "显示幽灵猪"
        case .ghostWave: return "显示小小幽灵猪"
        case .hanging: return "显示上吊猪"
        default: return "显示小猪"
        }
    }

    var resetPoseTitle: String { "重置位置" }
}
