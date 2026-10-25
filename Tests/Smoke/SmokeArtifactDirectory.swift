import Foundation

enum SmokeArtifactDirectory {
    static let url: URL = {
        let url = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("previews", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Cannot create smoke artifact directory: \(error)")
        }
        return url
    }()
}
