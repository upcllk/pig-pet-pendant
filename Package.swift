// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PigPendant",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "PigPendantCore", targets: ["PigPendantCore"]),
        .executable(name: "PigPendantCoreChecks", targets: ["PigPendantCoreChecks"])
    ],
    targets: [
        .target(
            name: "PigPendantCore",
            path: "PigPendant",
            exclude: ["App", "Platform", "Presentation", "UI", "Resources", "Info.plist", "main.swift"],
            sources: ["Core", "Settings"]
        ),
        .executableTarget(
            name: "PigPendantCoreChecks",
            dependencies: ["PigPendantCore"],
            path: "Tests/Core"
        )
    ]
)
