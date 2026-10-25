import AppKit

final class PigOverlayView: NSView {
    var scene: SceneSnapshot?
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
        guard let scene = scene, scene.isVisible,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let origin = window?.frame.origin ?? .zero
        if (scene.mode == .ghost || scene.mode == .ghostWave), let position = scene.ghostPosition {
            RopeRenderer.drawGhost(scene: scene, position: position, context: context, origin: origin)
            return
        }
        guard scene.ropes.first?.nodes.count ?? 0 > 1 else { return }
        if let pose = scene.bambooPose {
            BambooRenderer.draw(scene: scene, pose: pose, context: context, origin: origin)
        } else {
            RopeRenderer.draw(scene: scene, context: context, origin: origin)
        }
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
