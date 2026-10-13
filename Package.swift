// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flipside",
    platforms: [.macOS(.v14)],
    targets: [
        // Display geometry and the CoreGraphics calls that rearrange displays. No UI.
        .target(name: "FlipsideCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // The menu bar app.
        .executableTarget(
            name: "Flipside",
            dependencies: ["FlipsideCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FlipsideCoreTests",
            dependencies: ["FlipsideCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Development only: drives FlipsideCore against a temporary virtual display,
        // so the arrangement code can be exercised without a second monitor plugged in.
        .target(name: "CVirtualDisplay", path: "Tools/CVirtualDisplay"),
        .executableTarget(
            name: "flipside-e2e",
            dependencies: ["FlipsideCore", "CVirtualDisplay"],
            path: "Tools/flipside-e2e",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
