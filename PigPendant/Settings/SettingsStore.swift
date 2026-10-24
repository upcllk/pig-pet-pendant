import Foundation

final class SettingsStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> PendantSettings {
        var settings = PendantSettings()
        loadBambooPosition(into: &settings)
        settings.musicReactiveEnabled = defaults.bool(forKey: "MusicReactiveEnabled")
        if let raw = defaults.string(forKey: "DisplayMode") {
            if let mode = DisplayMode(rawValue: raw) {
                settings.mode = mode
            } else {
                NSLog("Invalid saved DisplayMode=%@; using rope", raw)
            }
        }
        for parameter in ParameterID.allCases {
            let needsMigration = DisplayMode.allCases.contains {
                defaults.object(forKey: parameter.storageKey(for: $0)) == nil
            }
            let legacyValue = needsMigration ? loadLegacyValue(for: parameter) : nil
            for mode in DisplayMode.allCases {
                let key = parameter.storageKey(for: mode)
                let fallback = legacyValue ?? parameter.defaultValue
                guard let saved = defaults.object(forKey: key) else {
                    applyMigrationFallback(fallback, parameter: parameter, mode: mode, key: key, settings: &settings)
                    continue
                }
                guard let value = saved as? NSNumber else {
                    NSLog("Invalid saved %@ type; using migrated/default value", key)
                    applyMigrationFallback(fallback, parameter: parameter, mode: mode, key: key, settings: &settings)
                    continue
                }
                do {
                    try settings.set(value.doubleValue, for: parameter, mode: mode)
                } catch {
                    NSLog("Invalid saved %@: %@; using migrated/default value", key, String(describing: error))
                    applyMigrationFallback(fallback, parameter: parameter, mode: mode, key: key, settings: &settings)
                }
            }
        }
        for axis in GhostOffsetAxis.allCases where defaults.object(forKey: axis.storageKey) != nil {
            guard let value = defaults.object(forKey: axis.storageKey) as? NSNumber else {
                NSLog("Invalid saved %@ type; using default", axis.storageKey)
                continue
            }
            do {
                try settings.set(value.doubleValue, for: axis)
            } catch {
                NSLog("Invalid saved %@: %@; using default", axis.storageKey, String(describing: error))
            }
        }
        if defaults.object(forKey: "BalloonCount") != nil {
            if let value = defaults.object(forKey: "BalloonCount") as? NSNumber {
                settings.setCount(value.intValue)
            } else {
                NSLog("Invalid saved BalloonCount type; using default")
            }
        }
        return settings
    }

    func save(_ settings: PendantSettings, parameter: ParameterID) {
        save(settings, parameter: parameter, mode: settings.mode)
    }

    func save(_ settings: PendantSettings, parameter: ParameterID, mode: DisplayMode) {
        defaults.set(settings[parameter, mode: mode], forKey: parameter.storageKey(for: mode))
    }

    func saveMode(_ mode: DisplayMode) {
        defaults.set(mode.rawValue, forKey: "DisplayMode")
    }

    func saveMusicReactiveEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "MusicReactiveEnabled")
    }

    func saveCount(_ count: Int) {
        defaults.set(count, forKey: "BalloonCount")
    }

    func saveBambooPosition(_ settings: PendantSettings) {
        defaults.set(settings.bambooPosition, forKey: "BambooPigPosition")
    }

    func saveGhostOffset(_ settings: PendantSettings, axis: GhostOffsetAxis) {
        defaults.set(settings[axis], forKey: axis.storageKey)
    }

    private func loadLegacyValue(for parameter: ParameterID) -> Double? {
        guard let saved = defaults.object(forKey: parameter.storageKey) else { return nil }
        guard let value = saved as? NSNumber else {
            NSLog("Invalid legacy %@ type; using default values for missing modes", parameter.storageKey)
            return nil
        }
        var settings = PendantSettings()
        do {
            try settings.set(value.doubleValue, for: parameter, mode: .rope)
            return settings[parameter, mode: .rope]
        } catch {
            NSLog("Invalid legacy %@: %@; using default values for missing modes",
                  parameter.storageKey, String(describing: error))
            return nil
        }
    }

    private func applyMigrationFallback(_ value: Double, parameter: ParameterID, mode: DisplayMode,
                                        key: String, settings: inout PendantSettings) {
        do {
            try settings.set(value, for: parameter, mode: mode)
        } catch {
            NSLog("Failed to apply fallback for %@: %@", key, String(describing: error))
        }
        defaults.set(settings[parameter, mode: mode], forKey: key)
    }

    private func loadBambooPosition(into settings: inout PendantSettings) {
        guard defaults.object(forKey: "BambooPigPosition") != nil else { return }
        guard let value = defaults.object(forKey: "BambooPigPosition") as? NSNumber else {
            NSLog("Invalid saved BambooPigPosition type; using default")
            return
        }
        guard let position = BambooPigPosition.clamped(value.doubleValue) else {
            NSLog("Invalid saved BambooPigPosition: value must be finite; using default")
            return
        }
        settings.bambooPosition = position
    }
}
