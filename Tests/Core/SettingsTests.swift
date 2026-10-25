import Foundation
@testable import PigPendantCore

final class SettingsTests {
    private var domain: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    func setUpWithError() throws {
        domain = "local.pigpendant.unit-tests.\(UUID().uuidString)"
        defaults = try requireValue(UserDefaults(suiteName: domain))
        store = try SettingsStore(defaults: defaults)
    }

    func tearDown() throws {
        defaults.removePersistentDomain(forName: domain)
        guard defaults.synchronize() else {
            throw CheckFailure(description: "Failed to synchronize settings test cleanup: \(domain!)")
        }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
            .appendingPathComponent("\(domain!).plist")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        store = nil
        defaults = nil
        domain = nil
    }

    func testDefaultsAndOriginalStorageKeys() throws {
        let settings = store.load()
        try expectEqual(settings.mode, .rope)
        try expectEqual(Array(DisplayMode.allCases.prefix(3)), [.rope, .ghost, .ghostWave])
        try expectEqual(settings.balloonCount, 2)
        try expectEqual(ParameterID.allCases.map(\.storageKey),
                       ["RopeLength", "PigSize", "Weight", "Elasticity", "NudgeSwingAmplitude", "DampingRate", "Gravity"])
        try expectEqual(ParameterID.allCases.map { settings[$0] }, [140, 48, 65, 55, 100, -60 * log(0.985), 1350])
        try expectEqual(PendantSettings.countRange, 1...8)
        try expectEqual(ParameterID.allCases.map(\.range), [20...1200, 16...256, 0...200, 0...200, 0...200, 0.2...8, 100...10000])
        try expectEqual(GhostOffsetAxis.allCases.map(\.storageKey), ["GhostOffsetX", "GhostOffsetY"])
        try expectEqual(settings[.horizontal], 44)
        try expectEqual(settings[.vertical], 32)
        try expectEqual(GhostOffsetAxis.range, -300...300)
        try expectEqual(HaloSpacing.modes, [.ghost, .ghostWave, .hanging])
        try expectEqual(HaloSpacing.range, -120...120)
        for mode in HaloSpacing.modes {
            try expectEqual(settings[haloSpacingFor: mode], HaloSpacing.defaultValue)
        }
        try expectEqual(HaloSize.modes, HaloSpacing.modes)
        try expectEqual(HaloSize.range, 25...300)
        for mode in HaloSize.modes {
            try expectEqual(settings[haloSizeFor: mode], HaloSize.defaultValue)
        }
        try expectEqual(DisplayMode.ghostWave.title, "小小幽灵猪")
        try expectEqual(DisplayMode.ghostWave.visibilityMenuTitle, "显示 / 隐藏小小幽灵猪")
        let bundledDefaultsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("PigPendant/Resources/default-settings.json")
        let bundledDefaults = try SettingsConfiguration.load(from: bundledDefaultsURL)
        try expectEqual(bundledDefaults[.size, mode: .ghostWave], 96)
        for mode in DisplayMode.allCases {
            for parameter in ParameterID.allCases {
                try expectEqual(settings[parameter, mode: mode], parameter.defaultValue)
                try expectEqual(defaults.double(forKey: parameter.storageKey(for: mode)), parameter.defaultValue)
            }
        }
    }

    func testEditableConfigurationProvidesModeSpecificRestoreDefaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pig-pendant-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let parameters = Dictionary(uniqueKeysWithValues: DisplayMode.allCases.map { mode in
            (mode.rawValue, Dictionary(uniqueKeysWithValues: ParameterID.allCases.map {
                ($0.configurationKey, $0.defaultValue + (mode == .net ? 1 : 0))
            }))
        })
        let configuration: [String: Any] = [
            "parameters": parameters,
            "balloonCount": 5,
            "bambooPosition": 67,
            "ghostOffsets": ["horizontal": 81, "vertical": -45],
            "haloSpacing": ["ghost": -30, "ghostWave": 45, "hanging": 100],
            "haloSize": ["ghost": 75, "ghostWave": 125, "hanging": 200]
        ]
        try JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys]).write(to: url)
        let configuredStore = try SettingsStore(defaults: defaults, configurationURL: url)
        let configured = configuredStore.load()
        try expectEqual(configured[.length, mode: .net], 141)
        try expectEqual(configured[.length, mode: .rope], 140)
        try expectEqual(configured.balloonCount, 5)
        try expectEqual(configured.bambooPosition, 67)
        try expectEqual(configured[.horizontal], 81)
        try expectEqual(configured[.vertical], -45)
        try expectEqual(configured[haloSpacingFor: .ghost], -30)
        try expectEqual(configured[haloSpacingFor: .ghostWave], 45)
        try expectEqual(configured[haloSpacingFor: .hanging], 100)
        try expectEqual(configured[haloSizeFor: .ghost], 75)
        try expectEqual(configured[haloSizeFor: .ghostWave], 125)
        try expectEqual(configured[haloSizeFor: .hanging], 200)
        defaults.set(222, forKey: ParameterID.length.storageKey(for: .net))
        try expectEqual(configuredStore.load()[.length, mode: .net], 222)
        try expectEqual(configuredStore.defaultSettings[.length, mode: .net], 141)
    }

    func testHaloSpacingPersistsIndependentlyByModeAndClampsToRange() throws {
        let values: [DisplayMode: Double] = [.ghost: -72, .ghostWave: 48, .hanging: 120]
        var settings = store.load()
        for (mode, value) in values {
            try settings.setHaloSpacing(value, for: mode)
            store.saveHaloSpacing(settings, mode: mode)
        }
        let loaded = store.load()
        for (mode, value) in values {
            try expectEqual(loaded[haloSpacingFor: mode], value)
            try expectEqual(defaults.double(forKey: HaloSpacing.storageKey(for: mode)), value)
        }
        try settings.setHaloSpacing(-Double.greatestFiniteMagnitude, for: .ghost)
        try expectEqual(settings[haloSpacingFor: .ghost], HaloSpacing.range.lowerBound)
        try settings.setHaloSpacing(Double.greatestFiniteMagnitude, for: .hanging)
        try expectEqual(settings[haloSpacingFor: .hanging], HaloSpacing.range.upperBound)
        try expectThrows(try settings.setHaloSpacing(.nan, for: .ghostWave))
        try expectThrows(try settings.setHaloSpacing(10, for: .rope))
    }

    func testHaloSizePersistsIndependentlyByModeAndClampsToRange() throws {
        let values: [DisplayMode: Double] = [.ghost: 75, .ghostWave: 150, .hanging: 300]
        var settings = store.load()
        for (mode, value) in values {
            try settings.setHaloSize(value, for: mode)
            store.saveHaloSize(settings, mode: mode)
        }
        try settings.setHaloSpacing(42, for: .ghost)
        try settings.setHaloSize(125, for: .ghost)
        try expectEqual(settings[haloSpacingFor: .ghost], 42)
        let loaded = store.load()
        for (mode, value) in values {
            try expectEqual(loaded[haloSizeFor: mode], value)
            try expectEqual(defaults.double(forKey: HaloSize.storageKey(for: mode)), value)
        }
        try settings.setHaloSize(-Double.greatestFiniteMagnitude, for: .ghost)
        try expectEqual(settings[haloSizeFor: .ghost], HaloSize.range.lowerBound)
        try settings.setHaloSize(Double.greatestFiniteMagnitude, for: .hanging)
        try expectEqual(settings[haloSizeFor: .hanging], HaloSize.range.upperBound)
        try expectThrows(try settings.setHaloSize(.nan, for: .ghostWave))
        try expectThrows(try settings.setHaloSize(100, for: .rope))
    }

    func testLegacyConfigurationAddsWaveGhostDefaultsWithoutReplacingCustomValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pig-pendant-settings-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("legacy.json")
        let bundledURL = directory.appendingPathComponent("bundled.json")

        var parameters = Dictionary(uniqueKeysWithValues: DisplayMode.allCases.map { mode in
            (mode.rawValue, Dictionary(uniqueKeysWithValues: ParameterID.allCases.map {
                ($0.configurationKey, $0.defaultValue)
            }))
        })
        parameters[DisplayMode.ghostWave.rawValue]?[ParameterID.length.configurationKey] = 180
        parameters[DisplayMode.rope.rawValue]?[ParameterID.length.configurationKey] = 175

        func writeConfiguration(_ parameters: [String: [String: Double]], to url: URL) throws {
            let configuration: [String: Any] = [
                "parameters": parameters,
                "balloonCount": 5,
                "bambooPosition": 67,
                "ghostOffsets": ["horizontal": 81, "vertical": -45]
            ]
            try JSONSerialization.data(withJSONObject: configuration).write(to: url)
        }

        var legacyParameters = parameters
        legacyParameters.removeValue(forKey: DisplayMode.ghostWave.rawValue)
        try writeConfiguration(legacyParameters, to: legacyURL)
        try writeConfiguration(parameters, to: bundledURL)

        try SettingsConfiguration.migrateMissingWaveGhostDefaults(
            at: legacyURL, bundledDefaultsURL: bundledURL
        )
        let migrated = try SettingsConfiguration.load(from: legacyURL)
        try expectEqual(migrated[.length, mode: .rope], 175)
        try expectEqual(migrated[.length, mode: .ghostWave], 180)
        try expectEqual(migrated.balloonCount, 5)
        try expectEqual(migrated.bambooPosition, 67)
        try expectEqual(migrated[.horizontal], 81)
        try expectEqual(migrated[.vertical], -45)
        for mode in HaloSize.modes {
            try expectEqual(migrated[haloSizeFor: mode], HaloSize.defaultValue)
        }
    }

    func testInvalidEditableConfigurationIsRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pig-pendant-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{}".utf8).write(to: url)
        try expectThrows(try SettingsStore(defaults: defaults, configurationURL: url))
        let parameters = Dictionary(uniqueKeysWithValues: DisplayMode.allCases.map { mode in
            (mode.rawValue, Dictionary(uniqueKeysWithValues: ParameterID.allCases.map {
                ($0.configurationKey, $0.defaultValue)
            }))
        })
        let configuration: [String: Any] = [
            "parameters": parameters,
            "balloonCount": 2,
            "bambooPosition": 50,
            "ghostOffsets": ["horizontal": 44, "vertical": 32],
            "haloSize": ["ghost": 24, "ghostWave": 100, "hanging": 100]
        ]
        try JSONSerialization.data(withJSONObject: configuration).write(to: url)
        try expectThrows(try SettingsStore(defaults: defaults, configurationURL: url))
    }

    func testFiniteValuesClampAtBothBounds() throws {
        var settings = PendantSettings()
        for parameter in ParameterID.allCases {
            try settings.set(-Double.greatestFiniteMagnitude, for: parameter)
            try expectEqual(settings[parameter], parameter.range.lowerBound)
            try settings.set(Double.greatestFiniteMagnitude, for: parameter)
            try expectEqual(settings[parameter], parameter.range.upperBound)
        }
        settings.setCount(Int.min)
        try expectEqual(settings.balloonCount, 1)
        settings.setCount(Int.max)
        try expectEqual(settings.balloonCount, 8)
        for axis in GhostOffsetAxis.allCases {
            try settings.set(-Double.greatestFiniteMagnitude, for: axis)
            try expectEqual(settings[axis], GhostOffsetAxis.range.lowerBound)
            try settings.set(Double.greatestFiniteMagnitude, for: axis)
            try expectEqual(settings[axis], GhostOffsetAxis.range.upperBound)
        }
    }

    func testNonFiniteValuesAreRejectedWithoutChangingState() throws {
        var settings = PendantSettings()
        for parameter in ParameterID.allCases {
            try settings.set(parameter.range.lowerBound, for: parameter)
            for value in [Double.nan, .infinity, -.infinity] {
                try expectThrows(try settings.set(value, for: parameter))
                try expectEqual(settings[parameter], parameter.range.lowerBound)
            }
        }
        for axis in GhostOffsetAxis.allCases {
            try settings.set(axis.defaultValue, for: axis)
            for value in [Double.nan, .infinity, -.infinity] {
                try expectThrows(try settings.set(value, for: axis))
                try expectEqual(settings[axis], axis.defaultValue)
            }
        }
    }

    func testRoundTripAndModeChangesPreserveIndependentParameters() throws {
        var settings = PendantSettings()
        settings.setCount(7)
        store.saveCount(settings.balloonCount)
        for (modeIndex, mode) in DisplayMode.allCases.enumerated() {
            settings.mode = mode
            store.saveMode(mode)
            for parameter in ParameterID.allCases {
                try settings.set(parameter.range.lowerBound + Double(modeIndex + 1), for: parameter)
                store.save(settings, parameter: parameter)
            }
        }
        for (modeIndex, mode) in DisplayMode.allCases.enumerated() {
            store.saveMode(mode)
            let loaded = store.load()
            try expectEqual(loaded.mode, mode)
            try expectEqual(loaded.balloonCount, 7)
            for parameter in ParameterID.allCases {
                try expectEqual(loaded[parameter], parameter.range.lowerBound + Double(modeIndex + 1))
            }
        }
    }

    func testLegacySharedParametersMigrateToEachMode() throws {
        let legacyValues: [ParameterID: Double] = [
            .length: 333,
            .size: 88,
            .weight: 77,
            .elasticity: 44,
            .damping: 1.25,
            .gravity: 1700
        ]
        for (parameter, value) in legacyValues {
            defaults.set(value, forKey: parameter.storageKey)
        }

        let settings = store.load()
        for mode in DisplayMode.allCases {
            for parameter in ParameterID.allCases {
                let expected = mode == .ghostWave
                    ? parameter.defaultValue
                    : legacyValues[parameter] ?? parameter.defaultValue
                try expectEqual(settings[parameter, mode: mode], expected)
                try expectEqual(defaults.double(forKey: parameter.storageKey(for: mode)), expected)
            }
        }

        var ropeSettings = settings
        try ropeSettings.set(555, for: .length, mode: .rope)
        store.save(ropeSettings, parameter: .length, mode: .rope)
        let reloaded = store.load()
        try expectEqual(reloaded[.length, mode: .rope], 555)
        for mode in DisplayMode.allCases where mode != .rope {
            let expected = mode == .ghostWave ? ParameterID.length.defaultValue : legacyValues[.length]!
            try expectEqual(reloaded[.length, mode: mode], expected)
        }
    }

    func testNewWaveModeDefaultsDoNotTriggerLegacyMigrationForSavedModes() throws {
        for mode in DisplayMode.allCases where mode != .ghostWave {
            for parameter in ParameterID.allCases {
                defaults.set(parameter.defaultValue + 1, forKey: parameter.storageKey(for: mode))
            }
        }
        for parameter in ParameterID.allCases {
            defaults.set(parameter.defaultValue + 2, forKey: parameter.storageKey)
        }
        let loaded = store.load()
        for mode in DisplayMode.allCases where mode != .ghostWave {
            for parameter in ParameterID.allCases {
                try expectEqual(loaded[parameter, mode: mode], parameter.defaultValue + 1)
            }
        }
        for parameter in ParameterID.allCases {
            try expectEqual(loaded[parameter, mode: .ghostWave], parameter.defaultValue)
        }
    }

    func testSavingOneParameterDoesNotPopulateOtherKeys() throws {
        defaults.set("unchanged", forKey: "Unrelated")
        var settings = PendantSettings()
        try settings.set(333, for: .length)
        store.save(settings, parameter: .length)
        try expectEqual(defaults.double(forKey: "RopeLength.rope"), 333)
        try expectNil(defaults.object(forKey: "RopeLength"))
        try expectNil(defaults.object(forKey: "RopeLength.balloon"))
        try expectNil(defaults.object(forKey: "PigSize.rope"))
        try expectNil(defaults.object(forKey: "DisplayMode"))
        try expectNil(defaults.object(forKey: "GhostOffsetX"))
        try expectNil(defaults.object(forKey: "GhostOffsetY"))
        try expectEqual(defaults.string(forKey: "Unrelated"), "unchanged")
    }

    func testGhostOffsetsRoundTripIndependentlyOfMode() throws {
        var settings = PendantSettings()
        try settings.set(127, for: .horizontal)
        try settings.set(-84, for: .vertical)
        for axis in GhostOffsetAxis.allCases { store.saveGhostOffset(settings, axis: axis) }

        for mode in DisplayMode.allCases {
            store.saveMode(mode)
            let loaded = store.load()
            try expectEqual(loaded.mode, mode)
            try expectEqual(loaded[.horizontal], 127)
            try expectEqual(loaded[.vertical], -84)
        }
    }

    func testCorruptSavedValuesUseDefaultsAndFiniteValuesClamp() throws {
        defaults.set("invalid-mode", forKey: "DisplayMode")
        defaults.set(Double.nan, forKey: "Weight")
        defaults.set("not-a-number", forKey: "PigSize")
        defaults.set(9999, forKey: "RopeLength")
        defaults.set(-20, forKey: "BalloonCount")
        defaults.set(Double.infinity, forKey: "GhostOffsetX")
        defaults.set("not-a-number", forKey: "GhostOffsetY")
        let settings = store.load()
        try expectEqual(settings.mode, .rope)
        try expectEqual(settings[.weight], ParameterID.weight.defaultValue)
        try expectEqual(settings[.size], ParameterID.size.defaultValue)
        try expectEqual(settings[.length], 1200)
        try expectEqual(settings[.horizontal], GhostOffsetAxis.horizontal.defaultValue)
        try expectEqual(settings[.vertical], GhostOffsetAxis.vertical.defaultValue)
        try expectEqual(settings.balloonCount, 1)
    }

    func testModeSpecificLabelsDoNotChangeStorageKeys() throws {
        try expectEqual(ParameterID.length.title(mode: .bamboo), "竹子长度")
        try expectEqual(ParameterID.elasticity.title(mode: .bamboo), "竹子弹性")
        try expectEqual(ParameterID.gravity.title(mode: .balloon), "浮力")
        try expectEqual(ParameterID.gravity.title(mode: .net), "重力")
        try expectEqual(ParameterID.sway.title(mode: .rope), "拱身晃动")
        try expectEqual(ParameterID.sway.range, 0...200)
        try expectEqual(ParameterID.sway.defaultValue, 100)
        try expectEqual(ParameterID.sway.readout(125), "125%")
        try expectEqual(ParameterID.sway.storageKey(for: .rope), "NudgeSwingAmplitude.rope")
        try expectEqual(ParameterID.length.storageKey, "RopeLength")
        try expectEqual(ParameterID.length.storageKey(for: .rope), "RopeLength.rope")
        try expectEqual(ParameterID.length.storageKey(for: .balloon), "RopeLength.balloon")
    }
}
