// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlassGridYou",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "YouTubeMacCore",
            targets: ["YouTubeMacCore"]
        ),
        .executable(
            name: "YouTubeMac",
            targets: ["YouTubeMac"]
        ),
        .executable(
            name: "glassgrid",
            targets: ["GlassGridCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "YouTubeMacCore"
        ),
        .executableTarget(
            name: "YouTubeMac",
            dependencies: [
                "YouTubeMacCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .copy("Resources/Fonts")
            ]
        ),
        .executableTarget(
            name: "GlassGridCLI",
            dependencies: ["YouTubeMacCore"]
        ),
        .testTarget(
            name: "YouTubeMacCoreTests",
            dependencies: ["YouTubeMacCore"]
        )
    ]
)
