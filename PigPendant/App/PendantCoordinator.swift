import AppKit

final class PendantCoordinator {
    private(set) var settings: PendantSettings
    private(set) var isVisible = true
    private var isSuspended = false
    private let store: SettingsStore
    let simulation: PendantSimulation
    let artwork: ArtworkCatalog
    let presenter = OverlayPresenter()
    let driver = UpdateDriver()
    var onChange: (() -> Void)?
    #if TESTING
    var validationAnchor: V2?
    var validationDefaults: UserDefaults { store.defaults }
    #endif

    var mode: DisplayMode { settings.mode }
    var balloonCount: Int { settings.balloonCount }
    var pigSize: CGFloat { CGFloat(settings[.size]) }
    var displayImage: NSImage { artwork.image(mode: mode, frameIndex: simulation.timeline.frameIndex) }

    init(resourceURL: URL, defaults: UserDefaults = .standard) throws {
        artwork = try ArtworkCatalog(resourceURL: resourceURL)
        store = SettingsStore(defaults: defaults)
        settings = store.load()
        simulation = PendantSimulation(settings: settings, frameDurations: artwork.net.frameDurations)
        driver.onTick = { [weak self] time in self?.tick(at: time) }
        rebuildWindows()
    }

    func ropeAnchor() -> V2 {
        #if TESTING
        if let validationAnchor = validationAnchor { return validationAnchor }
        #endif
        let point = NSEvent.mouseLocation
        if mode == .ghost { return V2(point.x, point.y) }
        return V2(point.x + 4, point.y + (mode == .balloon ? 6 : -6))
    }

    func sceneSnapshot() -> SceneSnapshot {
        SceneSnapshot(simulation: simulation, artwork: artwork, isVisible: isVisible)
    }

    private func redraw() { presenter.present(sceneSnapshot()) }

    private func schedule() {
        guard isVisible, !isSuspended else { return }
        driver.schedule(interval: simulation.updateInterval)
    }

    func tick(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let elapsed = driver.elapsed(at: time)
        guard isVisible, !isSuspended else { return }
        if simulation.advance(anchor: ropeAnchor(), elapsed: elapsed) { redraw() }
        schedule()
    }

    func reset() {
        simulation.reset(anchor: ropeAnchor())
        driver.resetClock()
        redraw()
        schedule()
    }

    func rebuildWindows() {
        presenter.rebuild(isVisible: isVisible)
        reset()
    }

    func toggleVisible() {
        isVisible.toggle()
        if isVisible { reset() } else { driver.stop() }
        presenter.setVisible(isVisible)
        onChange?()
    }

    func suspend() {
        isSuspended = true
        driver.stop()
    }

    func resume() {
        isSuspended = false
        reset()
    }

    func changeParameter(_ parameter: ParameterID, value: Double) {
        do {
            try settings.set(value, for: parameter)
        } catch {
            NSLog("Rejected setting %@=%@: %@", parameter.storageKey, String(value), String(describing: error))
            return
        }
        store.save(settings, parameter: parameter)
        simulation.apply(settings)
        switch parameter {
        case .length:
            simulation.wake()
            schedule()
        case .size: redraw()
        case .gravity, .damping, .weight, .elasticity:
            simulation.wake()
            schedule()
        }
        onChange?()
    }

    func changeCount(_ count: Int) {
        settings.setCount(count)
        store.saveCount(settings.balloonCount)
        simulation.apply(settings)
        simulation.rebuildBalloons()
        reset()
        onChange?()
    }

    func changeMode(_ mode: DisplayMode) {
        settings.mode = mode
        store.saveMode(mode)
        simulation.apply(settings)
        simulation.restartAnimation()
        reset()
        onChange?()
    }

    func changeBambooPosition(_ value: Double) {
        guard let position = BambooPigPosition.clamped(value) else {
            NSLog("Rejected BambooPigPosition=%@: value must be finite", String(value))
            return
        }
        settings.bambooPosition = position
        store.saveBambooPosition(settings)
        simulation.apply(settings)
        redraw()
        onChange?()
    }

    func changeGhostOffset(_ axis: GhostOffsetAxis, value: Double) {
        do {
            try settings.set(value, for: axis)
        } catch {
            NSLog("Rejected %@=%@: %@", axis.storageKey, String(value), String(describing: error))
            return
        }
        store.saveGhostOffset(settings, axis: axis)
        simulation.apply(settings)
        simulation.wake()
        redraw()
        schedule()
        onChange?()
    }

    func changeSize(_ value: CGFloat) { changeParameter(.size, value: Double(value)) }
    func changeLength(_ value: CGFloat) { changeParameter(.length, value: Double(value)) }

    func restoreDefaults() {
        settings = PendantSettings()
        for mode in DisplayMode.allCases {
            for parameter in ParameterID.allCases {
                store.save(settings, parameter: parameter, mode: mode)
            }
        }
        store.saveCount(settings.balloonCount)
        store.saveBambooPosition(settings)
        for axis in GhostOffsetAxis.allCases { store.saveGhostOffset(settings, axis: axis) }
        store.saveMode(settings.mode)
        simulation.apply(settings)
        simulation.rebuildBalloons()
        simulation.restartAnimation()
        reset()
        onChange?()
    }
}
