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
            ]
        ),
        .testTarget(
            name: "YouTubeMacCoreTests",
            dependencies: ["YouTubeMacCore"]
        )
    ]
)
