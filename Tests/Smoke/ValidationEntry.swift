import Foundation

func handleValidationArguments() {
    if CommandLine.arguments.contains("--cleanup-preferences") {
        do {
            let preferences = try ValidationPreferences()
            try preferences.remove()
            exit(0)
        } catch {
            fputs("Validation preference cleanup failed: \(error)\n", stderr)
            exit(1)
        }
    }
    if CommandLine.arguments.contains("--self-test") {
        runPhysicsTests()
        exit(0)
    }
}
