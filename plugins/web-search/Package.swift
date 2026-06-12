// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WebSearchPlugin",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "web-search-plugin", targets: ["WebSearchPlugin"]),
    ],
    targets: [
        .executableTarget(
            name: "WebSearchPlugin",
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "WebSearchPluginTests",
            dependencies: ["WebSearchPlugin"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
