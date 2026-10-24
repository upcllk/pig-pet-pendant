import AppKit

final class PendantCoordinator {
    private(set) var settings: PendantSettings
    private(set) var isVisible = true
    private var isSuspended = false
    private let audioMonitor = AudioLevelMonitor()
    private var targetMusicScale: CGFloat = 1
    private(set) var musicScale: CGFloat = 1
    private(set) var isAudioPermissionPending = false
    private(set) var audioStatus = "关闭（开启后请求系统音频权限）"
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
        audioMonitor.onLevel = { [weak self] rms in
            guard let self = self, self.settings.musicReactiveEnabled,
                  self.isVisible, !self.isSuspended else { return }
            self.targetMusicScale = AudioReactiveScale.scale(forRMS: rms)
        }
        driver.onTick = { [weak self] time in self?.tick(at: time) }
        rebuildWindows()
        if settings.musicReactiveEnabled { startAudioMonitoring() }
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
        SceneSnapshot(simulation: simulation, artwork: artwork, isVisible: isVisible, musicScale: musicScale)
    }

    private func redraw() { presenter.present(sceneSnapshot()) }

    private func schedule() {
        guard isVisible, !isSuspended else { return }
        driver.schedule(interval: simulation.updateInterval)
    }

    func tick(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let elapsed = driver.elapsed(at: time)
        guard isVisible, !isSuspended else { return }
        var needsRedraw = simulation.advance(anchor: ropeAnchor(), elapsed: elapsed)
        let scaleTarget = settings.musicReactiveEnabled ? targetMusicScale : 1
        let response: CGFloat = scaleTarget > musicScale ? 12 : 5
        let step = elapsed.isFinite && elapsed > 0 ? min(0.1, CGFloat(elapsed)) : 0
        let previousScale = musicScale
        musicScale += (scaleTarget - musicScale) * (1 - CGFloat(exp(Double(-response * step))))
        needsRedraw = needsRedraw || abs(musicScale - previousScale) > 0.002
        if needsRedraw { redraw() }
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
        if isVisible {
            reset()
            if settings.musicReactiveEnabled { startAudioMonitoring() }
        } else {
            driver.stop()
            audioMonitor.stop()
            targetMusicScale = 1
            musicScale = 1
        }
        presenter.setVisible(isVisible)
        onChange?()
    }

    func suspend() {
        isSuspended = true
        driver.stop()
        audioMonitor.stop()
        targetMusicScale = 1
        musicScale = 1
    }

    func resume() {
        isSuspended = false
        reset()
        if settings.musicReactiveEnabled { startAudioMonitoring() }
    }

    func setMusicReactiveEnabled(_ enabled: Bool) {
        guard !isAudioPermissionPending else { return }
        guard enabled else {
            settings.musicReactiveEnabled = false
            store.saveMusicReactiveEnabled(false)
            audioMonitor.stop()
            targetMusicScale = 1
            audioStatus = "关闭（开启后请求系统音频权限）"
            schedule()
            onChange?()
            return
        }
        settings.musicReactiveEnabled = true
        store.saveMusicReactiveEnabled(true)
        if isVisible && !isSuspended {
            startAudioMonitoring()
        } else {
            audioStatus = "已开启；挂件显示时分析系统播放音频"
            onChange?()
        }
    }

    private func startAudioMonitoring() {
        guard settings.musicReactiveEnabled, isVisible, !isSuspended,
              !isAudioPermissionPending else { return }
        isAudioPermissionPending = true
        audioStatus = "正在请求系统音频权限…"
        onChange?()
        audioMonitor.start { [weak self] result in
            guard let self = self else { return }
            self.isAudioPermissionPending = false
            guard self.settings.musicReactiveEnabled, self.isVisible, !self.isSuspended else {
                self.audioMonitor.stop()
                self.audioStatus = self.settings.musicReactiveEnabled
                    ? "已开启；挂件显示时分析系统播放音频" : "关闭（开启后请求系统音频权限）"
                self.onChange?()
                return
            }
            switch result {
            case .success:
                self.audioStatus = "正在分析系统播放音频（仅实时，不录制）"
                self.schedule()
            case .failure(let error):
                self.settings.musicReactiveEnabled = false
                self.store.saveMusicReactiveEnabled(false)
                self.audioMonitor.stop()
                self.targetMusicScale = 1
                self.audioStatus = error.localizedDescription
                NSLog("Audio-reactive mode could not start: %@", error.localizedDescription)
            }
            self.onChange?()
        }
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
        audioMonitor.stop()
        targetMusicScale = 1
        musicScale = 1
        audioStatus = "关闭（开启后请求系统音频权限）"
        isAudioPermissionPending = false
        store.saveMusicReactiveEnabled(false)
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
