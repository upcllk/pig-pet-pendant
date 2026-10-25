import AppKit
import Foundation

enum DisplayMode: String, CaseIterable {
    case rope
    case ghost
    case balloon
    case net
    case bamboo
    case hanging

    var title: String {
        switch self {
        case .rope: return "绳子挂件"
        case .balloon: return "猪猪气球"
        case .net: return "网兜小猪"
        case .bamboo: return "竹子小猪"
        case .hanging: return "猪上吊"
        case .ghost: return "幽灵猪"
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
        }
    }

    var visibilityCheckboxTitle: String {
        switch self {
        case .ghost: return "显示幽灵猪"
        case .hanging: return "显示上吊猪"
        default: return "显示小猪"
        }
    }

    var resetPoseTitle: String {
        switch self {
        case .rope: return "重置绳子姿态"
        case .balloon: return "重置气球姿态"
        case .net: return "重置网兜姿态"
        case .bamboo: return "重置竹子姿态"
        case .hanging: return "重置上吊猪姿态"
        case .ghost: return "重置幽灵猪位置"
        }
    }

    func menuDescription(balloonCount: Int) -> String {
        switch self {
        case .rope: return "绳子挂件 · 向下悬挂"
        case .balloon: return "\(balloonCount) 只气球 · 向上漂浮"
        case .net: return "网兜小猪 · 向下悬挂"
        case .bamboo: return "竹子小猪 · 弯垂时沿竹身下滑"
        case .hanging: return "猪上吊 · 绳子向下悬挂"
        case .ghost: return "幽灵猪 · 鼠标旁跟随（无绳）"
        }
    }
}
