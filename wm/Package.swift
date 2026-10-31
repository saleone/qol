// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplaySplit",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure geometry: column math and coordinate conversion. No AppKit, unit-tested.
        .target(name: "DisplaySplitCore"),
        // Menu bar app: Accessibility window moving, window-created observers, hotkeys.
        .executableTarget(name: "DisplaySplit", dependencies: ["DisplaySplitCore"]),
        .testTarget(name: "DisplaySplitCoreTests", dependencies: ["DisplaySplitCore"]),
    ]
)
