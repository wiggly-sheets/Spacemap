// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "spacemap",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Spacemap", targets: ["spacemap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "spacemap",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/spacemap",
            exclude: ["Info.plist"],
            resources: [
                .process("AppIcon.icns"),
                .process("spacemap.icns"),
                .process("Assets.xcassets"),
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "spacemapTests",
            dependencies: ["spacemap"],
            path: "Tests/spacemapTests"
        )
    ]
)
