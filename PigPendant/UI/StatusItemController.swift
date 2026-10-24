import AppKit

final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    private let controller: PendantCoordinator
    private let openSettings: () -> Void
    private let statusFrames: [NSImage]
    private var iconTimer: Timer?
    private(set) var iconRotation: CGFloat = 0
    private let iconRotationPeriod: TimeInterval = 1.2
    private let iconAnimationStartTime = ProcessInfo.processInfo.systemUptime
    private let iconCanvasSize: CGFloat = 42
    private let iconFrameSize: CGFloat = 28
    private var scaleStart: CGFloat = 1
    private var scaleTarget: CGFloat = 1
    private var scaleTransitionStart: TimeInterval = 0
    private var scaleTransitionDuration: TimeInterval = 1.6
    private var nextScaleTransition: TimeInterval = 0.6

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
            let scale = self.iconScale(at: elapsed)
            self.statusItem.button?.image = self.makeStatusFrame(frameIndex, scale: scale)
        }
        iconTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func iconScale(at elapsed: TimeInterval) -> CGFloat {
        if elapsed >= nextScaleTransition {
            scaleStart = scaleTarget
            scaleTarget = CGFloat.random(in: 0.6...1.4)
            scaleTransitionStart = elapsed
            scaleTransitionDuration = Double.random(in: 1.4...2.2)
            nextScaleTransition = elapsed + scaleTransitionDuration + Double.random(in: 0.2...0.6)
        }
        let progress = min(1, max(0, (elapsed - scaleTransitionStart) / scaleTransitionDuration))
        let eased = progress * progress * (3 - 2 * progress)
        return scaleStart + (scaleTarget - scaleStart) * CGFloat(eased)
    }

    private func makeStatusFrame(_ frameIndex: Int, scale: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: iconCanvasSize, height: iconCanvasSize))
        image.lockFocus()
        let size = iconFrameSize * scale
        let origin = (iconCanvasSize - size) / 2
        statusFrames[frameIndex].draw(in: CGRect(x: origin, y: origin, width: size, height: size))
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
        let detail = NSMenuItem(title: controller.mode.menuDescription(balloonCount: controller.balloonCount),
                                action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出猪猪挂件", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
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
