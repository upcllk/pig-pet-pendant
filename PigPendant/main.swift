import AppKit
import Foundation

#if TESTING
handleValidationArguments()
#else
if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--smoke-test") {
    fputs("This is a release app. Run ./build.sh --test to build and run validation.\n", stderr)
    exit(2)
}
#endif

let app = NSApplication.shared
private let delegate = PigAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 不占用 Dock，常驻菜单栏
app.run()
