// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Peal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Peal", path: "Sources/Peal"),
    ],
    swiftLanguageModes: [.v6]
)
