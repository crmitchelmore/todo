// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CaptureCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "CaptureCore", targets: ["CaptureCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/powersync-ja/powersync-swift", from: "1.14.1")
    ],
    targets: [
        .target(
            name: "CaptureCore",
            dependencies: [
                .product(name: "PowerSync", package: "powersync-swift")
            ]
        ),
        .executableTarget(
            name: "CaptureProbe",
            dependencies: ["CaptureCore"]
        ),
        .testTarget(
            name: "CaptureCoreTests",
            dependencies: ["CaptureCore"]
        )
    ]
)
