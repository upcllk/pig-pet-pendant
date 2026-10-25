import AppKit

final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    private let controller: PendantCoordinator
    private let openSettings: () -> Void
    private let statusFrames: [NSImage]
    private var iconTimer: Timer?
    private(set) var iconRotation: CGFloat = 0
    private var iconAudioScale: CGFloat = 1
    private var previousIconElapsed: TimeInterval = 0
    private let iconRotationPeriod: TimeInterval = 2.4
    private let iconAnimationStartTime = ProcessInfo.processInfo.systemUptime
    private let iconCanvasSize: CGFloat = 54.6
    private let iconFrameSize: CGFloat = 36.4

    init(controller: PendantCoordinator, statusFrames: [NSImage], openSettings: @escaping () -> Void) {
        self.controller = controller
        self.statusFrames = statusFrames
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = statusFrames[0]
        statusItem.button?.toolTip = "猪猪挂件"
        startIconAnimation()
        refresh()
    }

    deinit {
        iconTimer?.invalidate()
    }

    private func startIconAnimation() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - self.iconAnimationStartTime
            let phase = elapsed.truncatingRemainder(dividingBy: self.iconRotationPeriod) / self.iconRotationPeriod
            self.iconRotation = CGFloat(phase * 2 * .pi)
            let frameIndex = min(Int(phase * Double(self.statusFrames.count)), self.statusFrames.count - 1)
            let step = max(0, elapsed - self.previousIconElapsed)
            self.previousIconElapsed = elapsed
            self.iconAudioScale = AudioReactiveScale.smoothed(
                current: self.iconAudioScale, target: self.controller.audioReactiveScale, elapsed: step
            )
            self.statusItem.button?.image = self.makeStatusFrame(frameIndex, scale: self.iconAudioScale)
        }
        iconTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func makeStatusFrame(_ frameIndex: Int, scale: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: iconCanvasSize, height: iconCanvasSize))
        image.lockFocus()
        let size = min(iconCanvasSize, iconFrameSize * scale)
        let origin = (iconCanvasSize - size) / 2
        statusFrames[frameIndex].draw(in: CGRect(x: origin, y: origin,
                                                 width: size, height: size))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func showSettings() { openSettings() }

    func refresh() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let modes = NSMenu(title: "模式")
        for (index, mode) in DisplayMode.allCases.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = controller.mode == mode ? .on : .off
            modes.addItem(item)
        }
        let modeParent = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        modeParent.submenu = modes
        menu.addItem(modeParent)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: controller.mode.visibilityMenuTitle, action: #selector(togglePig), keyEquivalent: "")
        toggle.target = self
        toggle.state = controller.isVisible ? .on : .off
        menu.addItem(toggle)

        if controller.mode == .balloon {
            let countMenu = NSMenu(title: "气球数量")
            for count in PendantSettings.countRange {
                let item = NSMenuItem(title: "\(count) 只", action: #selector(setBalloonCount(_:)), keyEquivalent: "")
                item.target = self
                item.tag = count
                item.state = controller.balloonCount == count ? .on : .off
                countMenu.addItem(item)
            }
            let countParent = NSMenuItem(title: "气球数量", action: nil, keyEquivalent: "")
            countParent.submenu = countMenu
            menu.addItem(countParent)
        }

        let sizeTitle = ParameterID.size.title(mode: controller.mode)
        let sizeMenu = NSMenu(title: sizeTitle)
        for n in [16, 24, 36, 48, 64, 96, 128, 192, 256] {
            let item = NSMenuItem(title: "\(n) 点", action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = n
            item.state = abs(controller.pigSize - CGFloat(n)) < 0.1 ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeParent = NSMenuItem(title: sizeTitle, action: nil, keyEquivalent: "")
        sizeParent.submenu = sizeMenu
        menu.addItem(sizeParent)

        if controller.mode != .ghost {
            let lengthTitle = ParameterID.length.title(mode: controller.mode)
            let lengthMenu = NSMenu(title: lengthTitle)
            for n in [20, 60, 100, 140, 220, 320, 440, 600, 900, 1200] {
                let item = NSMenuItem(title: "\(n) 点", action: #selector(setLength(_:)), keyEquivalent: "")
                item.target = self
                item.tag = n
                item.state = abs(controller.settings[.length] - Double(n)) < 0.1 ? .on : .off
                lengthMenu.addItem(item)
            }
            let lengthParent = NSMenuItem(title: lengthTitle, action: nil, keyEquivalent: "")
            lengthParent.submenu = lengthMenu
            menu.addItem(lengthParent)
        }

        menu.addItem(.separator())
        let reset = NSMenuItem(title: controller.mode.resetPoseTitle, action: #selector(resetPig), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出猪猪挂件", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.toolTip = "猪猪挂件"
    }

    @objc private func togglePig() { controller.toggleVisible() }
    @objc private func setMode(_ sender: NSMenuItem) {
        guard DisplayMode.allCases.indices.contains(sender.tag) else { return }
        controller.changeMode(DisplayMode.allCases[sender.tag])
    }
    @objc private func setSize(_ sender: NSMenuItem) { controller.changeSize(CGFloat(sender.tag)) }
    @objc private func setLength(_ sender: NSMenuItem) { controller.changeLength(CGFloat(sender.tag)) }
    @objc private func setBalloonCount(_ sender: NSMenuItem) { controller.changeCount(sender.tag) }
    @objc private func resetPig() { controller.reset() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
