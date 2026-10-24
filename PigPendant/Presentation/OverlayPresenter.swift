import AppKit

final class OverlayPresenter {
    private(set) var windows: [NSPanel] = []
    private(set) var views: [PigOverlayView] = []
    private var lastDrawBounds: NSRect?

    func rebuild(isVisible: Bool) {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        views.removeAll()
        lastDrawBounds = nil
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let view = PigOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = false
            panel.contentView = view
            windows.append(panel)
            views.append(view)
            if isVisible { panel.orderFrontRegardless() }
        }
    }

    func setVisible(_ visible: Bool) {
        for panel in windows {
            if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        }
    }

    func present(_ scene: SceneSnapshot) {
        let dirty = lastDrawBounds.map { NSUnionRect(scene.bounds, $0) } ?? scene.bounds
        lastDrawBounds = scene.bounds
        for view in views {
            view.scene = scene
            let origin = view.window?.frame.origin ?? .zero
            let clipped = dirty.offsetBy(dx: -origin.x, dy: -origin.y).intersection(view.bounds)
            if !clipped.isNull && !clipped.isEmpty { view.setNeedsDisplay(clipped) }
        }
    }
}
