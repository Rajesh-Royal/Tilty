// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tilty",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure geometry and state logic. No AppKit or Accessibility here, so it is easy to test.
        .target(name: "TiltyCore"),
        // The menu bar app itself.
        .executableTarget(
            name: "Tilty",
            dependencies: ["TiltyCore"]
        ),
        .testTarget(
            name: "TiltyCoreTests",
            dependencies: ["TiltyCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
