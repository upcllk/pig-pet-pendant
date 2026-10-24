import Foundation
import CoreGraphics

struct V2 {
    var x: CGFloat
    var y: CGFloat
    init(_ x: CGFloat, _ y: CGFloat) { self.x = x; self.y = y }
    init(_ p: NSPoint) { self.x = p.x; self.y = p.y }
    var point: NSPoint { NSPoint(x: x, y: y) }
    var magnitude: CGFloat { sqrt(x * x + y * y) }
    static func +(lhs: V2, rhs: V2) -> V2 { V2(lhs.x + rhs.x, lhs.y + rhs.y) }
    static func -(lhs: V2, rhs: V2) -> V2 { V2(lhs.x - rhs.x, lhs.y - rhs.y) }
    static func *(lhs: V2, rhs: CGFloat) -> V2 { V2(lhs.x * rhs, lhs.y * rhs) }
    static func /(lhs: V2, rhs: CGFloat) -> V2 { V2(lhs.x / rhs, lhs.y / rhs) }
}
