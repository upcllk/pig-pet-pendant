import Foundation
@testable import PigPendantCore

final class SettingsTests {
    private var domain: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    func setUpWithError() throws {
        domain = "local.pigpendant.unit-tests.\(UUID().uuidString)"
        defaults = try requireValue(UserDefaults(suiteName: domain))
        store = SettingsStore(defaults: defaults)
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
        try expectEqual(settings.musicReactiveEnabled, false)
        try expectEqual(settings.balloonCount, 2)
        try expectEqual(ParameterID.allCases.map(\.storageKey),
                       ["RopeLength", "PigSize", "Weight", "Elasticity", "DampingRate", "Gravity"])
        try expectEqual(ParameterID.allCases.map { settings[$0] }, [140, 48, 65, 55, -60 * log(0.985), 1350])
        try expectEqual(PendantSettings.countRange, 1...8)
        try expectEqual(ParameterID.allCases.map(\.range), [20...1200, 16...256, 0...200, 0...200, 0.2...8, 100...10000])
        try expectEqual(GhostOffsetAxis.allCases.map(\.storageKey), ["GhostOffsetX", "GhostOffsetY"])
        try expectEqual(settings[.horizontal], 44)
        try expectEqual(settings[.vertical], 32)
        try expectEqual(GhostOffsetAxis.range, -300...300)
        for mode in DisplayMode.allCases {
            for parameter in ParameterID.allCases {
                try expectEqual(settings[parameter, mode: mode], parameter.defaultValue)
                try expectEqual(defaults.double(forKey: parameter.storageKey(for: mode)), parameter.defaultValue)
            }
        }
    }

    func testMusicReactiveSettingRoundTrip() throws {
        var settings = store.load()
        try expectEqual(settings.musicReactiveEnabled, false)
        settings.musicReactiveEnabled = true
        store.saveMusicReactiveEnabled(settings.musicReactiveEnabled)
        try expectEqual(defaults.bool(forKey: "SystemAudioReactiveEnabled"), true)
        try expectEqual(store.load().musicReactiveEnabled, true)
        store.saveMusicReactiveEnabled(false)
        try expectEqual(store.load().musicReactiveEnabled, false)
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
        let legacyValues = [333.0, 88, 77, 44, 1.25, 1700]
        for (index, parameter) in ParameterID.allCases.enumerated() {
            defaults.set(legacyValues[index], forKey: parameter.storageKey)
        }

        let settings = store.load()
        for mode in DisplayMode.allCases {
            for (index, parameter) in ParameterID.allCases.enumerated() {
                try expectEqual(settings[parameter, mode: mode], legacyValues[index])
                try expectEqual(defaults.double(forKey: parameter.storageKey(for: mode)), legacyValues[index])
            }
        }

        var ropeSettings = settings
        try ropeSettings.set(555, for: .length, mode: .rope)
        store.save(ropeSettings, parameter: .length, mode: .rope)
        let reloaded = store.load()
        try expectEqual(reloaded[.length, mode: .rope], 555)
        for mode in DisplayMode.allCases where mode != .rope {
            try expectEqual(reloaded[.length, mode: mode], legacyValues[0])
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
        try expectEqual(ParameterID.length.storageKey, "RopeLength")
        try expectEqual(ParameterID.length.storageKey(for: .rope), "RopeLength.rope")
        try expectEqual(ParameterID.length.storageKey(for: .balloon), "RopeLength.balloon")
    }
}
