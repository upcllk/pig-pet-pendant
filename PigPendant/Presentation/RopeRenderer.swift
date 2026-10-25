import AppKit

enum RopeRenderer {
    static func drawGhost(scene: SceneSnapshot, position: V2, context: CGContext, origin: NSPoint) {
        let point = CGPoint(x: position.x - origin.x, y: position.y - origin.y)
        let width = scene.pigSize
        let height = width * scene.imageAspect
        context.saveGState()
        let rect = NSRect(x: point.x - width * 0.5, y: point.y - height * 0.5, width: width, height: height)
        drawCharacter(scene: scene, rect: rect, context: context)
        drawHalo(scene: scene, rect: rect, width: width, context: context)
        context.restoreGState()
    }

    private static func drawCharacter(scene: SceneSnapshot, rect: NSRect, context: CGContext) {
        if let nextImage = scene.nextDisplayImage, scene.imageBlend > 0 {
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            scene.displayImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1 - scene.imageBlend)
            nextImage.draw(in: rect, from: .zero, operation: .plusLighter, fraction: scene.imageBlend)
            context.endTransparencyLayer()
        } else {
            scene.displayImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private static func drawHalo(scene: SceneSnapshot, rect: NSRect, width: CGFloat, context: CGContext) {
        guard let halo = scene.haloImage else { return }
        let pivot = CGPoint(x: rect.minX + rect.width * scene.haloCenter.x,
                            y: rect.minY + rect.height * scene.haloCenter.y)
        context.saveGState()
        context.translateBy(x: pivot.x + scene.haloPose.offset.x * width,
                            y: pivot.y + scene.haloPose.offset.y * width)
        context.rotate(by: scene.haloPose.angle)
        halo.draw(in: rect.offsetBy(dx: -pivot.x, dy: -pivot.y),
                  from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
    }

    static func draw(scene: SceneSnapshot, context: CGContext, origin: NSPoint) {
        func local(_ v: V2) -> CGPoint { CGPoint(x: v.x - origin.x, y: v.y - origin.y) }
        context.saveGState()
        context.setShouldAntialias(true)
        context.setLineWidth(scene.mode == .balloon ? 1.2 : 1.6)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(NSColor(calibratedRed: 70/255, green: 70/255, blue: 70/255, alpha: 0.96).cgColor)
        for balloon in scene.ropes {
            let nodes = balloon.nodes
            guard nodes.count > 1 else { continue }
            context.beginPath()
            context.move(to: local(nodes[0]))
            for index in 1..<(nodes.count - 1) {
                let midpoint = (nodes[index] + nodes[index + 1]) * 0.5
                context.addQuadCurve(to: local(midpoint), control: local(nodes[index]))
            }
            context.addQuadCurve(to: local(nodes[nodes.count - 1]),
                                 control: local(nodes[nodes.count - 1]))
            context.strokePath()
        }
        context.restoreGState()

        for balloon in scene.ropes {
            let bob = local(balloon.endPoint)
            let width = balloon.width
            let height = width * scene.imageAspect
            let knot = max(2, min(7, width * 0.07))
            context.saveGState()
            context.translateBy(x: bob.x, y: bob.y)
            if scene.mode != .balloon {
                context.rotate(by: balloon.endAngle * -0.70)
                let rect = scene.mode == .net
                    ? NSRect(x: -width * 0.52, y: -height, width: width, height: height)
                    : scene.mode == .hanging
                        ? NSRect(x: -width * 0.5, y: -height + 6, width: width, height: height)
                    : scene.mode == .rope
                        ? NSRect(x: -width * ArtworkCatalog.ropeAttachment.x,
                                 y: -height * (1 - ArtworkCatalog.ropeAttachment.y),
                                 width: width, height: height)
                    : NSRect(x: -width * 0.5, y: -height * 0.5, width: width, height: height)
                drawCharacter(scene: scene, rect: rect, context: context)
                drawHalo(scene: scene, rect: rect, width: width, context: context)
                context.restoreGState()
                continue
            }
            context.rotate(by: balloon.endAngle * 0.45)
            context.setFillColor(NSColor(calibratedRed: 0.96, green: 0.57, blue: 0.66, alpha: 1).cgColor)
            let neck = CGRect(x: -knot * 0.30, y: -knot * 0.05,
                              width: knot * 0.60, height: knot * 1.50)
            context.addPath(CGPath(roundedRect: neck, cornerWidth: knot * 0.30,
                                   cornerHeight: knot * 0.30, transform: nil))
            context.fillPath()
            context.setStrokeColor(NSColor(calibratedRed: 0.79, green: 0.34, blue: 0.46, alpha: 0.65).cgColor)
            context.setLineWidth(max(0.6, knot * 0.12))
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: CGPoint(x: -knot * 0.20, y: knot * 0.48))
            context.addQuadCurve(to: CGPoint(x: knot * 0.20, y: knot * 0.48),
                                 control: CGPoint(x: 0, y: knot * 0.40))
            context.strokePath()
            let rect = NSRect(x: -width * 0.5, y: knot, width: width, height: height)
            (balloon.characterImage ?? scene.displayImage).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.restoreGState()
        }
    }
}
