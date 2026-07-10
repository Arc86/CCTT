// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCTT",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "CCTTApp",
            dependencies: [
                "CCTTCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CCTTCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CCTTCoreTests",
            dependencies: ["CCTTCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
