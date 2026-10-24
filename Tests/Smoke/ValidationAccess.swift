import AppKit

extension PendantCoordinator {
    var physics: RopePhysics { simulation.physics }
    var bambooBend: BambooBend {
        get { simulation.bambooBend }
        set { simulation.bambooBend = newValue }
    }
    var bambooPose: BambooPose { simulation.bambooPose }
    var balloons: [RopePhysics] { simulation.balloons }
    var activeRopes: [RopePhysics] { simulation.activeRopes }
    var isIdle: Bool { simulation.isIdle }
    var netFrameIndex: Int { simulation.timeline.frameIndex }
    var idleTimerInterval: TimeInterval { simulation.idleInterval }
    var windows: [NSPanel] { presenter.windows }
    var views: [PigOverlayView] { presenter.views }
    var timer: Timer? { driver.timer }
    var timerInterval: TimeInterval { driver.interval }
    var lastTick: TimeInterval { driver.lastTick }
    var dampingRate: Double { settings[.damping] }
    var pigImage: NSImage { artwork.pig }
    var balloonImage: NSImage { artwork.balloon }
    var bambooImage: NSImage { artwork.bamboo }
    var hangingImage: NSImage { artwork.hanging }
    var ghostImage: NSImage { artwork.ghost }
    var netAnimation: AnimatedArtwork { artwork.net }
    var ropeAnimation: AnimatedArtwork { artwork.rope }

    func changeGravity(_ value: Double) { changeParameter(.gravity, value: value) }
    func changeDamping(_ value: Double) { changeParameter(.damping, value: value) }
    func changeWeight(_ value: Double) { changeParameter(.weight, value: value) }
    func changeElasticity(_ value: Double) { changeParameter(.elasticity, value: value) }
}

extension SettingsWindowController {
    var parameterLabels: [NSTextField] { parameterRows.map(\.label) }
    var sliders: [NSSlider] { parameterRows.map(\.slider) }
    var readouts: [NSTextField] { parameterRows.map(\.readout) }
}

extension PigAppDelegate {
    var statusItem: NSStatusItem? { menuController?.statusItem }
    func makeMenu() { menuController?.refresh() }
}
