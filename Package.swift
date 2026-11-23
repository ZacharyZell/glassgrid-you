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
    targets: [
        .target(
            name: "YouTubeMacCore"
        ),
        .executableTarget(
            name: "YouTubeMac",
            dependencies: ["YouTubeMacCore"]
        ),
        .testTarget(
            name: "YouTubeMacCoreTests",
            dependencies: ["YouTubeMacCore"]
        )
    ]
)
