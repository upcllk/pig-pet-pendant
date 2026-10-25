import AppKit
import Foundation

extension PigAppDelegate {
    func smokeCheckModeMenu() {
        guard let controller = controller else { preconditionFailure("Missing controller") }
        guard let menuController = menuController else { preconditionFailure("Missing menu controller") }
        precondition(menuController.iconRotation > 0)
        precondition(menuController.statusItem.button?.image != nil)
        let defaults = controller.validationDefaults
        let saved = defaults.object(forKey: "DisplayMode")
        let originalMode = controller.mode
        let originalCount = controller.balloonCount
        defer {
            controller.changeCount(originalCount)
            controller.changeMode(originalMode)
            defaults.set(saved, forKey: "DisplayMode")
            makeMenu()
        }
        for mode in DisplayMode.allCases {
            guard let modes = statusItem?.menu?.items.first(where: { $0.submenu?.title == "模式" })?.submenu,
                  let item = modes.items.first(where: { $0.title == mode.title }),
                  let action = item.action else { preconditionFailure("Missing mode menu item") }
            precondition(NSApp.sendAction(action, to: item.target, from: item))
            precondition(controller.mode == mode && defaults.string(forKey: "DisplayMode") == mode.rawValue)
            precondition(modes.items.map(\.title) == DisplayMode.allCases.map(\.title))
            precondition(Array(DisplayMode.allCases.prefix(3)) == [.rope, .ghost, .ghostWave])
            guard let refreshed = statusItem?.menu?.items.first(where: { $0.submenu?.title == "模式" })?.submenu else {
                preconditionFailure("Missing refreshed mode menu")
            }
            precondition(refreshed.items.filter { $0.state == .on }.map(\.title) == [mode.title])
            guard let menu = statusItem?.menu,
                  let visibility = menu.items.first(where: { $0.title == mode.visibilityMenuTitle }),
                  let size = menu.items.first(where: { $0.title == ParameterID.size.title(mode: mode) }),
                  let reset = menu.items.first(where: { $0.title == "重置位置" }) else {
                preconditionFailure("Mode-specific menu items were not refreshed for \(mode.rawValue)")
            }
            let length = menu.items.first(where: { $0.title == ParameterID.length.title(mode: mode) })
            precondition(visibility.state == .on && size.submenu != nil && reset.isEnabled)
            precondition((length?.submenu != nil) == (mode != .ghost && mode != .ghostWave))
            let spacingParent = menu.items.first(where: { $0.title == "光环间距" })
            precondition((spacingParent?.submenu != nil) == HaloSpacing.modes.contains(mode))
            if let spacingMenu = spacingParent?.submenu {
                precondition(spacingMenu.items.map(\.tag) == [-120, -80, -40, 0, 40, 80, 120])
            }
            let haloSizeParent = menu.items.first(where: { $0.title == "光环大小" })
            precondition((haloSizeParent?.submenu != nil) == HaloSize.modes.contains(mode))
            if let haloSizeMenu = haloSizeParent?.submenu {
                precondition(haloSizeMenu.items.map(\.tag) == [25, 50, 75, 100, 125, 150, 200, 250, 300])
            }
            precondition(menu.items.allSatisfy {
                !$0.title.contains("鼠标旁跟随") && !$0.title.contains("音乐律动")
            })
            let countItem = menu.items.first(where: { $0.title == "气球数量" })
            precondition((countItem != nil) == (mode == .balloon))
            if mode == .balloon {
                guard let countMenu = countItem?.submenu,
                      countMenu.items.map(\.tag) == Array(PendantSettings.countRange),
                      let eight = countMenu.items.first(where: { $0.tag == 8 }),
                      let action = eight.action else { preconditionFailure("Balloon count menu is incomplete") }
                precondition(NSApp.sendAction(action, to: eight.target, from: eight))
                precondition(controller.balloonCount == 8)
            }
            if mode == .ghost {
                guard let spacingItem = spacingParent?.submenu?.items.first(where: { $0.tag == 40 }),
                      let action = spacingItem.action else {
                    preconditionFailure("Ghost halo spacing menu is incomplete")
                }
                precondition(NSApp.sendAction(action, to: spacingItem.target, from: spacingItem))
                precondition(controller.settings[haloSpacingFor: .ghost] == 40)
                precondition(defaults.double(forKey: HaloSpacing.storageKey(for: .ghost)) == 40)
                controller.changeHaloSpacing(HaloSpacing.defaultValue)
                guard let haloSizeItem = haloSizeParent?.submenu?.items.first(where: { $0.tag == 200 }),
                      let haloSizeAction = haloSizeItem.action else {
                    preconditionFailure("Ghost halo size menu is incomplete")
                }
                precondition(NSApp.sendAction(haloSizeAction, to: haloSizeItem.target, from: haloSizeItem))
                precondition(controller.settings[haloSizeFor: .ghost] == 200)
                precondition(defaults.double(forKey: HaloSize.storageKey(for: .ghost)) == 200)
                controller.changeHaloSize(HaloSize.defaultValue)
            }
        }
        NSLog("PASS: all seven real mode menu actions, saved selection and checkmarks")
    }

}
