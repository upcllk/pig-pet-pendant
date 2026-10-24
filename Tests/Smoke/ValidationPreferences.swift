import Foundation

struct ValidationPreferences {
    let domain: String
    let defaults: UserDefaults

    init() throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--preferences-suite"),
              CommandLine.arguments.indices.contains(index + 1) else {
            throw ValidationError.missingPreferencesSuite
        }
        let name = CommandLine.arguments[index + 1]
        let prefix = "local.pigpendant.smoke-tests."
        guard name.hasPrefix(prefix),
              UUID(uuidString: String(name.dropFirst(prefix.count))) != nil,
              let defaults = UserDefaults(suiteName: name) else {
            throw ValidationError.missingPreferencesSuite
        }
        domain = name
        self.defaults = defaults
    }

    func remove() throws {
        defaults.removePersistentDomain(forName: domain)
        guard defaults.synchronize(),
              defaults.persistentDomain(forName: domain)?.isEmpty != false else {
            throw ValidationError.cleanupFailed(domain)
        }
        // UserDefaults can leave an empty plist after deleting the final key.
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
            .appendingPathComponent("\(domain).plist")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum ValidationError: LocalizedError {
    case missingPreferencesSuite
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPreferencesSuite:
            return "GUI validation requires --preferences-suite local.pigpendant.smoke-tests.<UUID>"
        case .cleanupFailed(let domain):
            return "Failed to clear validation preferences: \(domain)"
        }
    }
}
