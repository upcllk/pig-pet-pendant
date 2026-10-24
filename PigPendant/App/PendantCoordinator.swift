import AppKit

final class PendantCoordinator {
    private(set) var settings: PendantSettings
    private(set) var isVisible = true
    private var isSuspended = false
    private let audioMonitor = AudioLevelMonitor()
    private var targetMusicScale: CGFloat = 1
    private var isAudioPermissionPending = false
    private var audioMonitoringGeneration = 0
    private(set) var audioStatus = "正在启动系统音频律动…"
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
    var audioReactiveScale: CGFloat { targetMusicScale }
    var displayImage: NSImage { artwork.image(mode: mode, frameIndex: simulation.timeline.frameIndex) }

    init(resourceURL: URL, defaults: UserDefaults = .standard) throws {
        artwork = try ArtworkCatalog(resourceURL: resourceURL)
        store = SettingsStore(defaults: defaults)
        settings = store.load()
        simulation = PendantSimulation(settings: settings, frameDurations: artwork.net.frameDurations)
        audioMonitor.onLevel = { [weak self] rms in
            guard let self = self, !self.isSuspended else { return }
            self.targetMusicScale = AudioReactiveScale.scale(forRMS: rms)
        }
        driver.onTick = { [weak self] time in self?.tick(at: time) }
        rebuildWindows()
        startAudioMonitoring()
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
        audioMonitoringGeneration += 1
        isAudioPermissionPending = false
        audioMonitor.stop()
        targetMusicScale = 1
    }

    func resume() {
        isSuspended = false
        reset()
        startAudioMonitoring()
    }

    private func startAudioMonitoring() {
        guard !isSuspended, !isAudioPermissionPending else { return }
        #if TESTING
        audioStatus = "GUI 测试期间跳过系统音频读取"
        return
        #else
        isAudioPermissionPending = true
        audioStatus = "正在请求系统音频权限…"
        onChange?()
        audioMonitoringGeneration += 1
        let generation = audioMonitoringGeneration
        audioMonitor.start { [weak self] result in
            guard let self = self else { return }
            guard self.audioMonitoringGeneration == generation else { return }
            self.isAudioPermissionPending = false
            guard !self.isSuspended else {
                self.audioMonitor.stop()
                self.audioStatus = "系统音频律动已暂停"
                self.onChange?()
                return
            }
            switch result {
            case .success:
                self.audioStatus = "正在分析系统播放音频（仅实时，不录制）"
            case .failure(let error):
                self.audioMonitor.stop()
                self.targetMusicScale = 1
                self.audioStatus = error.localizedDescription
                NSLog("Audio-reactive mode could not start: %@", error.localizedDescription)
            }
            self.onChange?()
        }
        #endif
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
        targetMusicScale = 1
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
