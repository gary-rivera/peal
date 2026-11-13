// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Peal",
    platforms: [.macOS(.v13)],
    targets: [
        // Timer rules, scheduling, validation, settings. Foundation only.
        .target(name: "PealCore"),
        // The AppKit menu bar app.
        .executableTarget(name: "Peal", dependencies: ["PealCore"]),
        .testTarget(name: "PealCoreTests", dependencies: ["PealCore"]),
    ],
    swiftLanguageModes: [.v6]
)
