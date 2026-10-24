import AppKit

enum BambooRenderer {
    static func draw(scene: SceneSnapshot, pose: BambooPose, context: CGContext, origin: NSPoint) {
        let width = scene.pigSize
        let angle = pose.angle
        let points = pose.points
        let tip = pose.tip
        func local(_ point: V2) -> CGPoint { CGPoint(x: point.x - origin.x, y: point.y - origin.y) }
        let path = CGMutablePath()
        path.move(to: local(points[0]))
        for index in 1..<(points.count - 1) {
            path.addQuadCurve(to: local((points[index] + points[index + 1]) * 0.5),
                              control: local(points[index]))
        }
        path.addLine(to: local(tip))
        let thickness = max(3, min(18, width * 0.10))
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (lineWidth, color, offset) in [
            (thickness, NSColor(calibratedRed: 0.33, green: 0.57, blue: 0.18, alpha: 1), CGFloat(0)),
            (thickness * 0.66, NSColor(calibratedRed: 0.48, green: 0.69, blue: 0.27, alpha: 1), thickness * 0.12),
            (thickness * 0.12, NSColor(calibratedRed: 0.64, green: 0.79, blue: 0.38, alpha: 1), thickness * 0.25)
        ] {
            context.saveGState()
            context.translateBy(x: -offset, y: offset)
            context.addPath(path)
            context.setLineWidth(lineWidth)
            context.setStrokeColor(color.cgColor)
            context.strokePath()
            context.restoreGState()
        }
        var distance: CGFloat = 0
        let spacing = max(12, width * 0.32)
        for index in 1..<points.count {
            let delta = points[index] - points[index - 1]
            let length = delta.magnitude
            guard length > 0.001 else { continue }
            var travel = spacing - distance
            while travel <= length {
                let location = points[index - 1] + delta * (travel / length)
                context.saveGState()
                let center = local(location)
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: atan2(delta.y, delta.x))
                context.setLineWidth(max(1, thickness * 0.16))
                context.setStrokeColor(NSColor(calibratedRed: 0.89, green: 0.86, blue: 0.48, alpha: 1).cgColor)
                context.move(to: CGPoint(x: 0, y: -thickness * 0.48))
                context.addQuadCurve(to: CGPoint(x: 0, y: thickness * 0.48),
                                     control: CGPoint(x: thickness * 0.30, y: 0))
                context.strokePath()
                context.restoreGState()
                travel += spacing
            }
            distance = (distance + length).truncatingRemainder(dividingBy: spacing)
        }
        context.saveGState()
        let center = local(tip - V2(cos(angle), sin(angle)) * (width * 1.90))
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        context.scaleBy(x: width, y: width)
        context.setStrokeColor(NSColor(calibratedRed: 0.32, green: 0.52, blue: 0.20, alpha: 1).cgColor)
        context.setLineWidth(0.012)
        context.move(to: CGPoint(x: 1.76, y: 0.02))
        context.addLine(to: CGPoint(x: 1.97, y: 0.24))
        context.strokePath()
        for (stem, end) in [(V2(1.92, 0.18), V2(1.96, 0.44)),
                            (V2(1.94, 0.20), V2(2.23, 0.29)),
                            (V2(1.80, -0.01), V2(2.00, -0.27))] {
            let middle = (stem + end) * 0.5
            let delta = end - stem
            let normal = V2(-delta.y, delta.x) / delta.magnitude * 0.06
            context.move(to: stem.point)
            context.addQuadCurve(to: end.point, control: (middle + normal).point)
            context.addQuadCurve(to: stem.point, control: (middle - normal).point)
            context.setFillColor(NSColor(calibratedRed: 0.43, green: 0.66, blue: 0.23, alpha: 1).cgColor)
            context.fillPath()
        }
        context.restoreGState()
        let grip = pose.grip(width: width)
        let imageOrigin = local(grip.origin)
        context.translateBy(x: imageOrigin.x, y: imageOrigin.y)
        context.rotate(by: grip.angle)
        context.scaleBy(x: width, y: width)
        scene.displayImage.draw(in: NSRect(x: 0, y: 0, width: 1, height: scene.imageAspect),
                               from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
    }
}
