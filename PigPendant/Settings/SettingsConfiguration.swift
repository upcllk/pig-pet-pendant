import Foundation

private struct SettingsConfigurationFile: Decodable {
    let parameters: [String: [String: Double]]
    let balloonCount: Int
    let bambooPosition: Double
    let ghostOffsets: [String: Double]
}

enum SettingsConfiguration {
    static func installBundledDefaults(bundle: Bundle = .main,
                                       fileManager: FileManager = .default) throws -> URL {
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else {
            throw SettingsConfigurationError.applicationSupportUnavailable
        }
        let directory = supportDirectory.appendingPathComponent("PigPendant", isDirectory: true)
        let destination = directory.appendingPathComponent("default-settings.json")
        if !fileManager.fileExists(atPath: destination.path) {
            guard let source = bundle.url(forResource: "default-settings", withExtension: "json") else {
                throw SettingsConfigurationError.bundledFileMissing
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        } else if let bundledDefaults = bundle.url(forResource: "default-settings", withExtension: "json") {
            try migrateMissingWaveGhostDefaults(at: destination, bundledDefaultsURL: bundledDefaults)
        }
        return destination
    }

    static func migrateMissingWaveGhostDefaults(at url: URL, bundledDefaultsURL: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var parameters = root["parameters"] as? [String: Any] else { return }

        let legacyModes = Set(DisplayMode.allCases.map(\.rawValue))
            .subtracting([DisplayMode.ghostWave.rawValue])
        guard Set(parameters.keys) == legacyModes else { return }

        let bundledData = try Data(contentsOf: bundledDefaultsURL)
        guard let bundledRoot = try JSONSerialization.jsonObject(with: bundledData) as? [String: Any],
              let bundledParameters = bundledRoot["parameters"] as? [String: Any],
              let waveDefaults = bundledParameters[DisplayMode.ghostWave.rawValue] else {
            throw SettingsConfigurationError.bundledFileMissing
        }

        parameters[DisplayMode.ghostWave.rawValue] = waveDefaults
        var migratedRoot = root
        migratedRoot["parameters"] = parameters
        let migratedData = try JSONSerialization.data(withJSONObject: migratedRoot,
                                                      options: [.prettyPrinted, .sortedKeys])
        try migratedData.write(to: url, options: .atomic)
    }

    static func load(from url: URL?) throws -> PendantSettings {
        guard let url else { return PendantSettings() }
        let file: SettingsConfigurationFile
        do {
            file = try JSONDecoder().decode(SettingsConfigurationFile.self, from: Data(contentsOf: url))
        } catch {
            throw SettingsConfigurationError.invalid(url, error.localizedDescription)
        }

        let expectedModes = Set(DisplayMode.allCases.map(\.rawValue))
        guard Set(file.parameters.keys) == expectedModes else {
            throw SettingsConfigurationError.invalid(url, "parameters 必须包含全部模式：\(expectedModes.sorted().joined(separator: ", "))")
        }
        let expectedParameters = Set(ParameterID.allCases.map(\.configurationKey))
        var settings = PendantSettings()
        for mode in DisplayMode.allCases {
            guard let configured = file.parameters[mode.rawValue],
                  Set(configured.keys) == expectedParameters else {
                throw SettingsConfigurationError.invalid(url, "\(mode.rawValue) 必须包含全部七项参数")
            }
            for parameter in ParameterID.allCases {
                guard let value = configured[parameter.configurationKey], value.isFinite,
                      parameter.range.contains(value) else {
                    throw SettingsConfigurationError.invalid(
                        url, "\(mode.rawValue).\(parameter.configurationKey) 必须是 \(parameter.range.lowerBound)...\(parameter.range.upperBound) 范围内的有限数值"
                    )
                }
                try settings.set(value, for: parameter, mode: mode)
            }
        }
        guard (PendantSettings.countRange).contains(file.balloonCount) else {
            throw SettingsConfigurationError.invalid(url, "balloonCount 必须在 \(PendantSettings.countRange) 范围内")
        }
        guard BambooPigPosition.range.contains(file.bambooPosition) else {
            throw SettingsConfigurationError.invalid(url, "bambooPosition 必须在 \(BambooPigPosition.range) 范围内")
        }
        settings.setCount(file.balloonCount)
        settings.bambooPosition = file.bambooPosition

        let expectedAxes = Set(GhostOffsetAxis.allCases.map(\.configurationKey))
        guard Set(file.ghostOffsets.keys) == expectedAxes else {
            throw SettingsConfigurationError.invalid(url, "ghostOffsets 必须包含 horizontal 和 vertical")
        }
        for axis in GhostOffsetAxis.allCases {
            guard let value = file.ghostOffsets[axis.configurationKey],
                  GhostOffsetAxis.range.contains(value) else {
                throw SettingsConfigurationError.invalid(url, "\(axis.configurationKey) 必须在 \(GhostOffsetAxis.range) 范围内")
            }
            try settings.set(value, for: axis)
        }
        return settings
    }
}

enum SettingsConfigurationError: LocalizedError {
    case applicationSupportUnavailable
    case bundledFileMissing
    case invalid(URL, String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "无法定位用户的 Application Support 目录。"
        case .bundledFileMissing:
            return "应用包中缺少 default-settings.json。"
        case .invalid(let url, let reason):
            return "默认参数配置无效（\(url.path)）：\(reason)"
        }
    }
}
