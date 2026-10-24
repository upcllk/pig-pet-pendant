import AppKit
import Foundation
import ImageIO

final class PigAppDelegate: NSObject, NSApplicationDelegate {
    private let statusIconSize: CGFloat = 36.4
    private let statusIconHorizontalNudge: CGFloat = 1
    private(set) var controller: PendantCoordinator?
    private(set) var menuController: StatusItemController?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let url: URL
        let appController: PendantCoordinator
        let statusFrames: [NSImage]
        do {
            guard let resource = Bundle.main.url(forResource: "pig", withExtension: "png") else {
                throw ArtworkError.unreadable(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/pig.png"))
            }
            guard let iconResource = Bundle.main.url(forResource: "status-pig-spin", withExtension: "gif") else {
                throw ArtworkError.unreadable(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/status-pig-spin.gif"))
            }
            statusFrames = try loadStatusFrames(from: iconResource)
            url = resource
            #if TESTING
            appController = try PendantCoordinator(resourceURL: resource, defaults: ValidationPreferences().defaults)
            #else
            appController = try PendantCoordinator(resourceURL: resource)
            #endif
        } catch {
            NSLog("Application startup failed: %@", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = "无法读取应用图片素材"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        controller = appController
        appController.onChange = { [weak self] in
            self?.menuController?.refresh()
            self?.settingsController?.refresh()
        }
        menuController = StatusItemController(controller: appController, statusFrames: statusFrames) { [weak self] in self?.showSettings() }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSLog("PigPendant started; resource=%@ mode=%@ size=%.0f rope=%.0f count=%d screens=%d", url.path,
              appController.mode.rawValue, appController.pigSize, appController.settings[.length],
              appController.mode == .balloon ? appController.balloonCount : 1, NSScreen.screens.count)
        #if TESTING
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                appController.smokeCheck()
                self.makeSettingsController()?.smokeCheck()
                self.smokeCheckModeMenu()
                precondition(self.statusItem?.menu != nil && appController.isVisible)
                NSApp.terminate(nil)
            }
        }
        #endif
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    private func loadStatusFrames(from url: URL) throws -> [NSImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ArtworkError.unreadable(url)
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ArtworkError.unreadable(url) }
        return try (0..<frameCount).map { index in
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                throw ArtworkError.unreadable(url)
            }
            let pixelNudge = max(1, Int((statusIconHorizontalNudge * CGFloat(cgImage.width) / statusIconSize).rounded()))
            guard let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ArtworkError.unreadable(url)
            }
            context.interpolationQuality = .high
            context.translateBy(x: CGFloat(pixelNudge), y: 0)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            guard let shiftedImage = context.makeImage() else { throw ArtworkError.unreadable(url) }
            let frame = NSImage(cgImage: shiftedImage, size: NSSize(width: statusIconSize, height: statusIconSize))
            frame.isTemplate = false
            return frame
        }
    }

    private func makeSettingsController() -> SettingsWindowController? {
        guard let controller = controller else { return nil }
        if settingsController == nil {
            settingsController = SettingsWindowController(model: controller)
        }
        return settingsController
    }

    @objc private func showSettings() {
        let settings = makeSettingsController()
        settings?.refresh()
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func screensChanged() { controller?.rebuildWindows() }
    @objc private func willSleep() { controller?.suspend() }
    @objc private func didWake() { controller?.resume() }
}
