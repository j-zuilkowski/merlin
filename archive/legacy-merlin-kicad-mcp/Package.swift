// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "merlin-kicad-mcp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "merlin-kicad-mcp",
            dependencies: ["KiCadMCPKit"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "KiCadMCPKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "KiCadMCPKitTests",
            dependencies: ["KiCadMCPKit"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
